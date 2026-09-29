import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(new URL('../native/Resources/GofileBridge.js', import.meta.url), 'utf8');
async function run(body, url = 'https://api.gofile.io/contents/example?page=2', method = 'GET') {
  const messages = [];
  let requests = 0;
  const window = { fetch: async () => { requests++; return new Response(JSON.stringify(body)); }, webkit: { messageHandlers: { gofile: { postMessage: value => messages.push(JSON.parse(JSON.stringify(value))) } } } };
  window.top = window;
  vm.runInNewContext(script, { window, location: new URL('https://gofile.io/d/example'), URL });
  const response = await window.fetch(url, { method });
  await new Promise(resolve => setTimeout(resolve, 30));
  return { messages, requests, body: await response.json() };
}
test('passes through the real response while exposing only file metadata', async () => {
  const body = { status: 'ok', data: { id: 'folder', name: 'Folder', type: 'folder', token: 'private', password: 'private', children: {
    f: { id: 'file', name: 'Test.png', type: 'file', size: 12, link: 'https://store5.gofile.io/download/web/file/Test.png', account: 'private' }
  } }, metadata: { totalPages: 3, account: 'private' } };
  const result = await run(body);
  assert.equal(result.requests, 1);
  assert.deepEqual(result.body, body);
  assert.equal(result.messages.length, 1);
  const value = result.messages[0];
  assert.equal(value.contentId, 'example');
  assert.equal(value.page, 2);
  assert.equal(value.totalPages, 3);
  assert.equal(value.data.children[0].size, 12);
  assert.ok(!JSON.stringify(value).includes('private'));
});
test('ignores accounts, foreign origins, and mutation requests', async () => {
  for (const [url, method] of [['https://api.gofile.io/accounts/website', 'GET'], ['https://api.gofile.io.evil.test/contents/a', 'GET'], ['https://api.gofile.io/contents/a', 'POST']]) {
    assert.equal((await run({ status: 'ok' }, url, method)).messages.length, 0);
  }
});
test('does not publish gated children or raw server errors', async () => {
  const result = await run({ status: 'ok', data: { canAccess: false, password: true, children: { a: { id: 'a', name: 'Hidden' } } } });
  assert.deepEqual(result.messages[0].data.children, []);
  assert.equal(result.messages[0].data.canAccess, false);
  const failure = await run({ status: 'error-privateDetails', message: 'private' });
  assert.equal(failure.messages[0].status, 'error');
  assert.ok(!JSON.stringify(failure.messages[0]).includes('private'));
});
test('single-file pages produce one native entry', async () => {
  const value = await run({ status: 'ok', data: { id: 'f', type: 'file', name: 'File.txt', size: 0 } });
  assert.equal(value.messages[0].data.children.length, 1);
  assert.equal(value.messages[0].data.children[0].size, 0);
});
