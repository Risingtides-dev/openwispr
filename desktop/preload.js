const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  getConfig: () => ipcRenderer.invoke('get-config'),
  saveConfig: (cfg) => ipcRenderer.invoke('save-config', cfg),
  pasteText: (text) => ipcRenderer.invoke('paste-text', text),
  copyText: (text) => ipcRenderer.invoke('copy-text', text),
  testHotkey: (acc) => ipcRenderer.invoke('test-hotkey', acc),
  beginHotkeyCapture: () => ipcRenderer.send('begin-hotkey-capture'),
  endHotkeyCapture: () => ipcRenderer.send('end-hotkey-capture'),
  getWidgetPosition: () => ipcRenderer.invoke('get-widget-position'),
  setWidgetPosition: (x, y) => ipcRenderer.send('set-widget-position', x, y),
  openSettings: (tab) => ipcRenderer.send('open-settings', tab),
  openExternal: (url) => ipcRenderer.send('open-external', url),
  showWidgetMenu: () => ipcRenderer.send('show-widget-menu'),
  onHotkeyToggle: (cb) => ipcRenderer.on('hotkey-toggle', cb),
  onFocusTab: (cb) => ipcRenderer.on('focus-tab', (_e, tab) => cb(tab)),
  notes: {
    list: () => ipcRenderer.invoke('notes-list'),
    create: () => ipcRenderer.invoke('notes-create'),
    update: (id, fields) => ipcRenderer.invoke('notes-update', id, fields),
    delete: (id) => ipcRenderer.invoke('notes-delete', id)
  },
  transcripts: {
    list: () => ipcRenderer.invoke('transcripts-list'),
    save: (entry) => ipcRenderer.invoke('transcripts-save', entry),
    delete: (id) => ipcRenderer.invoke('transcripts-delete', id),
    clear: () => ipcRenderer.invoke('transcripts-clear')
  }
});
