const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('soundboard', {
  list: () => ipcRenderer.invoke('sounds:list'),
  importDialog: () => ipcRenderer.invoke('sounds:import-dialog'),
  add: (sound) => ipcRenderer.invoke('sounds:add', sound),
  update: (id, changes) => ipcRenderer.invoke('sounds:update', id, changes),
  remove: (id) => ipcRenderer.invoke('sounds:remove', id),
  reorder: (ids) => ipcRenderer.invoke('sounds:reorder', ids),
  reveal: (id) => ipcRenderer.invoke('sounds:reveal', id),
  openExternal: (url) => ipcRenderer.invoke('shell:open-external', url),
  onHotkey: (callback) => ipcRenderer.on('hotkey:play', (_e, id) => callback(id)),
});
