import {
  app,
  BrowserWindow,
  ipcMain,
  nativeTheme,
  WebContentsView,
  type IpcMainEvent,
  type Input,
  type WebContents,
} from 'electron';
import path from 'node:path';
import started from 'electron-squirrel-startup';
import { TabManager } from './tabs';
import type { NavCommand, OverlayState, WindowState } from './types';

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (started) {
  app.quit();
}

const HOME_URL = 'https://duckduckgo.com';

// Layout of the window frame (keep in sync with the CSS in src/ui/styles.css).
const SIDEBAR_WIDTH = 260;
const PAGE_INSET = 8;
const PAGE_RADIUS = 12;

// The hidden window buttons' area in the top-right corner.
const CONTROLS_WIDTH = 168;
const CONTROLS_HEIGHT = 76;

// Ctrl+Tab: a quick tap just flips tabs; holding Ctrl this long shows the list.
const SWITCHER_DELAY_MS = 180;

// Warm neutral frame colors, used before the UI has painted.
const FRAME = { light: '#e9e3da', dark: '#3a3734' };

const frameColor = () =>
  nativeTheme.shouldUseDarkColors ? FRAME.dark : FRAME.light;

// Phase 2 has one space; Phase 4 adds the rest.
const DEFAULT_SPACE_ID = 'space-default';

const NAV_COMMANDS: NavCommand[] = ['back', 'forward', 'reload', 'stop'];

// macOS keeps its own traffic lights; elsewhere Firn draws window buttons.
const OWN_WINDOW_BUTTONS = process.platform !== 'darwin';

// Same safe settings as web pages, plus the narrow preload bridge.
const UI_WEB_PREFERENCES = {
  preload: path.join(__dirname, 'preload.cjs'),
  contextIsolation: true,
  sandbox: true,
  nodeIntegration: false,
};

