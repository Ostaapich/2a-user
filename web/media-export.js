/* Browser-owned download sink with bounded backpressure and account fencing. */
(() => {
  'use strict';
  const active = new Set(), prepared = new Map(), blobUrls = new Map();
  const SMALL_FILE_LIMIT = 8 * 1024 * 1024;
  const fail = code => Object.assign(new Error(code), { code });
  const safeName = name => typeof name === 'string' && name.length > 0 && name.length <= 200 && !/[\x00-\x1f\x7f/\\]/.test(name);
  const isLocal = host => ['localhost', '127.0.0.1', '[::1]'].includes(host);
  const timeout = (promise, ms, code) => {
    let timer;
    return Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(fail(code)), ms); })]).finally(() => clearTimeout(timer));
  };
  function cleanPrepared(id) {
    const item = prepared.get(id);
    if (item) { clearTimeout(item.timer); prepared.delete(id); }
  }
  function cancelAll() {
    for (const job of [...active]) job.cancel('session_changed');
    for (const id of [...prepared.keys()]) cleanPrepared(id);
    for (const [url, timer] of blobUrls) { clearTimeout(timer); URL.revokeObjectURL(url); }
    blobUrls.clear();
  }
  addEventListener('pagehide', cancelAll);
  addEventListener('storage', event => {
    if (event.key === null || event.key === 'auth_token' || event.key === 'flutter.auth_token') cancelAll();
  });
  addEventListener('beforeunload', event => {
    if (active.size) { event.preventDefault(); event.returnValue = ''; }
  });
  function validate(options) {
    if (!options || !safeName(options.name) || typeof options.getIdentity !== 'function' || typeof options.identity !== 'string' ||
        !['download', 'share'].includes(options.mode)) throw fail('invalid_request');
    if (options.operationId && !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(options.operationId)) throw fail('invalid_request');
    const url = new URL(options.url);
    if (url.username || url.password || url.hash || (url.protocol !== 'https:' && !(url.protocol === 'http:' && isLocal(url.hostname)))) throw fail('invalid_url');
    if (options.token) {
      const api = new URL(options.apiBase);
      const prefix = api.pathname.replace(/\/$/, '') + '/';
      const path = url.pathname.slice(prefix.length);
      if (url.origin !== api.origin || !url.pathname.startsWith(prefix) ||
          !/^(uploads\/|support\/attachments\/[0-9]+$|assembly-scan-media\/playback$)/.test(path) ||
          /%2e|%2f|%5c|%00|%25/i.test(url.pathname) || url.pathname.includes('\\')) throw fail('invalid_private_url');
    }
    return url;
  }
  async function identity(options) {
    if (await options.getIdentity() !== options.identity) throw fail('session_changed');
  }
  async function worker() {
    if (!isSecureContext || !navigator.serviceWorker || !globalThis.ReadableStream || !globalThis.MessageChannel) throw fail('streaming_unavailable');
    let registration;
    try { registration = await navigator.serviceWorker.register('/media-export/worker.js', { scope: '/media-export/', updateViaCache: 'none' }); }
    catch (_) { throw fail('streaming_unavailable'); }
    const instance = registration.active || registration.installing || registration.waiting;
    if (!instance) throw fail('streaming_unavailable');
    if (instance.state !== 'activated') await timeout(new Promise((resolve, reject) => {
      const listener = () => {
        if (instance.state === 'activated') { instance.removeEventListener('statechange', listener); resolve(); }
        else if (instance.state === 'redundant') { instance.removeEventListener('statechange', listener); reject(fail('streaming_unavailable')); }
      };
      instance.addEventListener('statechange', listener); listener();
    }), 15000, 'streaming_unavailable');
    return instance;
  }
  async function boundedSmallDownload(response, options) {
    if (Number(response.headers.get('content-length')) > SMALL_FILE_LIMIT) throw fail('streaming_unavailable');
    const reader = response.body.getReader(), parts = []; let size = 0;
    try {
      while (true) {
        await identity(options);
        const next = await timeout(reader.read(), 45000, 'network_timeout');
        if (next.done) break;
        size += next.value.length;
        if (size > SMALL_FILE_LIMIT) { await reader.cancel(); throw fail('streaming_unavailable'); }
        parts.push(next.value);
      }
      await identity(options);
      if (size === 0) throw fail('media_denied');
      const url = URL.createObjectURL(new Blob(parts, { type: 'application/octet-stream' }));
      const anchor = document.createElement('a'); anchor.href = url; anchor.download = options.name;
      document.body.append(anchor); anchor.click(); anchor.remove();
      const timer = setTimeout(() => { URL.revokeObjectURL(url); blobUrls.delete(url); }, 30000);
      blobUrls.set(url, timer);
      return { kind: 'downloaded' };
    } finally { reader.releaseLock(); }
  }
  async function relay(response, options, job) {
    let instance;
    try { instance = await worker(); }
    catch (error) {
      if (error.code === 'streaming_unavailable') return boundedSmallDownload(response, options);
      throw error;
    }
    await identity(options);
    const channel = new MessageChannel(), port = channel.port1;
    let reader, chunk = null, offset = 0, received = 0, pulling = false, readyUrl, downloadStarted = false, closed = false;
    let resolveReady, rejectReady, resolveEnd, rejectEnd;
    const ready = new Promise((resolve, reject) => { resolveReady = resolve; rejectReady = reject; });
    const ended = new Promise((resolve, reject) => { resolveEnd = resolve; rejectEnd = reject; });
    // A rejection can precede awaiting this promise during startup.
    void ended.catch(() => {});
    let iframe;
    const heartbeat = setInterval(() => instance.postMessage({ type: 'keepalive' }), 5000);
    const previousCancel = job.cancel;
    job.cancel = reason => {
      if (closed) return;
      closed = true; previousCancel(reason);
      port.postMessage({ type: 'abort' });
      rejectReady(fail(reason)); rejectEnd(fail(reason));
      void reader?.cancel().catch(() => {});
    };
    port.onmessage = async ({ data }) => {
      if (closed) return;
      try {
        if (data?.type === 'ready') {
          const expected = location.origin + '/media-export/d/' + job.id;
          if (data.url !== expected) throw fail('invalid_worker_response');
          readyUrl = data.url; resolveReady(); return;
        }
        if (data?.type === 'started') { downloadStarted = true; return; }
        if (data?.type === 'finished') { closed = true; resolveEnd(); return; }
        if (data?.type === 'cancel') { job.cancel(data.reason === 'browser_cancelled' ? 'cancelled' : 'stream_failed'); return; }
        if (data?.type !== 'pull' || pulling) throw fail('protocol_error');
        pulling = true;
        await identity(options);
        if (!reader) reader = response.body.getReader();
        if (!chunk || offset >= chunk.length) {
          const next = await timeout(reader.read(), 45000, 'network_timeout');
          if (closed) return;
          if (next.done) { if (received === 0) throw fail('media_denied'); await identity(options); port.postMessage({ type: 'end' }); pulling = false; return; }
          chunk = next.value; offset = 0;
        }
        await identity(options);
        if (closed) return;
        const part = chunk.slice(offset, Math.min(offset + 65536, chunk.length));
        offset += part.length; received += part.length;
        options.progress?.(received, Number(response.headers.get('content-length')) || -1);
        if (closed) return;
        port.postMessage({ type: 'chunk', bytes: part.buffer }, [part.buffer]);
        pulling = false;
      } catch (error) { job.cancel(error.code || 'stream_failed'); }
    };
    try {
      instance.postMessage({ version: 1, type: 'create', id: job.id, name: options.name }, [channel.port2]);
      await timeout(ready, 20000, 'streaming_unavailable');
      await identity(options);
      // Navigation is to an opaque one-use local sink; credentials stay in fetch.
      iframe = document.createElement('iframe'); iframe.hidden = true; iframe.src = readyUrl;
      document.body.append(iframe);
      await timeout((async () => {
        while (!downloadStarted && !closed) await new Promise(resolve => setTimeout(resolve, 25));
        if (!downloadStarted) throw fail('streaming_unavailable');
      })(), 15000, 'streaming_unavailable');
      await ended;
      return { kind: 'downloaded' };
    } catch (error) {
      job.cancel(error.code || 'stream_failed'); throw error;
    } finally {
      clearInterval(heartbeat); iframe?.remove();
      if (!closed) job.cancel('cancelled');
      if (!reader) void response.body.cancel().catch(() => {});
      port.close();
    }
  }
  async function smallShare(response, options, job) {
    if (!navigator.share || !navigator.canShare || Number(response.headers.get('content-length')) > SMALL_FILE_LIMIT) return null;
    const reader = response.body.getReader(), parts = []; let size = 0;
    try {
      while (true) {
        await identity(options);
        const next = await timeout(reader.read(), 45000, 'network_timeout');
        if (next.done) break;
        size += next.value.length;
        if (size > SMALL_FILE_LIMIT) { await reader.cancel(); return { restartDownload: true }; }
        parts.push(next.value);
      }
      await identity(options);
      if (size === 0) throw fail('media_denied');
      const file = new File(parts, options.name, { type: response.headers.get('content-type') || 'application/octet-stream' });
      if (!navigator.canShare({ files: [file] })) return { restartDownload: true };
      const id = crypto.randomUUID();
      if (prepared.size >= 2) cleanPrepared(prepared.keys().next().value);
      prepared.set(id, { file, timer: setTimeout(() => cleanPrepared(id), 60000) });
      return { kind: 'shareReady', preparedId: id };
    } finally { reader.releaseLock(); }
  }
  async function sharePrepared(id) {
    const item = prepared.get(id);
    if (!item) throw fail('share_expired');
    try {
      // Called directly by the second user tap, preserving transient activation.
      await navigator.share({ files: [item.file] });
      return { kind: 'shared' };
    } catch (error) {
      if (error.name === 'AbortError') return { kind: 'cancelled' };
      throw fail('share_failed');
    } finally { cleanPrepared(id); }
  }
  async function begin(options) {
    if (active.size >= 2) throw fail('busy');
    const url = validate(options);
    await identity(options);
    const controller = new AbortController();
    const job = { id: options.operationId || crypto.randomUUID(), cancel(reason) { controller.abort(fail(reason)); } };
    active.add(job);
    const sessionPoll = setInterval(() => { void identity(options).catch(() => job.cancel('session_changed')); }, 1000);
    const headers = options.token ? { Authorization: 'Bearer ' + options.token } : {};
    const get = () => timeout(fetch(url, { headers, credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer', signal: controller.signal }), 30000, 'network_timeout');
    let response;
    try {
      response = await get();
      await identity(options);
      if (response.status !== 200 || !response.body) { void response.body?.cancel(); throw fail('media_denied'); }
      if (options.mode === 'share') {
        const share = await smallShare(response, options, job);
        if (share?.kind) return share;
        if (share?.restartDownload) { response = await get(); if (response.status !== 200 || !response.body) throw fail('media_denied'); }
      }
      return await relay(response, options, job);
    } catch (error) {
      job.cancel(error.code || 'stream_failed');
      throw fail(controller.signal.reason?.code || error.code || 'stream_failed');
    } finally { clearInterval(sessionPoll); active.delete(job); }
  }
  const cancel = id => { for (const job of active) if (job.id === id) job.cancel('cancelled'); };
  globalThis.twoaBrowserMediaExports = Object.freeze({ begin, sharePrepared, cancel, cancelAll, clearPrepared: cleanPrepared });
})();
