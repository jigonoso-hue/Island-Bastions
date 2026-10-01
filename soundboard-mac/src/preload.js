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
  ambience: {
    builtins: () => ipcRenderer.invoke('ambience:builtins'),
    readBuiltin: (file) => ipcRenderer.invoke('ambience:read-builtin', file),
    load: () => ipcRenderer.invoke('ambience:load'),
    save: (state) => ipcRenderer.invoke('ambience:save', state),
  },
  downloadAudio: (jobId, url) => ipcRenderer.invoke('youtube:download-audio', { jobId, url }),
  cancelDownload: (jobId) => ipcRenderer.invoke('youtube:cancel-download', jobId),
  onDownloadProgress: (callback) => ipcRenderer.on('youtube:download-progress', (_e, jobId, progress) => callback(jobId, progress)),
});
