/* One-use, same-origin byte relay. It never receives credentials or asset URLs. */
'use strict';
const pending = new Map();
const jobPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('message', event => {
  if (event.origin !== self.location.origin || !event.source?.id) return;
  if (event.data?.type === 'keepalive') return;
  const data = event.data, port = event.ports[0];
  if (data?.version !== 1 || data.type !== 'create' || !port || !jobPattern.test(data.id) ||
      typeof data.name !== 'string' || !data.name || data.name.length > 200 || /[\x00-\x1f\x7f/\\]/.test(data.name) || pending.has(data.id)) return;
  if (pending.size >= 4) { port.postMessage({ type: 'cancel', reason: 'busy' }); port.close(); return; }
  let streamController, pullDone, used = false, ended = false;
  let resolveLifetime;
  const lifetime = new Promise(resolve => { resolveLifetime = resolve; });
  const expire = setTimeout(() => fail('start_timeout'), 20000);
  function finish() {
    if (ended) return;
    ended = true; clearTimeout(expire); pending.delete(data.id);
    pullDone?.(); pullDone = null; resolveLifetime();
  }
  function fail(reason) {
    if (ended) return;
    try { streamController?.error(new Error(reason)); } catch (_) {}
    port.postMessage({ type: 'cancel', reason }); finish(); port.close();
  }
  const stream = new ReadableStream({
    start(controller) { streamController = controller; },
    pull() {
      if (ended) return;
      return new Promise(resolve => { pullDone = resolve; port.postMessage({ type: 'pull' }); });
    },
    cancel() { fail('browser_cancelled'); },
  }, { highWaterMark: 0 });
  port.onmessage = ({ data: message }) => {
    if (ended) return;
    if (message?.type === 'abort') { fail('client_cancelled'); return; }
    if (!used || !pullDone) { fail('protocol_error'); return; }
    if (message?.type === 'chunk' && message.bytes instanceof ArrayBuffer && message.bytes.byteLength > 0 && message.bytes.byteLength <= 65536) {
      streamController.enqueue(new Uint8Array(message.bytes));
      const resolve = pullDone; pullDone = null; resolve();
    } else if (message?.type === 'end') {
      streamController.close(); port.postMessage({ type: 'finished' }); finish(); port.close();
    } else { fail('protocol_error'); }
  };
  const start = () => {
    if (used || ended) return null;
    used = true; clearTimeout(expire);
    port.postMessage({ type: 'started' });
    const filename = encodeURIComponent(data.name).replace(/['()*]/g, ch => '%' + ch.charCodeAt(0).toString(16));
    return new Response(stream, { headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': "attachment; filename*=UTF-8''" + filename,
      'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'none'", 'Referrer-Policy': 'no-referrer',
    }});
  };
  pending.set(data.id, start);
  event.waitUntil(lifetime);
  port.postMessage({ type: 'ready', url: self.registration.scope + 'd/' + data.id });
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  const prefix = new URL(self.registration.scope).pathname + 'd/';
  if (url.origin !== self.location.origin || !url.pathname.startsWith(prefix)) return;
  const id = url.pathname.slice(prefix.length);
  const start = event.request.method === 'GET' && !url.search && jobPattern.test(id) ? pending.get(id) : null;
  pending.delete(id);
  const response = start?.();
  event.respondWith(response || new Response('Download expired', { status: 410, headers: { 'Cache-Control': 'no-store' } }));
});
