import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(new URL('../native/Resources/GofileBridge.js', import.meta.url), 'utf8');
async function run(body, url = 'https://api.gofile.io/contents/example?page=2', method = 'GET', options = {}) {
  const messages = [];
  let requests = 0;
  const window = { fetch: async () => { requests++; return new Response(options.raw ?? JSON.stringify(body), { status: options.status ?? 200, headers: options.headers }); }, webkit: { messageHandlers: { gofile: { postMessage: value => messages.push(JSON.parse(JSON.stringify(value))) } } } };
  window.top = window;
  vm.runInNewContext(script, { window, location: new URL('https://gofile.io/d/example'), URL });
  const response = await window.fetch(url, { method });
  await new Promise(resolve => setTimeout(resolve, 30));
  return { messages, requests, body: options.raw ? await response.text() : await response.json() };
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

test('password gate exposes state but never the submitted password or gated files', async () => {
  const result = await run({ status: 'ok', data: { canAccess: false, password: true, passwordStatus: 'passwordWrong', passwordHash: 'private', children: { f: { id: 'f', name: 'private' } } } });
  const data = result.messages[0].data;
  assert.equal(data.passwordRequired, true);
  assert.equal(data.passwordWrong, true);
  assert.deepEqual(data.children, []);
  assert.ok(!JSON.stringify(data).includes('private'));
});

test('expired and nonpublic gates retain website precedence', async () => {
  for (const [isPublic, expired] of [[true, true], [false, false]]) {
    const result = await run({ status: 'ok', data: { canAccess: false, public: isPublic, expire: 1700000000 } });
    assert.equal(result.messages[0].data.expired, expired);
  }
});

test('HTTP rate limit survives HTML responses and carries the server cooldown', async () => {
  const result = await run(null, undefined, undefined, { raw: '<html>Too many requests</html>', status: 429, headers: { 'Retry-After': '120' } });
  assert.equal(result.requests, 1);
  assert.equal(result.messages[0].httpStatus, 429);
  assert.equal(result.messages[0].retryAfter, 120);
  assert.equal(result.messages[0].status, 'error');
  assert.ok(!JSON.stringify(result.messages).includes('Too many'));
});

test('known API gate codes are allowed without exposing arbitrary server messages', async () => {
  for (const status of ['error-notFound', 'error-notPremium', 'error-rateLimit']) {
    const result = await run({ status, message: 'private', data: { token: 'private' } });
    assert.equal(result.messages[0].status, status);
    assert.ok(!JSON.stringify(result.messages).includes('private'));
  }
});

test('native password submission uses the normal form exactly once and clears plaintext', async () => {
  const swift = readFileSync(new URL('../native/App/GofileSession.swift', import.meta.url), 'utf8');
  const source = swift.match(/let script = """([\s\S]*?)"""/)[1];
  const input = { value: '' };
  const submissions = [];
  const form = { querySelector: () => input, requestSubmit: () => submissions.push(input.value) };
  const result = await vm.runInNewContext(`(async () => { ${source} })()`, {
    document: { querySelector: selector => { assert.equal(selector, 'form[data-fm="password"]'); return form; } },
    password: 'test-only-password', setTimeout
  });
  assert.equal(result, true);
  assert.deepEqual(submissions, ['test-only-password']);
  assert.equal(input.value, '');
});
