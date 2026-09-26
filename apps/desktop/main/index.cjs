const { app, BrowserWindow, ipcMain, session, shell, Menu } = require('electron');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { StateStore } = require('./state.cjs');
const { checkHealth } = require('./health.cjs');
const { profiles, connectors } = require('../shared/catalog.cjs');
const { resourceRequest, trustedSender, canCheckHealth } = require('../shared/validation.cjs');

// Squirrel manages application shortcuts on install/update/uninstall.
if (require('electron-squirrel-startup')) app.quit();
else if (!app.requestSingleInstanceLock()) app.quit();
else {
  const pageUrl = pathToFileURL(path.join(__dirname, '../renderer/index.html')).href;
  let window;
  let store;
  let inFlightHealth;
  let integration = { state: 'disabled', detail: 'Local service has not been checked.', checkedAt: null };
  const offlineHealth = () => ({ state: 'disabled', detail: 'Health checks are disabled by the offline profile or Connections module setting.', checkedAt: null });

  function handle(channel, handler) {
    ipcMain.handle(channel, async (event, value) => {
      if (!trustedSender(event, window?.webContents, pageUrl)) throw new Error('Untrusted caller');
      return handler(value);
    });
  }

  function createWindow() {
    window = new BrowserWindow({
      width: 1440, height: 960, minWidth: 880, minHeight: 640,
      title: 'HELIOS Workbench', backgroundColor: '#080f16', show: false,
      webPreferences: {
        preload: path.join(__dirname, 'preload.cjs'),
        contextIsolation: true, sandbox: true, nodeIntegration: false,
        webSecurity: true, webviewTag: false,
      },
    });
    window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    window.webContents.on('will-navigate', (event) => event.preventDefault());
    window.webContents.on('will-attach-webview', (event) => event.preventDefault());
    window.once('ready-to-show', () => window.show());
    window.on('closed', () => { window = null; });
    void window.loadURL(pageUrl);
  }

  app.whenReady().then(async () => {
    session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
    session.defaultSession.setPermissionCheckHandler(() => false);
    store = new StateStore(app.getPath('userData'));
    await store.load();
    handle('helios:snapshot', () => ({
      app: { name: app.getName(), version: app.getVersion(), platform: process.platform },
      profiles, connectors, plugins: store.plugins, preferences: store.preferences,
      integration: canCheckHealth(store.preferences, store.plugins) ? integration : offlineHealth(),
    }));
    handle('helios:preferences', (value) => store.updatePreferences(value));
    handle('helios:plugin', (value) => store.updatePlugin(value));
    handle('helios:resource', (value) => {
      const url = resourceRequest(value);
      if (store.preferences.profile === 'sysadmin') throw new Error('External links are disabled in the offline Sysadmin profile.');
      return shell.openExternal(url);
    });
    handle('helios:health', () => {
      if (!canCheckHealth(store.preferences, store.plugins)) return offlineHealth();
      if (!inFlightHealth) {
        inFlightHealth = checkHealth(process.env.HELIOS_AIHUB_URL).then((result) => {
          integration = canCheckHealth(store.preferences, store.plugins) ? result : offlineHealth();
          return integration;
        }).finally(() => { inFlightHealth = null; });
      }
      return inFlightHealth;
    });
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      ...(process.platform === 'darwin' ? [{ role: 'appMenu' }] : []),
      { role: 'fileMenu' }, { role: 'editMenu' }, { role: 'viewMenu' }, { role: 'windowMenu' },
    ]));
    createWindow();
    app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
  }).catch(() => { console.error('HELIOS could not start.'); app.quit(); });
  app.on('second-instance', () => { if (window) { if (window.isMinimized()) window.restore(); window.focus(); } });
  app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
}
