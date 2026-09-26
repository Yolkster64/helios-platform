'use strict';

const { app, BrowserWindow } = require('electron');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

function createWindow() {
  const documentPath = path.join(__dirname, 'index.html');
  const documentUrl = pathToFileURL(documentPath).href;
  const allowedResources = new Set(['index.html', 'renderer.js', 'styles.css']
    .map((name) => pathToFileURL(path.join(__dirname, name)).href));

  const window = new BrowserWindow({
    width: 1180,
    height: 800,
    minWidth: 660,
    minHeight: 680,
    title: 'HELIOS · Profile Lab',
    backgroundColor: '#080c12',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      partition: 'helios-profile-lab',
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      allowRunningInsecureContent: false,
      spellcheck: false,
    },
  });

  // This experiment has no service connection, permission grants or IPC handlers.
  window.webContents.session.setPermissionRequestHandler((_contents, _permission, respond) => respond(false));
  window.webContents.session.setPermissionCheckHandler(() => false);
  window.webContents.session.webRequest.onBeforeRequest({ urls: ['<all_urls>'] }, (request, respond) => {
    respond({ cancel: !allowedResources.has(request.url) });
  });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event, url) => {
    if (url !== documentUrl) event.preventDefault();
  });
  window.webContents.on('will-redirect', (event) => event.preventDefault());
  window.webContents.on('will-attach-webview', (event) => event.preventDefault());
  window.loadFile(documentPath);
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
