const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');

test('actual main handlers enforce sender, offline, modules, and stale health result restrictions', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'helios-main-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const main = path.resolve(__dirname, '../main/index.cjs');
  const requireMain = createRequire(main);
  const handlers = new Map();
  const opened = [];
  let window;
  let healthCalls = 0;
  let completeHealth;
  let loaded;
  const ready = new Promise((resolve) => { loaded = resolve; });
  class BrowserWindow {
    constructor(options) {
      assert.equal(options.webPreferences.contextIsolation, true);
      assert.equal(options.webPreferences.sandbox, true);
      assert.equal(options.webPreferences.nodeIntegration, false);
      assert.equal(options.webPreferences.webviewTag, false);
      this.webContents = { mainFrame: { url: '' }, setWindowOpenHandler() {}, on() {} };
      window = this;
    }
    on() {}
    once() {}
    loadURL(url) { this.webContents.mainFrame.url = url; loaded(); return Promise.resolve(); }
  }
  const electron = {
    app: {
      requestSingleInstanceLock: () => true,
      whenReady: () => Promise.resolve(),
      getPath: () => directory,
      getName: () => 'HELIOS Workbench',
      getVersion: () => '0.1.0',
      on() {},
      quit() { throw new Error('Unexpected app quit'); },
    },
    BrowserWindow,
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler) },
    session: { defaultSession: { setPermissionRequestHandler() {}, setPermissionCheckHandler() {} } },
    shell: { openExternal: async (url) => { opened.push(url); } },
    Menu: { buildFromTemplate: (value) => value, setApplicationMenu() {} },
  };
  vm.runInNewContext(await fs.readFile(main, 'utf8'), {
    require: (name) => name === 'electron' ? electron : name === 'electron-squirrel-startup' ? false : name === './health.cjs'
      ? { checkHealth: () => { healthCalls += 1; return new Promise((resolve) => { completeHealth = resolve; }); } }
      : requireMain(name),
    __dirname: path.dirname(main), process: { platform: 'linux', env: {} }, console,
  }, { filename: main });
  await ready;
  const event = { sender: window.webContents, senderFrame: window.webContents.mainFrame };
  const invoke = (channel, value) => handlers.get(`helios:${channel}`)(event, value);
  await assert.rejects(handlers.get('helios:resource')({ sender: {}, senderFrame: {} }, { id: 'github' }), /Untrusted/);
  window.webContents.mainFrame.url += '#workbench';
  assert.equal((await invoke('snapshot')).preferences.profile, 'developer');
  await invoke('preferences', { profile: 'sysadmin' });
  await assert.rejects(invoke('resource', { id: 'github' }), /offline/);
  assert.equal((await invoke('health')).state, 'disabled');
  assert.equal(healthCalls, 0);
  assert.equal(opened.length, 0);
  await invoke('preferences', { profile: 'developer' });
  await invoke('plugin', { id: 'connections', enabled: false });
  assert.equal((await invoke('health')).state, 'disabled');
  assert.equal(healthCalls, 0);
  await invoke('plugin', { id: 'connections', enabled: true });
  const pending = invoke('health');
  assert.equal(healthCalls, 1);
  await invoke('preferences', { profile: 'sysadmin' });
  completeHealth({ state: 'ready', detail: 'Fixture health response', checkedAt: '2026-01-01T00:00:00Z' });
  assert.equal((await pending).state, 'disabled');
  assert.equal((await invoke('snapshot')).integration.state, 'disabled');
  await invoke('preferences', { profile: 'developer' });
  await invoke('resource', { id: 'github' });
  assert.deepEqual(opened, ['https://github.com/Yolkster64/helios-platform']);
});
