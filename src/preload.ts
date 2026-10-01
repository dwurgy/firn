// The only bridge between Firn's UI and the main process. Keep it narrow:
// the UI can ask for navigation and tab changes, and listen for state.
import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron';
import type { FirnBridge } from './types';

// Subscribes to a channel and returns a function that unsubscribes.
function listen<T>(channel: string, listener: (value: T) => void) {
  const handler = (_event: IpcRendererEvent, value: T) => listener(value);
  ipcRenderer.on(channel, handler);
  return () => {
    ipcRenderer.removeListener(channel, handler);
  };
}

const bridge: FirnBridge = {
  platform: process.platform,
  navigate: (input) => ipcRenderer.send('nav:navigate', input),
  command: (command) => ipcRenderer.send('nav:command', command),
  newTab: () => ipcRenderer.send('tabs:new'),
  openUrl: (input) => ipcRenderer.send('tabs:open-url', input),
  closeOverlay: () => ipcRenderer.send('overlay:close'),
  toggleSidebar: () => ipcRenderer.send('sidebar:toggle'),
  setSidebarWidth: (width) => ipcRenderer.send('sidebar:width', width),
  closeTab: (id) => ipcRenderer.send('tabs:close', id),
  activateTab: (id) => ipcRenderer.send('tabs:activate', id),
  moveTab: (id, toIndex) => ipcRenderer.send('tabs:move', id, toIndex),
  windowCommand: (command) => ipcRenderer.send('window:command', command),
  dragWindow: (phase) => ipcRenderer.send('window:drag', phase),
  ready: () => ipcRenderer.send('ui:ready'),
  onNavState: (listener) => listen('nav:state', listener),
  onTabsState: (listener) => listen('tabs:state', listener),
  onFocusAddress: (listener) => listen('ui:focus-address', listener),
  onMaximizedChange: (listener) => listen('window:maximized', listener),
  onOverlayState: (listener) => listen('overlay:state', listener),
  onTopBarState: (listener) => listen('top-bar:state', listener),
  onSidebarState: (listener) => listen('sidebar:state', listener),
};

contextBridge.exposeInMainWorld('firn', bridge);