// Loads Firn's UI. `view` picks which part: the sidebar (default), the
// floating layer (command bar, tab switcher) or the window buttons.
function loadUi(web: WebContents, view?: 'floating' | 'controls') {
  if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
    const url = new URL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
    if (view) url.searchParams.set('view', view);
    web.loadURL(url.toString());
  } else {
    web.loadFile(
      path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`),
      view ? { query: { view } } : undefined,
    );
  }
  // Firn's own UI must never navigate away from itself.
  web.on('will-navigate', (event) => event.preventDefault());
  web.setWindowOpenHandler(() => ({ action: 'deny' }));
}

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
    // Linux Firn draws its own window buttons, hidden in the top-right corner.
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: UI_WEB_PREFERENCES,
  });

  const windowState: WindowState = {
    id: String(win.id),
    activeSpaceId: DEFAULT_SPACE_ID,
    activeTabId: null,
    sidebarWidth: SIDEBAR_WIDTH,
    sidebarCollapsed: false,
  };

  // --- Layers above the web page ------------------------------------------
  // Web pages are drawn on top of the sidebar's layer, so anything that has
  // to float over a page lives in its own transparent layer above it.

  const makeLayer = (view: 'floating' | 'controls') => {
    const layer = new WebContentsView({ webPreferences: UI_WEB_PREFERENCES });
    layer.setBackgroundColor('#00000000');
    layer.setVisible(false);
    win.contentView.addChildView(layer);
    loadUi(layer.webContents, view);
    return layer;
  };
  const floating = makeLayer('floating');
  const controls = OWN_WINDOW_BUTTONS ? makeLayer('controls') : null;
  const uiContents = [win.webContents, floating.webContents];
  if (controls) uiContents.push(controls.webContents);

  // Sends a message to every part of Firn's UI.
  const send = (channel: string, ...args: unknown[]) => {
    for (const web of uiContents)
      if (!web.isDestroyed()) web.send(channel, ...args);
  };

  const layoutLayers = () => {
    const [width, height] = win.getContentSize();
    floating.setBounds({ x: 0, y: 0, width, height });
    controls?.setBounds({
      x: width - CONTROLS_WIDTH,
      y: 0,
      width: CONTROLS_WIDTH,
      height: CONTROLS_HEIGHT,
    });
  };

  // New tabs are added on top, so lift any visible layer back above them.
  const raiseLayers = () => {
    for (const layer of [floating, controls]) {
      if (layer?.getVisible()) win.contentView.addChildView(layer);
    }
  };

  let overlay: OverlayState = { mode: 'hidden' };
  let commandOpenId = 0;

  const showOverlay = (state: OverlayState) => {
    overlay = state;
    send('overlay:state', state);
    layoutLayers();
    win.contentView.addChildView(floating);
    floating.setVisible(true);
    if (state.mode !== 'hidden') floating.webContents.focus();
  };
  const hideOverlay = () => {
    if (overlay.mode === 'hidden') return;
    overlay = { mode: 'hidden' };
    send('overlay:state', overlay);
    floating.setVisible(false);
    tabs.focusActive();
  };

  const showControls = () => {
    if (!controls || win.isFullScreen()) return;
    layoutLayers();
    win.contentView.addChildView(controls);
    controls.setVisible(true);
    send('controls:shown');
  };
  const hideControls = () => controls?.setVisible(false);

  // --- Tabs ---------------------------------------------------------------

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
    onPageCreated: (web) => {
      watchShortcuts(web);
      raiseLayers();
    },
    onEmpty: () => openCommandBar(),
  });

  win.on('resize', () => {
    tabs.layout();
    layoutLayers();
  });

  // New tab: a floating bar to search or type an address. Nothing is added
  // to the tab list until something is picked.
  const openCommandBar = () =>
    showOverlay({ mode: 'command', openId: ++commandOpenId });

  const focusAddress = () => {
    hideOverlay();
    win.webContents.focus();
    // Include the active tab's address, so the bar never shows a stale one.
    send('ui:focus-address', tabs.navState().url);
  };

  // --- Ctrl+Tab: switch by most recent use, like Alt+Tab ------------------

  let switcher: {
    tabIds: string[];
    index: number;
    revealed: boolean;
    timer: ReturnType<typeof setTimeout>;
  } | null = null;

  const stepSwitcher = (step: 1 | -1) => {
    if (!switcher) {
      const tabIds = tabs.recentIds();
      if (tabIds.length < 2) return;
      switcher = {
        tabIds,
        index: 0,
        revealed: false,
        timer: setTimeout(() => {
          if (!switcher) return;
          switcher.revealed = true;
          showSwitcher();
        }, SWITCHER_DELAY_MS),
      };
    }
    const count = switcher.tabIds.length;
    switcher.index = (switcher.index + step + count) % count;
    // The layer takes keyboard focus right away (still invisible), because
    // the page that saw Ctrl+Tab won't report Ctrl being let go.
    showSwitcher();
  };
  const showSwitcher = () => {
    if (!switcher) return;
    const { tabIds, index, revealed } = switcher;
    showOverlay({ mode: 'switcher', tabIds, index, revealed });
  };
  // Letting go of Ctrl switches to the picked tab; Esc cancels.
  const endSwitcher = (commit: boolean) => {
    if (!switcher) return;
    clearTimeout(switcher.timer);
    const id = switcher.tabIds[switcher.index];
    switcher = null;
    hideOverlay();
    if (commit) tabs.activate(id);
  };

  // --- Commands from the UI -----------------------------------------------

  const handlers: Record<
    string,
    (sender: WebContents, ...args: unknown[]) => void
  > = {
    'nav:navigate': (_sender, input) => {
      if (typeof input === 'string') tabs.navigate(input);
    },
    'nav:command': (_sender, command) => {
      if (NAV_COMMANDS.includes(command as NavCommand))
        tabs.command(command as NavCommand);
    },
    'tabs:new': () => openCommandBar(),
    'tabs:open-url': (_sender, input) => {
      if (typeof input !== 'string') return;
      hideOverlay();
      tabs.openTyped(input);
    },
    'tabs:close': (_sender, id) => {
      if (typeof id === 'string') tabs.close(id);
    },
    'tabs:activate': (_sender, id) => {
      if (typeof id !== 'string') return;
      if (switcher) endSwitcher(false);
      hideOverlay();
      tabs.activate(id);
    },
    'overlay:close': () => {
      if (switcher) endSwitcher(false);
      hideOverlay();
    },
    'controls:show': () => showControls(),
    'controls:hide': () => hideControls(),
    'window:command': (_sender, command) => {
      if (command === 'minimize') win.minimize();
      else if (command === 'toggle-maximize')
        win.isMaximized() ? win.unmaximize() : win.maximize();
      else if (command === 'close') win.close();
    },
    'ui:ready': (sender) => {
      sender.send('tabs:state', tabs.state());
      sender.send('nav:state', tabs.navState());
      sender.send('window:maximized', win.isMaximized());
      sender.send('overlay:state', overlay);
    },
  };
  // Only accept messages that come from this window's own UI.
  const listeners = Object.entries(handlers).map(([channel, handler]) => {
    const listener = (event: IpcMainEvent, ...args: unknown[]) => {
      if (uiContents.includes(event.sender)) handler(event.sender, ...args);
    };
    ipcMain.on(channel, listener);
    return [channel, listener] as const;
  });

  // Lets the UI swap the maximize icon for a restore icon.
  const sendMaximized = () => send('window:maximized', win.isMaximized());
  win.on('maximize', sendMaximized);
  win.on('unmaximize', sendMaximized);

  // If the window loses focus mid-switch, Ctrl's release never arrives.
  win.on('blur', () => endSwitcher(true));
  win.on('enter-full-screen', hideControls);

  // --- Keyboard shortcuts (work wherever focus is) -------------------------

  const handleShortcut = (
    event: Electron.Event,
    input: Input,
    source: WebContents,
  ) => {
    // Ctrl was let go (or is no longer held): switch to the picked tab.
    const ctrlReleased =
      input.key === 'Control' ? input.type === 'keyUp' : !input.control;
    if (switcher && ctrlReleased) {
      endSwitcher(true);
      return;
    }
    if (input.type !== 'keyDown') return;
    if (input.type !== 'keyDown') return;
    const mod = process.platform === 'darwin' ? input.meta : input.control;
    const key = input.key.toLowerCase();

    let handled = true;
    if (input.control && key === 'tab') {
      stepSwitcher(input.shift ? -1 : 1);
      // Blocking a key here also hides the matching key release from that
      // same view, so let the switcher layer keep its own key events.
      if (source === floating.webContents) handled = false;
    } else if (switcher && key === 'escape') {
      endSwitcher(false);
    } else if (mod && key === 'l') {
      focusAddress();
    } else if (mod && input.shift && key === 't') {
      tabs.reopenClosed();
    } else if (mod && key === 't') {
      openCommandBar();
    } else if (mod && key === 'w') {
      if (tabs.activeTabId) tabs.close(tabs.activeTabId);
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
    web.on('before-input-event', (event, input) =>
      handleShortcut(event, input, web),
    );
  uiContents.forEach(watchShortcuts);

  // --- Follow the OS light/dark setting ------------------------------------

  const onThemeChange = () => win.setBackgroundColor(frameColor());
  nativeTheme.on('updated', onThemeChange);

  win.on('closed', () => {
    for (const [channel, listener] of listeners)
      ipcMain.removeListener(channel, listener);
    nativeTheme.removeListener('updated', onThemeChange);
    if (switcher) clearTimeout(switcher.timer);
    tabs.destroy();
    for (const layer of [floating, controls])
      if (layer && !layer.webContents.isDestroyed()) layer.webContents.close();
  });

  // --- Load Firn's UI, then the first tab ---------------------------------

  loadUi(win.webContents);
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
