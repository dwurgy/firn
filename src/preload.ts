// The only bridge between Firn's UI and the main process. Keep it narrow:
// the UI can ask for navigation and listen for page state, nothing more.
import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron';
import type { FirnBridge, NavState } from './types';

const bridge: FirnBridge = {
  platform: process.platform,
  navigate: (input) => ipcRenderer.send('nav:navigate', input),
  command: (command) => ipcRenderer.send('nav:command', command),
  windowCommand: (command) => ipcRenderer.send('window:command', command),
  ready: () => ipcRenderer.send('ui:ready'),
  onNavState: (listener) => {
    const handler = (_event: IpcRendererEvent, state: NavState) =>
      listener(state);
    ipcRenderer.on('nav:state', handler);
    return () => ipcRenderer.removeListener('nav:state', handler);
  },
  onFocusAddress: (listener) => {
    const handler = () => listener();
    ipcRenderer.on('ui:focus-address', handler);
    return () => ipcRenderer.removeListener('ui:focus-address', handler);
  },
  onMaximizedChange: (listener) => {
    const handler = (_event: IpcRendererEvent, maximized: boolean) =>
      listener(maximized);
    ipcRenderer.on('window:maximized', handler);
    return () => ipcRenderer.removeListener('window:maximized', handler);
  },
};

contextBridge.exposeInMainWorld('firn', bridge);
