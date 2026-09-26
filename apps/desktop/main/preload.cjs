const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('helios', Object.freeze({
  getSnapshot: () => ipcRenderer.invoke('helios:snapshot'),
  checkHealth: () => ipcRenderer.invoke('helios:health'),
  setPreferences: (value) => ipcRenderer.invoke('helios:preferences', value),
  setPluginEnabled: (value) => ipcRenderer.invoke('helios:plugin', value),
  openResource: (value) => ipcRenderer.invoke('helios:resource', value),
}));
