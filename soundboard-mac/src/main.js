const { app, BrowserWindow, ipcMain, dialog, protocol, net, shell, globalShortcut } = require('electron');
const path = require('path');
const { pathToFileURL } = require('url');
const { Library, AUDIO_EXTENSIONS } = require('./library');

// Sounds are served to the renderer over sound://local/<file>.
protocol.registerSchemesAsPrivileged([
  { scheme: 'sound', privileges: { standard: true, secure: true, stream: true, supportFetchAPI: true } },
]);

// YouTube shows "browser not supported" banners to Electron's default UA.
app.userAgentFallback = app.userAgentFallback.replace(/\s(Electron|clipboard-soundboard|Soundboard)\/\S+/gi, '');

let library;
let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 860,
    minWidth: 900,
    minHeight: 560,
    title: 'Soundboard',
    titleBarStyle: 'hiddenInset',
    backgroundColor: '#14141c',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webviewTag: true,
    },
  });
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  mainWindow.on('closed', () => { mainWindow = null; });
}

// Lock down the embedded YouTube browser: our capture preload only, no Node.
app.on('web-contents-created', (_event, contents) => {
  contents.on('will-attach-webview', (_e, webPreferences, params) => {
    delete webPreferences.preloadURL;
    webPreferences.preload = path.join(__dirname, 'youtube-preload.js');
    webPreferences.nodeIntegration = false;
    webPreferences.contextIsolation = true;
    webPreferences.sandbox = true;
    params.partition = 'persist:youtube';
  });
  if (contents.getType() === 'webview') {
    // Open "new window" links inside the same embedded browser.
    contents.setWindowOpenHandler(({ url }) => {
      if (/^https?:/.test(url)) contents.loadURL(url);
      return { action: 'deny' };
    });
  }
});

function syncHotkeys() {
  globalShortcut.unregisterAll();
  const failed = [];
  for (const sound of library.list()) {
    if (!sound.hotkey) continue;
    try {
      const ok = globalShortcut.register(sound.hotkey, () => {
        if (mainWindow) mainWindow.webContents.send('hotkey:play', sound.id);
      });
      if (!ok) failed.push(sound.hotkey);
    } catch {
      failed.push(sound.hotkey);
    }
  }
  return failed;
}

function registerIpc() {
  ipcMain.handle('sounds:list', () => library.list());

  ipcMain.handle('sounds:import-dialog', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: 'Add sounds',
      properties: ['openFile', 'multiSelections'],
      filters: [{ name: 'Audio', extensions: AUDIO_EXTENSIONS }],
    });
    if (result.canceled) return [];
    const added = [];
    for (const file of result.filePaths) {
      try { added.push(library.addFromFile(file)); } catch (err) { console.error(err); }
    }
    return added;
  });

  ipcMain.handle('sounds:add', (_e, { name, data, ext, source }) => library.add({ name, data, ext, source }));

  ipcMain.handle('sounds:update', (_e, id, changes) => {
    const sound = library.update(id, changes);
    const failed = 'hotkey' in changes ? syncHotkeys() : [];
    return { sound, sounds: library.list(), failedHotkeys: failed };
  });

  ipcMain.handle('sounds:remove', (_e, id) => {
    library.remove(id);
    syncHotkeys();
  });

  ipcMain.handle('sounds:reorder', (_e, ids) => library.reorder(ids));

  ipcMain.handle('sounds:reveal', (_e, id) => {
    const sound = library.get(id);
    if (sound) shell.showItemInFolder(path.join(library.dir, sound.file));
    else shell.openPath(library.dir);
  });

  ipcMain.handle('shell:open-external', (_e, url) => {
    if (/^https:\/\//.test(url)) shell.openExternal(url);
  });
}

app.whenReady().then(() => {
  library = new Library(path.join(app.getPath('userData'), 'sounds'));

  protocol.handle('sound', (request) => {
    const file = decodeURIComponent(new URL(request.url).pathname.slice(1));
    const resolved = library.resolveFile(file);
    if (!resolved) return new Response('Not found', { status: 404 });
    return net.fetch(pathToFileURL(resolved).toString(), { headers: request.headers });
  });

  registerIpc();
  createWindow();
  syncHotkeys();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('will-quit', () => globalShortcut.unregisterAll());

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
