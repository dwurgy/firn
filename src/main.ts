import {
  app,
  BrowserWindow,
  ipcMain,
  nativeTheme,
  type IpcMainEvent,
  type Input,
  type WebContents,
} from 'electron';
import path from 'node:path';
import started from 'electron-squirrel-startup';
import { TabManager } from './tabs';
import type { NavCommand, WindowState } from './types';

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (started) {
  app.quit();
}

const HOME_URL = 'https://duckduckgo.com';

// Layout of the window frame (keep in sync with the CSS in src/ui/styles.css).
const SIDEBAR_WIDTH = 260;
const PAGE_INSET = 8;
const PAGE_RADIUS = 12;

// Warm neutral frame colors, used before the UI has painted.
const FRAME = { light: '#e9e3da', dark: '#3a3734' };

const frameColor = () =>
  nativeTheme.shouldUseDarkColors ? FRAME.dark : FRAME.light;

// Phase 2 has one space; Phase 4 adds the rest.
const DEFAULT_SPACE_ID = 'space-default';

const NAV_COMMANDS: NavCommand[] = ['back', 'forward', 'reload', 'stop'];

const createWindow = () => {
  // The window itself hosts Firn's own UI (the sidebar).
  const win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 640,
    minHeight: 400,
    title: 'Firn',
    backgroundColor: frameColor(),
    // Hide the OS title bar. macOS keeps its traffic lights; on Windows and
    // Linux Firn draws its own window buttons at the top of the sidebar.
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });

  const windowState: WindowState = {
    id: String(win.id),
    activeSpaceId: DEFAULT_SPACE_ID,
    activeTabId: null,
    sidebarWidth: SIDEBAR_WIDTH,
    sidebarCollapsed: false,
  };

  const send = (channel: string, ...args: unknown[]) => {
    if (!win.isDestroyed()) win.webContents.send(channel, ...args);
  };

  const tabs = new TabManager(win, {
    spaceId: DEFAULT_SPACE_ID,
    pageRadius: PAGE_RADIUS,
    // The page floats to the right of the sidebar, inset from the edges.
    pageBounds: () => {
      const [width, height] = win.getContentSize();
      return {
        x: windowState.sidebarWidth,
        y: PAGE_INSET,
        width: Math.max(0, width - windowState.sidebarWidth - PAGE_INSET),
        height: Math.max(0, height - PAGE_INSET * 2),
      };
    },
    onTabsChanged: (state) => {
      windowState.activeTabId = state.activeTabId;
      send('tabs:state', state);
    },
    onNavChanged: (state) => {
      if (!win.isDestroyed())
        win.setTitle(state.title ? `${state.title} — Firn` : 'Firn');
      send('nav:state', state);
    },
    onPageCreated: (web) => watchShortcuts(web),
  });

  win.on('resize', () => tabs.layout());

  // A new, empty tab with the address bar ready for typing.
  const openNewTab = () => {
    tabs.create();
    focusAddress();
  };
  const focusAddress = () => {
    win.webContents.focus();
    // Include the active tab's address, so the bar never shows a stale one.
    send('ui:focus-address', tabs.navState().url);
  };

  // Firn's own UI must never navigate away from itself.
  win.webContents.on('will-navigate', (event) => event.preventDefault());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));

  // --- Commands from the UI -----------------------------------------------

  const handlers: Record<string, (...args: unknown[]) => void> = {
    'nav:navigate': (input) => {
      if (typeof input === 'string') tabs.navigate(input);
    },
    'nav:command': (command) => {
      if (NAV_COMMANDS.includes(command as NavCommand))
        tabs.command(command as NavCommand);
    },
    'tabs:new': () => openNewTab(),
    'tabs:close': (id) => {
      if (typeof id === 'string') tabs.close(id);
    },
    'tabs:activate': (id) => {
      if (typeof id === 'string') tabs.activate(id);
    },
    'window:command': (command) => {
      if (command === 'minimize') win.minimize();
      else if (command === 'toggle-maximize')
        win.isMaximized() ? win.unmaximize() : win.maximize();
      else if (command === 'close') win.close();
    },
    'ui:ready': () => {
      send('tabs:state', tabs.state());
      send('nav:state', tabs.navState());
      sendMaximized();
    },
  };
  // Only accept messages that come from this window's own UI.
  const listeners = Object.entries(handlers).map(([channel, handler]) => {
    const listener = (event: IpcMainEvent, ...args: unknown[]) => {
      if (event.sender === win.webContents) handler(...args);
    };
    ipcMain.on(channel, listener);
    return [channel, listener] as const;
  });

  // Lets the UI swap the maximize icon for a restore icon.
  const sendMaximized = () => send('window:maximized', win.isMaximized());
  win.on('maximize', sendMaximized);
  win.on('unmaximize', sendMaximized);

  // --- Keyboard shortcuts (work whether a page or the sidebar has focus) ---

  const handleShortcut = (event: Electron.Event, input: Input) => {
    if (input.type !== 'keyDown') return;
    const mod = process.platform === 'darwin' ? input.meta : input.control;
    const key = input.key.toLowerCase();

    let handled = true;
    if (mod && key === 'l') {
      focusAddress();
    } else if (mod && input.shift && key === 't') {
      tabs.reopenClosed();
    } else if (mod && key === 't') {
      openNewTab();
    } else if (mod && key === 'w') {
      if (tabs.activeTabId) tabs.close(tabs.activeTabId);
    } else if (input.control && key === 'tab') {
      tabs.cycle(input.shift ? -1 : 1);
    } else if (mod && /^[1-9]$/.test(key)) {
      // Ctrl+1…8 jump to that tab; Ctrl+9 always means the last one.
      tabs.activateIndex(key === '9' ? -1 : Number(key) - 1);
    } else if ((input.alt && key === 'arrowleft') || (mod && key === '[')) {
      tabs.command('back');
    } else if ((input.alt && key === 'arrowright') || (mod && key === ']')) {
      tabs.command('forward');
    } else if (key === 'f5' || (mod && key === 'r')) {
      if (input.shift) tabs.hardReload();
      else tabs.command('reload');
    } else if (
      key === 'f12' ||
      (mod && input.shift && key === 'i') ||
      (input.meta && input.alt && key === 'i')
    ) {
      tabs.toggleDevTools();
    } else {
      handled = false;
    }
    if (handled) event.preventDefault();
  };
  const watchShortcuts = (web: WebContents) =>
    web.on('before-input-event', handleShortcut);
  watchShortcuts(win.webContents);

  // --- Follow the OS light/dark setting ------------------------------------

  const onThemeChange = () => win.setBackgroundColor(frameColor());
  nativeTheme.on('updated', onThemeChange);

  win.on('closed', () => {
    for (const [channel, listener] of listeners)
      ipcMain.removeListener(channel, listener);
    nativeTheme.removeListener('updated', onThemeChange);
    tabs.destroy();
  });

  // --- Load Firn's UI, then the first tab ---------------------------------

  if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
    win.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
  } else {
    win.loadFile(
      path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`),
    );
  }
  tabs.create(HOME_URL);
};

app.whenReady().then(() => {
  createWindow();

  // On macOS, re-create a window when the dock icon is clicked and none are open.
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

// Quit when all windows are closed, except on macOS.
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
