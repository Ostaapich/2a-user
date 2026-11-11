import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn, execFileSync } from 'node:child_process';
import { mkdtemp, readFile, mkdir, rm, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';

const chrome = process.env.CHROME_BINARY || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
let root, server, browser, cdp, session, origin;
const downloads = [], requests = [];
const bytes = Buffer.alloc(65536, 0x37);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, ms = 20000) { const deadline = Date.now() + ms; while (Date.now() < deadline) { const result = await check(); if (result) return result; await pause(25); } throw new Error('Timed out'); }
class CDP {
  next = 0; pending = new Map(); listeners = new Map();
  constructor(ws) { this.ws = ws; ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.id) { const item = this.pending.get(message.id); this.pending.delete(message.id); if (message.error) item.reject(new Error(message.error.message)); else item.resolve(message.result); }
    else for (const listener of this.listeners.get(message.method) || []) listener(message.params, message.sessionId);
  }; }
  on(name, listener) { if (!this.listeners.has(name)) this.listeners.set(name, []); this.listeners.get(name).push(listener); }
  send(method, params = {}, sessionId) { const id = ++this.next; return new Promise((resolve, reject) => { this.pending.set(id, { resolve, reject }); this.ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) })); }); }
}
async function evaluate(expression) {
  const result = await cdp.send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true, userGesture: true }, session);
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
  return result.result.value;
}
function options(path, mode = 'download', name = 'fixture.mp4', extras = '') {
  return `({operationId:${JSON.stringify(randomUUID())},url:${JSON.stringify(origin + path)},apiBase:${JSON.stringify(origin + '/api')},name:${JSON.stringify(name)},token:'fixture-a',identity:'account-A',getIdentity:async()=>window.testIdentity,mode:${JSON.stringify(mode)},progress:(n)=>{window.received=n;${extras}}})`;
}
before(async () => {
  root = await mkdtemp(join(tmpdir(), '2a-media-export-'));
  await mkdir(join(root, 'downloads'));
  execFileSync('dart', ['compile', 'js', '-O1', '-o', join(root, 'bridge-fixture.js'), new URL('./media_export_bridge_fixture.dart', import.meta.url).pathname], { timeout: 60000, stdio: 'pipe' });
  server = createServer(async (request, response) => {
    requests.push({ url: request.url, auth: request.headers.authorization });
    if (request.url === '/') { response.setHeader('Content-Type', 'text/html'); response.end('<!doctype html><title>Media fixture</title><div id="viewer">Viewer</div><script src="/media-export.js"></script><script src="/bridge-fixture.js"></script>'); return; }
    if (request.url === '/bridge-fixture.js') { response.setHeader('Content-Type', 'application/javascript'); response.end(await readFile(join(root, 'bridge-fixture.js'))); return; }
    if (['/media-export.js', '/media-export/worker.js'].includes(request.url)) { response.setHeader('Content-Type', 'application/javascript'); response.setHeader('Cache-Control', 'no-store'); response.end(await readFile(new URL('../../web' + request.url, import.meta.url))); return; }
    if (request.url === '/api/uploads/redirect.mp4') { response.writeHead(307, {Location: origin + '/must-not-receive-token'}); response.end(); return; }
    if (request.url.startsWith('/api/uploads/')) {
      if (request.headers.authorization !== 'Bearer fixture-a') { response.writeHead(401); response.end(); return; }
      const total = request.url.includes('small') ? 1024 * 1024 : 64 * 1024 * 1024;
      response.setHeader('Content-Type', 'video/mp4'); response.setHeader('Cache-Control', 'no-store');
      if (!request.url.includes('unknown')) response.setHeader('Content-Length', total);
      let sent = 0, timer;
      response.on('close', () => clearTimeout(timer));
      const write = () => {
        if (response.destroyed) return;
        if (sent >= total) { response.end(); return; }
        sent += bytes.length;
        if (response.write(bytes)) timer = setTimeout(write, 1); else response.once('drain', () => { timer = setTimeout(write, 1); });
      }; write(); return;
    }
    response.writeHead(404); response.end('not found');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = spawn(chrome, ['--headless=new', '--disable-gpu', '--disable-background-networking', '--disable-component-update', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', '--user-data-dir=' + join(root, 'profile')], { stdio: 'ignore' });
  const port = await until(async () => { try { return (await readFile(join(root, 'profile', 'DevToolsActivePort'), 'utf8')).split('\n'); } catch { return null; } });
  const ws = new WebSocket(`ws://127.0.0.1:${port[0]}${port[1]}`);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  cdp = new CDP(ws);
  cdp.on('Browser.downloadWillBegin', event => downloads.push({ ...event, state: 'started' }));
  cdp.on('Browser.downloadProgress', event => { const item = downloads.find(d => d.guid === event.guid); if (item) Object.assign(item, event); });
  await cdp.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: join(root, 'downloads'), eventsEnabled: true });
  const target = await cdp.send('Target.createTarget', { url: origin });
  ({ sessionId: session } = await cdp.send('Target.attachToTarget', { targetId: target.targetId, flatten: true }));
  await cdp.send('Runtime.enable', {}, session);
  await until(async () => { try { return await evaluate('!!window.twoaBrowserMediaExports && !!window.dartExport'); } catch { return false; } });
}, { timeout: 40000 });
after(async () => {
  const exited = browser && browser.exitCode === null
    ? new Promise(resolve => browser.once('exit', resolve)) : Promise.resolve();
  try { await cdp?.send('Browser.close'); } catch (_) {}
  browser?.kill();
  await Promise.race([exited, pause(3000)]);
  if (server) await new Promise(resolve => server.close(resolve));
  if (root) await rm(root, { recursive: true, force: true, maxRetries: 8, retryDelay: 100 });
});

test('64MiB authenticated original reaches browser download with correct bytes and no Blob', { timeout: 30000 }, async () => {
  await evaluate(`window.testIdentity='account-A';window.received=0;window.originalBlob=Blob;window.Blob=class {constructor(){throw Error('Blob forbidden')}};`);
  const result = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/large.mp4', 'download', 'large.mp4')})`);
  assert.equal(result.kind, 'downloaded');
  const item = await until(() => downloads.find(d => d.suggestedFilename === 'large.mp4' && d.state === 'completed'));
  assert.ok(!item.url.includes('fixture-a')); assert.match(item.url, /\/media-export\/d\/[a-f0-9-]+$/);
  assert.equal((await stat(join(root, 'downloads', 'large.mp4'))).size, 64 * 1024 * 1024);
  const hash = createHash('sha256'); for await (const chunk of createReadStream(join(root, 'downloads', 'large.mp4'))) hash.update(chunk);
  const expected = createHash('sha256'); for (let i = 0; i < 1024; i++) expected.update(bytes);
  assert.equal(hash.digest('hex'), expected.digest('hex'));
  assert.ok(requests.filter(r => r.url.startsWith('/api/uploads/')).every(r => r.auth === 'Bearer fixture-a'));
  await evaluate('window.Blob=window.originalBlob');
});

test('account change cancels the original instead of completing another account file', { timeout: 20000 }, async () => {
  await evaluate("window.testIdentity='account-A';window.received=0");
  const result = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/cancel.mp4', 'download', 'cancel.mp4', "if(n>=1048576)window.testIdentity='account-B';")}).then(()=> 'unexpected', e=>e.code)`);
  assert.equal(result, 'session_changed');
  await until(() => downloads.find(d => d.suggestedFilename === 'cancel.mp4' && d.state === 'canceled'));
  assert.ok(!downloads.find(d => d.suggestedFilename === 'cancel.mp4' && d.state === 'completed'));
});

test('unknown-length oversized sharing restarts as streaming download without an oversized File', { timeout: 30000 }, async () => {
  await evaluate(`window.testIdentity='account-A';Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});Object.defineProperty(navigator,'share',{configurable:true,value:async()=>{throw Error('must not share large file')}});window.OriginalFile=File;window.File=class extends window.OriginalFile{constructor(parts,name,options){super(parts,name,options);if(this.size>8*1024*1024)throw Error('oversized File')}};`);
  const result = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/unknown.mp4', 'share', 'unknown.mp4')})`);
  assert.equal(result.kind, 'downloaded');
  await until(() => downloads.find(d => d.suggestedFilename === 'unknown.mp4' && d.state === 'completed'));
  assert.equal((await stat(join(root, 'downloads', 'unknown.mp4'))).size, 64 * 1024 * 1024);
  await evaluate('window.File=window.OriginalFile');
});

test('small file requires explicit second share tap and prepared file is revoked on logout', async () => {
  await evaluate(`window.testIdentity='account-A';window.sharedSize=0;Object.defineProperty(navigator,'share',{configurable:true,value:async({files})=>{window.sharedSize=files[0].size}});`);
  const result = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/small.mp4', 'share', 'small.mp4')})`);
  assert.equal(result.kind, 'shareReady'); assert.equal(await evaluate('window.sharedSize'), 0);
  assert.equal((await evaluate(`twoaBrowserMediaExports.sharePrepared(${JSON.stringify(result.preparedId)})`)).kind, 'shared');
  assert.equal(await evaluate('window.sharedSize'), 1024 * 1024);
  const next = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/small.mp4', 'share', 'small.mp4')})`);
  await evaluate('twoaBrowserMediaExports.cancelAll()');
  assert.equal(await evaluate(`twoaBrowserMediaExports.sharePrepared(${JSON.stringify(next.preparedId)}).catch(e=>e.code)`), 'share_expired');
});

test('foreign private origin, non-media endpoint and malformed filename are rejected before fetch', async () => {
  const count = requests.filter(r => r.url.startsWith('/api/')).length;
  const opts = options('/api/uploads/small.mp4');
  for (const change of ["url:'https://foreign.invalid/api/uploads/a.jpg'", `url:${JSON.stringify(origin + '/api/client/profile')}`, "name:'../secret'", "url:'data:text/plain,hi'"]) {
    const code = await evaluate(`twoaBrowserMediaExports.begin({...${opts},${change}}).catch(e=>e.code)`);
    assert.ok(['invalid_url', 'invalid_private_url', 'invalid_request'].includes(code), code);
  }
  assert.equal(requests.filter(r => r.url.startsWith('/api/')).length, count);
});


test('compiled Dart bridge streams real bytes and normalizes session cancellation', { timeout: 30000 }, async () => {
  await evaluate("window.testIdentity='account-A';window.dartReceived=0");
  const args = [origin + '/api/uploads/small.mp4', origin + '/api', 'dart-small.mp4', randomUUID()].map(JSON.stringify).join(',');
  const result = await evaluate(`dartExport(${args})`);
  assert.equal(result.kind, 'downloaded');
  await until(() => downloads.find(d => d.suggestedFilename === 'dart-small.mp4' && d.state === 'completed'));
  assert.equal(await evaluate('window.dartReceived'), 1024 * 1024);
  await evaluate("window.testIdentity='account-B'");
  const rejected = await evaluate(`dartExport(${args})`);
  assert.equal(rejected.error, 'session_changed');
});

test('completed sink cannot be replayed or read over the network', async () => {
  const url = downloads.find(d => d.suggestedFilename === 'large.mp4').url;
  const target = await cdp.send('Target.createTarget', { url });
  const attached = await cdp.send('Target.attachToTarget', { targetId: target.targetId, flatten: true });
  try {
    const text = await until(async () => {
      try {
        const result = await cdp.send('Runtime.evaluate', { expression: 'document.body?.textContent', returnByValue: true }, attached.sessionId);
        return result.result?.value === 'Download expired' ? result.result.value : null;
      } catch { return null; }
    });
    assert.equal(text, 'Download expired');
    assert.ok(!requests.some(r => r.url.startsWith('/media-export/d/')));
  } finally { await cdp.send('Target.closeTarget', { targetId: target.targetId }); }
});


test('authorization denial and redirects never become a successful download', async () => {
  await evaluate("window.testIdentity='account-A'");
  const completed = downloads.filter(d => d.state === 'completed').length;
  assert.equal(await evaluate(`twoaBrowserMediaExports.begin({...${options('/api/uploads/denied.mp4')},token:'invalid'}).catch(e=>e.code)`), 'media_denied');
  assert.equal(await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/redirect.mp4')}).catch(e=>e.code)`), 'stream_failed');
  assert.ok(!requests.some(r => r.url === '/must-not-receive-token'));
  assert.equal(downloads.filter(d => d.state === 'completed').length, completed);
});

test('explicit cancellation stops one operation while closing viewer DOM does not stop download', { timeout: 30000 }, async () => {
  await evaluate("window.testIdentity='account-A'");
  const id = randomUUID();
  const expression = `{...${options('/api/uploads/cancel-one.mp4', 'download', 'cancel-one.mp4')},operationId:${JSON.stringify(id)},progress:()=>twoaBrowserMediaExports.cancel(${JSON.stringify(id)})}`;
  assert.equal(await evaluate(`twoaBrowserMediaExports.begin(${expression}).catch(e=>e.code)`), 'cancelled');
  await until(() => downloads.find(d => d.suggestedFilename === 'cancel-one.mp4' && d.state === 'canceled'));
  const result = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/after-viewer-close.mp4', 'download', 'after-viewer-close.mp4', "document.getElementById('viewer')?.remove();")})`);
  assert.equal(result.kind, 'downloaded');
  await until(() => downloads.find(d => d.suggestedFilename === 'after-viewer-close.mp4' && d.state === 'completed'));
  assert.equal((await stat(join(root, 'downloads', 'after-viewer-close.mp4'))).size, 64 * 1024 * 1024);
});


test('unsupported streaming keeps small downloads and rejects large before Blob buffering', { timeout: 20000 }, async () => {
  await evaluate("window.testIdentity='account-A';Object.defineProperty(navigator,'serviceWorker',{configurable:true,get:()=>undefined})");
  try {
    const small = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/small.mp4', 'download', 'old-browser-small.mp4')})`);
    assert.equal(small.kind, 'downloaded');
    await until(() => downloads.find(d => d.suggestedFilename === 'old-browser-small.mp4' && d.state === 'completed'));
    await evaluate("window.savedBlob=Blob;window.Blob=class{constructor(){throw Error('large Blob forbidden')}}");
    assert.equal(await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/large.mp4', 'download', 'old-browser-large.mp4')}).catch(e=>e.code)`), 'streaming_unavailable');
    assert.ok(!downloads.find(d => d.suggestedFilename === 'old-browser-large.mp4'));
  } finally { await evaluate('window.Blob=window.savedBlob;delete navigator.serviceWorker;twoaBrowserMediaExports.cancelAll()'); }
});

test('SW registration rejection uses bounded small fallback and rejects large honestly', { timeout: 20000 }, async () => {
  await evaluate(`window.testIdentity='account-A';window.realRegister=navigator.serviceWorker.register;navigator.serviceWorker.register=async()=>{throw new DOMException('Blocked','SecurityError')}`);
  try {
    const small = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/small.mp4', 'download', 'register-denied-small.mp4')})`);
    assert.equal(small.kind, 'downloaded');
    await until(() => downloads.find(d => d.suggestedFilename === 'register-denied-small.mp4' && d.state === 'completed'));
    assert.equal(await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/large.mp4', 'download', 'register-denied-large.mp4')}).catch(e=>e.code)`), 'streaming_unavailable');
    assert.ok(!downloads.find(d => d.suggestedFilename === 'register-denied-large.mp4'));
  } finally { await evaluate('navigator.serviceWorker.register=window.realRegister;twoaBrowserMediaExports.cancelAll()'); }
});

test('cross-tab auth storage events revoke prepared files and active transfers only for auth keys', { timeout: 20000 }, async () => {
  await evaluate(`window.testIdentity='account-A';Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});Object.defineProperty(navigator,'share',{configurable:true,value:async()=>{}})`);
  const first = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/small.mp4', 'share', 'storage-first.mp4')})`);
  await evaluate(`dispatchEvent(new StorageEvent('storage',{key:'unrelated_setting'}))`);
  assert.equal((await evaluate(`twoaBrowserMediaExports.sharePrepared(${JSON.stringify(first.preparedId)})`)).kind, 'shared');
  for (const key of ['auth_token', 'flutter.auth_token', null]) {
    const next = await evaluate(`twoaBrowserMediaExports.begin(${options('/api/uploads/small.mp4', 'share', 'storage-revoked.mp4')})`);
    await evaluate(`dispatchEvent(new StorageEvent('storage',{key:${JSON.stringify(key)}}))`);
    assert.equal(await evaluate(`twoaBrowserMediaExports.sharePrepared(${JSON.stringify(next.preparedId)}).catch(e=>e.code)`), 'share_expired');
  }
  const expression = options('/api/uploads/storage-active.mp4', 'download', 'storage-active.mp4', `if(n===65536)dispatchEvent(new StorageEvent('storage',{key:'flutter.auth_token'}));`);
  assert.equal(await evaluate(`twoaBrowserMediaExports.begin(${expression}).catch(e=>e.code)`), 'session_changed');
  assert.ok(!downloads.find(d => d.suggestedFilename === 'storage-active.mp4' && d.state === 'completed'));
});
