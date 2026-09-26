const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { preferencesPatch, pluginRequest, resourceRequest, trustedSender, canCheckHealth } = require('../shared/validation.cjs');
const { StateStore } = require('../main/state.cjs');
const { healthUrl, checkHealth } = require('../main/health.cjs');

test('IPC validators reject arbitrary commands, external URLs, and unknown preference values', () => {
  for (const value of [null, [], { command: 'sh' }, { profile: 'admin' }, { compact: 'true' }]) {
    assert.throws(() => preferencesPatch(value));
  }
  assert.deepEqual(preferencesPatch({ profile: 'sysadmin', reducedMotion: true }), { profile: 'sysadmin', reducedMotion: true });
  assert.throws(() => pluginRequest({ id: 'arbitrary.js', enabled: true }));
  assert.throws(() => pluginRequest({ id: 'connections', enabled: 'yes' }));
  assert.throws(() => resourceRequest({ id: 'https://attacker.example/' }));
  assert.throws(() => resourceRequest({ id: '__proto__' }));
  assert.throws(() => resourceRequest({ id: 'github', url: 'https://attacker.example/' }));
  assert.equal(resourceRequest({ id: 'github' }), 'https://github.com/Yolkster64/helios-platform');
});

test('IPC accepts only the exact top-level local window', () => {
  const frame = { url: 'file:///app/renderer/index.html' };
  const sender = { mainFrame: frame };
  assert.equal(trustedSender({ sender, senderFrame: frame }, sender, frame.url), true);
  assert.equal(trustedSender({ sender, senderFrame: { url: frame.url } }, sender, frame.url), false);
  assert.equal(trustedSender({ sender: {}, senderFrame: frame }, sender, frame.url), false);
  assert.equal(trustedSender({ sender, senderFrame: frame }, sender, 'https://remote.example/'), false);
  assert.equal(trustedSender({}, null, frame.url), false);
  frame.url = 'file:///app/renderer/index.html#main-content';
  assert.equal(trustedSender({ sender, senderFrame: frame }, sender, 'file:///app/renderer/index.html'), true);
  frame.url = 'file:///app/renderer/other.html#main-content';
  assert.equal(trustedSender({ sender, senderFrame: frame }, sender, 'file:///app/renderer/index.html'), false);
});

test('offline profile and disabled Connections module block health capability', () => {
  assert.equal(canCheckHealth({ profile: 'sysadmin' }, [{ id: 'connections', enabled: true }]), false);
  assert.equal(canCheckHealth({ profile: 'developer' }, [{ id: 'connections', enabled: false }]), false);
  assert.equal(canCheckHealth({ profile: 'developer' }, []), false);
  assert.equal(canCheckHealth({ profile: 'developer' }, [{ id: 'connections', enabled: true }]), true);
});

test('preferences and module choices persist across restart; concurrent changes are serialized', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'helios-test-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const store = new StateStore(directory);
  await store.load();
  await Promise.all([
    store.updatePreferences({ profile: 'studio' }),
    store.updatePreferences({ reducedMotion: true }),
    store.updatePlugin({ id: 'usb-planner', enabled: false }),
  ]);
  const restored = new StateStore(directory);
  await restored.load();
  assert.deepEqual(restored.preferences, { profile: 'studio', compact: false, reducedMotion: true });
  assert.equal(restored.plugins.find((plugin) => plugin.id === 'usb-planner').enabled, false);
  await assert.rejects(restored.updatePreferences({ profile: 'malicious' }));
  assert.equal(restored.preferences.profile, 'studio');
});

test('corrupt stored settings cannot inject module definitions or partial preferences', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'helios-corrupt-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const store = new StateStore(directory);
  await fs.writeFile(store.file, JSON.stringify({ version: 1, preferences: { profile: 'studio' }, plugins: [{ id: 'evil', enabled: true }] }));
  await store.load();
  assert.equal(store.preferences.profile, 'developer');
  assert.equal(store.plugins.some((plugin) => plugin.id === 'evil'), false);
});

test('health requests are explicit, loopback-only, non-redirecting and credential-free', async () => {
  for (const base of ['https://example.com', 'http://169.254.169.254', 'http://127.0.0.1@evil.test', 'http://secret@127.0.0.1:5080', 'http://127.0.0.1/foo', 'http://127.0.0.1/?key=value']) {
    assert.throws(() => healthUrl(base));
  }
  assert.equal(healthUrl('http://127.0.0.1:5080'), 'http://127.0.0.1:5080/healthz');
  assert.equal(healthUrl('http://[::1]:5080'), 'http://[::1]:5080/healthz');
  let calls = 0;
  const fetcher = async (url, options) => {
    calls += 1;
    assert.equal(url, 'http://127.0.0.1:5080/healthz');
    assert.equal(options.redirect, 'error');
    assert.deepEqual(options.headers, { Accept: 'application/json' });
    return Response.json({ status: 'ok' });
  };
  assert.equal((await checkHealth('', fetcher)).state, 'disabled');
  assert.equal((await checkHealth('https://remote.example/', fetcher)).state, 'unavailable');
  assert.equal(calls, 0);
  const result = await checkHealth('http://127.0.0.1:5080', fetcher);
  assert.equal(result.state, 'ready');
  assert.match(result.detail, /not verified/);
  assert.equal(calls, 1);
});

test('health distinguishes failed, malformed, oversized, and unexpected responses', async () => {
  const replies = [
    async () => new Response('error', { status: 500 }),
    async () => new Response('login page', { headers: { 'content-type': 'text/html' } }),
    async () => new Response('{', { headers: { 'content-type': 'application/json' } }),
    async () => Response.json({ status: 'different-service' }),
    async () => Response.json({ status: 'ok', extra: 'x'.repeat(65536) }),
    async () => { throw new Error('private diagnostic must not reach renderer'); },
  ];
  for (const reply of replies) {
    const result = await checkHealth('http://127.0.0.1:5080', reply);
    assert.equal(result.state, 'unavailable');
    assert.doesNotMatch(result.detail, /private diagnostic/);
  }
});
