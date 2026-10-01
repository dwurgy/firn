import {
  app,
  BrowserWindow,
  ipcMain,
  nativeTheme,
  screen,
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
const SIDEBAR_MIN = 200;
const SIDEBAR_MAX = 360;
const GLIDE_MS = 200; // matches --motion in styles.css
// Once the mouse leaves the peeking sidebar, wait this long before it tucks
// away, so an overshoot doesn't make it vanish.
const PEEK_LINGER_MS = 450;
// How far to the right of the peeking sidebar the mouse can stray and still
// count as "on it". Anywhere to its left (even off the window) also counts.
const PEEK_RIGHT_SLACK = 24;
// How often the cursor's position is checked for the edge reveals.
const EDGE_CHECK_MS = 50;
const PAGE_INSET = 8;
// Matches macOS's window corners.
const PAGE_RADIUS = 12;

// Hovering the top edge slides a bar with the window buttons down over the
// top of the page (Windows / Linux). The layer is a little taller than the
// bar so the bar's soft shadow has room.
const TOP_BAR_LAYER_HEIGHT = 60;
const TOP_BAR_HEIGHT = 40; // matches --top-bar-height in styles.css
// Once the mouse leaves the bar, wait this long before sliding it away, so
// brushing past the edge doesn't make it flicker.
const TOP_BAR_LINGER_MS = 250;

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
// floating layer (command bar, tab switcher), the top bar, or the sidebar
// peeking over the page while collapsed.
type LayerView = 'floating' | 'topbar' | 'peek';

function loadUi(web: WebContents, view?: LayerView) {
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

  // Every show and hide goes through showLayer / hideLayer. A hidden layer
  // is also shrunk to nothing, so even if the system ever ignored "hidden",
  // an invisible layer could never sit over the window catching clicks.
  const NO_BOUNDS = { x: 0, y: 0, width: 0, height: 0 };
  const shownLayers = new Set<WebContentsView>();

  const makeLayer = (view: LayerView) => {
    const layer = new WebContentsView({ webPreferences: UI_WEB_PREFERENCES });
    layer.setBackgroundColor('#00000000');
    layer.setBounds(NO_BOUNDS);
    layer.setVisible(false);
    win.contentView.addChildView(layer);
    loadUi(layer.webContents, view);
    // Loading can make a view visible again; put it back if it should be
    // hidden.
    layer.webContents.on('did-finish-load', () => {
      if (!shownLayers.has(layer)) {
        layer.setVisible(false);
        layer.setBounds(NO_BOUNDS);
      }
    });
    return layer;
  };
  const peek = makeLayer('peek');
  const floating = makeLayer('floating');
  const topBar = OWN_WINDOW_BUTTONS ? makeLayer('topbar') : null;
  const uiContents = [win.webContents, floating.webContents, peek.webContents];
  if (topBar) uiContents.push(topBar.webContents);

  // If one of Firn's own panels crashes or freezes, say so in the terminal
  // and reload it, so the window never stays stuck. Its errors are printed
  // in the terminal too, to help track problems down.
  const uiNames = new Map<WebContents, string>([
    [win.webContents, 'sidebar'],
    [floating.webContents, 'command bar'],
    [peek.webContents, 'peek'],
  ]);
  if (topBar) uiNames.set(topBar.webContents, 'top bar');
  for (const [web, name] of uiNames) {
    web.on('render-process-gone', (_event, details) => {
      console.error(
        `[Firn] The ${name} panel stopped (${details.reason}); reloading it.`,
      );
      if (!win.isDestroyed()) setTimeout(() => web.reload(), 300);
    });
    web.on('unresponsive', () => {
      console.error(
        `[Firn] The ${name} panel is not responding; reloading it.`,
      );
      web.forcefullyCrashRenderer();
    });
    web.on('console-message', (details) => {
      if (details.level === 'error')
        console.error(`[Firn] ${name} error: ${details.message}`);
    });
  }

  // Where the page starts: the sidebar's width, or just the inset when the
  // sidebar is collapsed. It glides between the two.
  let pageLeft = SIDEBAR_WIDTH;

  // Sends a message to every part of Firn's UI.
  const send = (channel: string, ...args: unknown[]) => {
    for (const web of uiContents)
      if (!web.isDestroyed()) web.send(channel, ...args);
  };

  const boundsFor = (layer: WebContentsView) => {
    const [width, height] = win.getContentSize();
    if (layer === topBar) {
      return {
        x: pageLeft,
        y: 0,
        width: Math.max(0, width - pageLeft),
        height: TOP_BAR_LAYER_HEIGHT,
      };
    }
    if (layer === peek) {
      // A little wider than the sidebar, so its soft shadow has room.
      const peekWidth = Math.min(width, windowState.sidebarWidth + 32);
      return { x: 0, y: 0, width: peekWidth, height };
    }
    return { x: 0, y: 0, width, height };
  };

  const layoutLayers = () => {
    for (const layer of shownLayers) layer.setBounds(boundsFor(layer));
  };

  // Stacking order, bottom to top.
  const layerOrder = [peek, topBar, floating];

  // New tabs are added on top, so lift any shown layer back above them.
  const raiseLayers = () => {
    for (const layer of layerOrder)
      if (layer && shownLayers.has(layer)) win.contentView.addChildView(layer);
  };

  const showLayer = (layer: WebContentsView) => {
    shownLayers.add(layer);
    layer.setBounds(boundsFor(layer));
    layer.setVisible(true);
    raiseLayers();
  };

  const hideLayer = (layer: WebContentsView) => {
    shownLayers.delete(layer);
    layer.setVisible(false);
    layer.setBounds(NO_BOUNDS);
  };

  let overlay: OverlayState = { mode: 'hidden' };
  let commandOpenId = 0;

  const showOverlay = (state: OverlayState) => {
    overlay = state;
    send('overlay:state', state);
    showLayer(floating);
    if (state.mode !== 'hidden') floating.webContents.focus();
  };
  const hideOverlay = () => {
    if (overlay.mode === 'hidden') return;
    overlay = { mode: 'hidden' };
    send('overlay:state', overlay);
    hideLayer(floating);
    tabs.focusActive();
  };

  // --- The top bar with the window buttons -------------------------------
  // Reaching the frame edge above the page shows a bar that slides down over
  // the top of the page; the page itself stays where it is.

  // Both the bar and the sidebar layer's outline of the page slide together,
  // so every edge and shadow moves as one.
  //
  // The bar's empty space moves the window like a title bar. Windows takes
  // over the mouse there, so the bar itself can't tell when the mouse
  // leaves; instead we check where the cursor is a few times a second.
  let topBarShown = false;
  let topBarHideTimer: ReturnType<typeof setTimeout> | undefined;
  let topBarWatch: ReturnType<typeof setInterval> | undefined;
  let mouseLastOverBar = 0;

  // The cursor's position relative to the window's content area.
  const cursorInWindow = () => {
    const cursor = screen.getCursorScreenPoint();
    const content = win.getContentBounds();
    return {
      x: cursor.x - content.x,
      y: cursor.y - content.y,
      width: content.width,
      height: content.height,
    };
  };

  const mouseIsOverBar = () => {
    const { x, y, width } = cursorInWindow();
    return (
      x >= pageLeft &&
      x <= width &&
      y <= TOP_BAR_HEIGHT &&
      // A little slack above, for a maximized window's very top edge.
      y >= -4
    );
  };

  const revealTopBar = (reveal: boolean) => {
    if (!topBar) return;
    if (reveal && !win.isFullScreen()) {
      if (topBarShown) return;
      topBarShown = true;
      clearTimeout(topBarHideTimer);
      showLayer(topBar);
      send('top-bar:state', true);
      mouseLastOverBar = Date.now();
      topBarWatch = setInterval(() => {
        if (win.isDestroyed()) return;
        if (mouseIsOverBar()) mouseLastOverBar = Date.now();
        else if (Date.now() - mouseLastOverBar > TOP_BAR_LINGER_MS)
          revealTopBar(false);
      }, 50);
    } else if (topBarShown) {
      topBarShown = false;
      clearInterval(topBarWatch);
      send('top-bar:state', false);
      // Let the slide back up finish before the bar's layer goes away.
      topBarHideTimer = setTimeout(() => hideLayer(topBar), 260);
    }
  };

  // --- Tabs ---------------------------------------------------------------

  const tabs = new TabManager(win, {
    spaceId: DEFAULT_SPACE_ID,
    pageRadius: PAGE_RADIUS,
    // The page floats to the right of the sidebar, inset from the edges.
    pageBounds: () => {
      const [width, height] = win.getContentSize();
      return {
        x: pageLeft,
        y: PAGE_INSET,
        width: Math.max(0, width - pageLeft - PAGE_INSET),
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

  const relayout = () => {
    tabs.layout();
    layoutLayers();
  };
  win.on('resize', relayout);

  // --- Sidebar: resize, collapse, peek -------------------------------------

  let peeking = false;
  let peekWatch: ReturnType<typeof setInterval> | undefined;
  let peekHideTimer: ReturnType<typeof setTimeout> | undefined;
  let glide: ReturnType<typeof setInterval> | undefined;

  const sendSidebar = () =>
    send('sidebar:state', {
      width: windowState.sidebarWidth,
      collapsed: windowState.sidebarCollapsed,
      pageLeft,
      peeking,
    });

  // Slides the page's left edge (and the sidebar with it) to a new spot.
  // Each step is sent to the UI too, so the sidebar moves in step with the
  // page.
  const glidePageLeft = (to: number) => {
    const from = pageLeft;
    const start = Date.now();
    clearInterval(glide);
    glide = setInterval(() => {
      if (win.isDestroyed()) return clearInterval(glide);
      const t = Math.min(1, (Date.now() - start) / GLIDE_MS);
      const eased = 1 - Math.pow(1 - t, 3); // ease-out
      pageLeft = Math.round(from + (to - from) * eased);
      relayout();
      sendSidebar();
      if (t === 1) clearInterval(glide);
    }, 16);
  };

  const setSidebarCollapsed = (collapsed: boolean) => {
    if (windowState.sidebarCollapsed === collapsed) return;
    windowState.sidebarCollapsed = collapsed;
    hidePeek();
    glidePageLeft(collapsed ? PAGE_INSET : windowState.sidebarWidth);
  };

  const setSidebarWidth = (requested: number) => {
    const width = Math.round(
      Math.max(SIDEBAR_MIN, Math.min(SIDEBAR_MAX, requested)),
    );
    if (width === windowState.sidebarWidth) return;
    windowState.sidebarWidth = width;
    if (!windowState.sidebarCollapsed) {
      clearInterval(glide);
      pageLeft = width;
    }
    relayout();
    sendSidebar();
  };

  // While collapsed, reaching the left edge slides the sidebar in over the
  // page. It tucks away once the mouse has left it (checked by cursor
  // position, like the top bar, since its top row moves the window).
  const mouseIsOverPeek = () => {
    const { x, y, height } = cursorInWindow();
    return (
      x <= windowState.sidebarWidth + PEEK_RIGHT_SLACK &&
      y >= -40 &&
      y <= height + 40
    );
  };

  const showPeek = () => {
    if (!windowState.sidebarCollapsed || peeking || win.isFullScreen()) return;
    peeking = true;
    clearTimeout(peekHideTimer);
    showLayer(peek);
    sendSidebar();
    let lastOver = Date.now();
    peekWatch = setInterval(() => {
      if (win.isDestroyed()) return;
      // Stay while the mouse is over it, or while typing in it.
      if (mouseIsOverPeek() || peek.webContents.isFocused())
        lastOver = Date.now();
      else if (Date.now() - lastOver > PEEK_LINGER_MS) hidePeek();
    }, 50);
  };

  const hidePeek = () => {
    if (!peeking) return;
    peeking = false;
    clearInterval(peekWatch);
    sendSidebar();
    // Let it slide away before the layer goes.
    peekHideTimer = setTimeout(() => {
      if (!peeking) hideLayer(peek);
    }, GLIDE_MS + 60);
  };

  // Reaching the window's edges reveals things: the left edge brings the
  // collapsed sidebar out to peek, the top edge above the page brings down
  // the window buttons. This checks the cursor's position directly rather
  // than waiting for hover events, which never fire again while the pointer
  // stays pressed against the screen's edge (e.g. a maximized window).
  const edgeWatch = setInterval(() => {
    if (win.isDestroyed() || !win.isVisible() || win.isMinimized()) return;
    if (win.isFullScreen()) return;
    const { x, y, width, height } = cursorInWindow();
    const alongLeftEdge = x >= -2 && x < PAGE_INSET && y >= 0 && y <= height;
    const alongTopEdge =
      y >= -2 && y < PAGE_INSET && x >= pageLeft && x <= width + 2;
    if (alongLeftEdge && windowState.sidebarCollapsed) showPeek();
    if (alongTopEdge) revealTopBar(true);
  }, EDGE_CHECK_MS);

  // New tab: a floating bar to search or type an address. Nothing is added
  // to the tab list until something is picked.
  const openCommandBar = () =>
    showOverlay({ mode: 'command', openId: ++commandOpenId });

  const focusAddress = () => {
    hideOverlay();
    // With the sidebar collapsed, its address bar is in the peek layer.
    if (windowState.sidebarCollapsed) showPeek();
    const target = windowState.sidebarCollapsed
      ? peek.webContents
      : win.webContents;
    target.focus();
    // Include the active tab's address, so the bar never shows a stale one.
    target.send('ui:focus-address', tabs.navState().url);
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
    'tabs:move': (_sender, id, toIndex) => {
      if (typeof id === 'string' && Number.isInteger(toIndex))
        tabs.move(id, toIndex as number);
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
    'sidebar:toggle': () => setSidebarCollapsed(!windowState.sidebarCollapsed),
    'sidebar:width': (_sender, width) => {
      if (typeof width === 'number' && Number.isFinite(width))
        setSidebarWidth(width);
    },
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
      sender.send('sidebar:state', {
        width: windowState.sidebarWidth,
        collapsed: windowState.sidebarCollapsed,
        pageLeft,
        peeking,
      });
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
  win.on('enter-full-screen', () => revealTopBar(false));

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
    } else if (mod && input.shift && key === 'd') {
      printDiagnostics();
    } else if (mod && key === 's') {
      setSidebarCollapsed(!windowState.sidebarCollapsed);
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
  // Ctrl+Shift+D: print what every layer is doing to the terminal, to help
  // track down a stuck or unresponsive window.
  const printDiagnostics = () => {
    const name = (web: WebContents) =>
      uiNames.get(web) ?? `page ${web.getURL().slice(0, 60)}`;
    const focused = win.webContents.isFocused()
      ? 'sidebar'
      : ([
          ...uiNames.keys(),
          ...win.contentView.children.map(
            (v) => (v as WebContentsView).webContents,
          ),
        ]
          .filter((w) => w && !w.isDestroyed() && w.isFocused())
          .map(name)[0] ?? 'nothing');
    console.log('\n[Firn] --- diagnostics ---');
    console.log(
      `[Firn] overlay=${overlay.mode} switcher=${Boolean(switcher)} topBar=${topBarShown} ` +
        `collapsed=${windowState.sidebarCollapsed} peeking=${peeking} pageLeft=${pageLeft} focused=${focused}`,
    );
    for (const child of win.contentView.children) {
      const view = child as WebContentsView;
      const b = view.getBounds();
      console.log(
        `[Firn]   ${view.getVisible() ? 'shown ' : 'hidden'} ${b.x},${b.y} ${b.width}x${b.height}  ${name(view.webContents)}`,
      );
    }
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
    clearTimeout(topBarHideTimer);
    clearInterval(topBarWatch);
    clearInterval(peekWatch);
    clearInterval(edgeWatch);
    clearTimeout(peekHideTimer);
    clearInterval(glide);
    for (const layer of [floating, topBar, peek])
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
