import {
  app,
  BrowserWindow,
  ipcMain,
  dialog,
  Menu,
  nativeTheme,
  screen,
  session,
  WebContentsView,
  type IpcMainEvent,
  type IpcMainInvokeEvent,
  type Input,
  type WebContents,
} from 'electron';
import { randomUUID } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import started from 'electron-squirrel-startup';
import { loadSession, SaveScheduler, saveSession, sessionPath } from './store';
import { BASECAMP_MAX, TabManager } from './tabs';
import type {
  FrameState,
  NavCommand,
  OverlayState,
  SavedWindow,
  Space,
  WindowState,
} from './types';

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (started) {
  app.quit();
}

const HOME_URL = 'https://duckduckgo.com';

// Start with FIRN_DEBUG=1 to log what the window's layers are doing.
const DEBUG = Boolean(process.env.FIRN_DEBUG);
const debug = (message: string) => {
  if (DEBUG) console.log(`[Firn debug] ${message}`);
};

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
// A UI panel that hasn't reported it started within this long is reloaded.
const UI_START_TIMEOUT_MS = 5000;

// How often the cursor's position is checked for the edge reveals.
const EDGE_CHECK_MS = 50;
// How generous the left-edge zone that brings out the peeking sidebar is:
// a little past the window's edge, and a little way into the page. (Just
// the thin frame strip proved far too easy to miss.)
const PEEK_ZONE_OUTSIDE = 8;
const PEEK_ZONE_INSIDE = 20;
const PAGE_INSET = 8;
// Matches macOS's window corners.
const PAGE_RADIUS = 12;

// Hovering the top edge lowers the page to make room for a bar with the
// window buttons above it (Windows / Linux).
const TOP_BAR_HEIGHT = 40; // matches --top-bar-height in styles.css
// Once the mouse leaves the bar, wait this long before sliding it away, so
// brushing past the edge doesn't make it flicker.
const TOP_BAR_LINGER_MS = 250;

// Ctrl+Tab: a quick tap just flips tabs; holding Ctrl this long shows the list.
const SWITCHER_DELAY_MS = 180;

// Warm neutral frame colors, used before the UI has painted.
// Frosted glass behind the window: acrylic on Windows 11 (version 22H2,
// build 22621, and later) and vibrancy on macOS. Elsewhere the frame stays
// solid. FIRN_NO_GLASS=1 turns it off.
const GLASS = (() => {
  if (process.env.FIRN_NO_GLASS) return false;
  if (process.platform === 'darwin') return true;
  if (process.platform === 'win32')
    return Number(os.release().split('.')[2]) >= 22621;
  return false;
})();

const FRAME = { light: '#e9e3da', dark: '#3a3734' };

const frameColor = () =>
  nativeTheme.shouldUseDarkColors ? FRAME.dark : FRAME.light;

// The space a first run starts with.
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
}

// Firn's own UI must never navigate away from itself.
function lockUi(web: WebContents) {
  web.on('will-navigate', (event) => event.preventDefault());
  web.setWindowOpenHandler(() => ({ action: 'deny' }));
}

// Downloads a favicon and returns it as a data: URL (or null). Small images
// only; anything else is ignored.
const ICON_MAX_BYTES = 512 * 1024;
async function iconAsDataUrl(url: string): Promise<string | null> {
  if (url.startsWith('data:image/')) return url;
  if (!/^https?:\/\//i.test(url)) return null;
  try {
    const response = await session.defaultSession.fetch(url);
    if (!response.ok) return null;
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > ICON_MAX_BYTES) return null;
    const type = (response.headers.get('content-type') ?? '').split(';')[0];
    // Some sites send .ico files without an image type; Chromium sniffs it.
    const mime = type.startsWith('image/') ? type : 'image/x-icon';
    return `data:${mime};base64,${bytes.toString('base64')}`;
  } catch {
    return null;
  }
}

// --- Spaces ---------------------------------------------------------------

// Icons to choose from for a space (a new space takes the next unused one).
const SPACE_ICONS = [
  '🏠',
  '💼',
  '🌿',
  '📚',
  '🎨',
  '🎵',
  '🎮',
  '✈️',
  '☕',
  '🛒',
  '💡',
  '🧪',
  '🏔️',
  '🌊',
  '⭐',
  '❤️',
];
// Each space's theme color (used for its tint in the next step).
const SPACE_COLORS = [
  '#c9a27e',
  '#7f9cb0',
  '#8fae8b',
  '#b88a9e',
  '#c4a95b',
  '#8e8fb8',
  '#b07f6a',
  '#6fa3a0',
];

const defaultSpaces = (): Space[] => [
  {
    id: DEFAULT_SPACE_ID,
    name: 'Personal',
    icon: SPACE_ICONS[0],
    color: SPACE_COLORS[0],
    order: 0,
  },
];

// The saved spaces, if they look right; otherwise the default one. Older
// sessions saved a space with no icon or color; those get one.
function usableSpaces(saved: Space[] | undefined): Space[] {
  const valid = (saved ?? []).filter(
    (s) => s && typeof s.id === 'string' && typeof s.name === 'string',
  );
  if (!valid.length) return defaultSpaces();
  return valid
    .sort((a, b) => a.order - b.order)
    .map((s, i) => ({
      ...s,
      icon: s.icon || SPACE_ICONS[i % SPACE_ICONS.length],
      color: s.color || SPACE_COLORS[i % SPACE_COLORS.length],
      order: i,
    }));
}

// The saved window position, if it's still (mostly) on a connected screen;
// otherwise Firn opens at its default size, centered.
function usableBounds(saved: SavedWindow['bounds']) {
  if (!saved) return undefined;
  const visible = screen.getAllDisplays().some(({ workArea: a }) => {
    const overlapX =
      Math.min(saved.x + saved.width, a.x + a.width) - Math.max(saved.x, a.x);
    const overlapY =
      Math.min(saved.y + saved.height, a.y + a.height) - Math.max(saved.y, a.y);
    return overlapX >= 200 && overlapY >= 100;
  });
  return visible ? saved : undefined;
}

const createWindow = () => {
  // Bring back the last session, if there is one.
  const saved = loadSession();
  const bounds = usableBounds(saved?.window.bounds);

  // The window itself hosts Firn's own UI (the sidebar).
  const win = new BrowserWindow({
    width: bounds?.width ?? 1280,
    height: bounds?.height ?? 820,
    x: bounds?.x,
    y: bounds?.y,
    minWidth: 640,
    minHeight: 400,
    title: 'Firn',
    // With glass, the window is see-through and the UI paints a tinted,
    // partly transparent frame over the system's blur.
    backgroundColor: GLASS ? '#00000000' : frameColor(),
    ...(GLASS && process.platform === 'win32'
      ? { backgroundMaterial: 'acrylic' as const }
      : {}),
    ...(GLASS && process.platform === 'darwin'
      ? {
          vibrancy: 'under-window' as const,
          visualEffectState: 'followWindow' as const,
        }
      : {}),
    // Hide the OS title bar. macOS keeps its traffic lights; on Windows and
    // Linux Firn draws its own window buttons, hidden in the top-right corner.
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: UI_WEB_PREFERENCES,
  });

  let spaces = usableSpaces(saved?.spaces);
  const windowState: WindowState = {
    id: String(win.id),
    activeSpaceId: spaces.some((s) => s.id === saved?.window.activeSpaceId)
      ? saved!.window.activeSpaceId
      : spaces[0].id,
    activeTabId: null,
    sidebarWidth: Math.round(
      Math.max(
        SIDEBAR_MIN,
        Math.min(SIDEBAR_MAX, saved?.window.sidebarWidth ?? SIDEBAR_WIDTH),
      ),
    ),
    sidebarCollapsed: saved?.window.sidebarCollapsed ?? false,
  };
  if (saved?.window.maximized) win.maximize();

  // --- Layers above the web page ------------------------------------------
  // Web pages are drawn on top of the sidebar's layer, so anything that has
  // to float over a page lives in its own transparent layer above it.

  // --- Starting Firn's UI panels -------------------------------------------
  // Panels are loaded one at a time: the sidebar first, then each layer once
  // the one before it has reported that it started ('ui:ready'). A panel
  // that hasn't started within UI_START_TIMEOUT_MS is reloaded. (Loading
  // them all at once could leave one blank in development mode.)
  const readyUi = new Set<WebContents>();
  const startTimers = new Map<WebContents, ReturnType<typeof setTimeout>>();

  const startUi = (web: WebContents) => {
    if (web.isDestroyed()) return;
    readyUi.delete(web);
    loadUi(web, layerViews.get(web));
    clearTimeout(startTimers.get(web));
    startTimers.set(
      web,
      setTimeout(() => {
        if (web.isDestroyed() || readyUi.has(web)) return;
        console.error(
          `[Firn] The ${uiNames.get(web) ?? 'UI'} panel didn't start; reloading it.`,
        );
        startUi(web);
      }, UI_START_TIMEOUT_MS),
    );
  };

  let layersToStart: WebContents[] = [];
  const onUiReady = (web: WebContents) => {
    readyUi.add(web);
    clearTimeout(startTimers.get(web));
    debug(`${uiNames.get(web)} started`);
    // Start the next layer once the previous one is up.
    if (layersToStart[0] === web) layersToStart.shift();
    if (web === win.webContents || !layersToStart.includes(web)) {
      const next = layersToStart[0];
      if (next && !startTimers.has(next)) startUi(next);
    }
  };

  // Every show and hide goes through showLayer / hideLayer. A hidden layer
  // is also shrunk to nothing, so even if the system ever ignored "hidden",
  // an invisible layer could never sit over the window catching clicks.
  const NO_BOUNDS = { x: 0, y: 0, width: 0, height: 0 };
  const shownLayers = new Set<WebContentsView>();
  const layerViews = new Map<WebContents, LayerView>();

  const makeLayer = (view: LayerView) => {
    const layer = new WebContentsView({ webPreferences: UI_WEB_PREFERENCES });
    layer.setBackgroundColor('#00000000');
    layer.setBounds(NO_BOUNDS);
    layer.setVisible(false);
    win.contentView.addChildView(layer);
    layerViews.set(layer.webContents, view);
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

  // If one of Firn's own panels crashes, say so in the terminal and reload
  // it, so the window never stays stuck. Its errors are printed
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
      if (!win.isDestroyed()) setTimeout(() => startUi(web), 300);
    });
    // While a panel (re)loads it hasn't started: take it off screen.
    web.on('did-start-loading', () => {
      readyUi.delete(web);
      for (const layer of shownLayers)
        if (layer.webContents === web) hideLayer(layer);
    });
    // Only reported: a hidden panel can look "unresponsive" to Windows
    // while it's simply asleep, and reloading it then would break it.
    web.on('unresponsive', () =>
      console.error(`[Firn] The ${name} panel is not responding.`),
    );
    web.on('console-message', (details) => {
      if (details.level === 'error')
        console.error(`[Firn] ${name} error: ${details.message}`);
    });
  }

  // Where the page starts: the sidebar's width, or just the inset when the
  // sidebar is collapsed. It glides between the two.
  let pageLeft = windowState.sidebarCollapsed
    ? PAGE_INSET
    : windowState.sidebarWidth;
  // Where the page's top edge is: lower while the top bar shows. While it
  // glides, the page keeps one size and only moves (resizing every step
  // makes the site re-fit each time, which looks jumpy); it takes its new
  // size once, at whichever end of the glide it is taller.
  let pageTop = PAGE_INSET;
  let topFrom = PAGE_INSET;
  let topTo = PAGE_INSET;

  // Sends a message to every part of Firn's UI.
  const send = (channel: string, ...args: unknown[]) => {
    for (const web of uiContents)
      if (!web.isDestroyed()) web.send(channel, ...args);
  };

  const boundsFor = (layer: WebContentsView) => {
    const [width, height] = win.getContentSize();
    if (layer === topBar) {
      // Only as tall as the gap above the page, so the bar's buttons are
      // revealed and covered exactly as the page's top edge glides.
      return {
        x: pageLeft,
        y: 0,
        width: Math.max(0, width - pageLeft),
        height: Math.min(pageTop, TOP_BAR_HEIGHT),
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

  // Returns false (and shows nothing) if the panel hasn't started yet, so a
  // blank, see-through panel can never sit over the window.
  const showLayer = (layer: WebContentsView) => {
    if (!readyUi.has(layer.webContents)) {
      debug(`not showing ${uiNames.get(layer.webContents)}: not started yet`);
      return false;
    }
    debug(`show ${uiNames.get(layer.webContents)}`);
    shownLayers.add(layer);
    layer.setBounds(boundsFor(layer));
    layer.setVisible(true);
    raiseLayers();
    return true;
  };

  const hideLayer = (layer: WebContentsView) => {
    debug(`hide ${uiNames.get(layer.webContents)}`);
    shownLayers.delete(layer);
    layer.setVisible(false);
    layer.setBounds(NO_BOUNDS);
  };

  let overlay: OverlayState = { mode: 'hidden' };
  let commandOpenId = 0;

  const showOverlay = (state: OverlayState) => {
    if (!readyUi.has(floating.webContents)) return false;
    overlay = state;
    send('overlay:state', state);
    showLayer(floating);
    if (state.mode !== 'hidden') floating.webContents.focus();
    return true;
  };
  const hideOverlay = () => {
    if (overlay.mode === 'hidden') return;
    overlay = { mode: 'hidden' };
    send('overlay:state', overlay);
    hideLayer(floating);
    tabs.focusActive();
  };

  // --- The top bar with the window buttons -------------------------------
  // Reaching the frame edge above the page glides the page down a little and
  // shows the window buttons in the space above it. The bar has no
  // background of its own: the frame (frosted glass, where available) shows
  // through it, just like around the rest of the page.
  //
  // The bar's empty space moves the window like a title bar. Windows takes
  // over the mouse there, so the bar itself can't tell when the mouse
  // leaves; instead we check where the cursor is a few times a second.
  let topBarShown = false;
  let topBarHideTimer: ReturnType<typeof setTimeout> | undefined;
  let topBarWatch: ReturnType<typeof setInterval> | undefined;
  let mouseLastOverBar = 0;
  let topGlide: ReturnType<typeof setInterval> | undefined;

  // Slides the page's top edge, in step with the sidebar layer's outline of
  // the page (.page-area in styles.css).
  const glidePageTop = (to: number) => {
    topFrom = pageTop;
    topTo = to;
    const start = Date.now();
    clearInterval(topGlide);
    topGlide = setInterval(() => {
      if (win.isDestroyed()) return clearInterval(topGlide);
      const t = Math.min(1, (Date.now() - start) / GLIDE_MS);
      const eased = 1 - Math.pow(1 - t, 3); // ease-out
      pageTop = Math.round(topFrom + (topTo - topFrom) * eased);
      if (t === 1) {
        clearInterval(topGlide);
        topFrom = topTo;
      }
      tabs.layout();
      if (topBar && shownLayers.has(topBar))
        topBar.setBounds(boundsFor(topBar));
    }, 8);
  };

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
      if (topBarShown || !readyUi.has(topBar.webContents)) return;
      topBarShown = true;
      clearTimeout(topBarHideTimer);
      showLayer(topBar);
      send('top-bar:state', true);
      glidePageTop(TOP_BAR_HEIGHT);
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
      glidePageTop(PAGE_INSET);
      // Let the slide back up finish before the bar's layer goes away.
      topBarHideTimer = setTimeout(() => hideLayer(topBar), 260);
    }
  };

  // --- Tabs ---------------------------------------------------------------

  const tabs = new TabManager(win, {
    spaceId: windowState.activeSpaceId,
    pageRadius: PAGE_RADIUS,
    // The page floats to the right of the sidebar, inset from the edges.
    pageBounds: () => {
      const [width, height] = win.getContentSize();
      return {
        x: pageLeft,
        y: pageTop,
        width: Math.max(0, width - pageLeft - PAGE_INSET),
        // (While gliding, sized for the higher of the two positions; the
        // part that dips below the window is simply out of sight.)
        height: Math.max(0, height - Math.min(topFrom, topTo) - PAGE_INSET),
      };
    },
    onTabsChanged: (state) => {
      windowState.activeTabId = state.activeTabId;
      saver.schedule();
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
    saver.schedule();
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
    saver.schedule();
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
    if (!readyUi.has(peek.webContents)) return;
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
    const cursor = screen.getCursorScreenPoint();
    const content = win.getContentBounds();
    // Measure from the part of the window that's actually on screen: a
    // maximized window on Windows reaches a few pixels past the screen's
    // edges, where the mouse can't go.
    const display = screen.getDisplayMatching(content).bounds;
    const left = Math.max(content.x, display.x);
    const top = Math.max(content.y, display.y);
    const right = content.x + content.width;
    const bottom = content.y + content.height;
    const alongLeftEdge =
      cursor.x >= left - PEEK_ZONE_OUTSIDE &&
      cursor.x < left + PEEK_ZONE_INSIDE &&
      cursor.y >= top &&
      cursor.y <= bottom;
    const alongTopEdge =
      cursor.y >= top - 2 &&
      cursor.y < top + PAGE_INSET &&
      cursor.x >= content.x + pageLeft &&
      cursor.x <= right + 2;
    if (alongLeftEdge && windowState.sidebarCollapsed && !peeking) {
      debug('left edge reached: peek');
      showPeek();
    }
    if (alongTopEdge && !topBarShown) {
      debug('top edge reached: top bar');
      revealTopBar(true);
    }
  }, EDGE_CHECK_MS);

  // Right-click menu for a tab.
  const showTabMenu = (id: string) => {
    const tab = tabs.state().tabs.find((t) => t.id === id);
    if (!tab) return;
    const count = tabs.basecampCount;
    const addToBasecamp: Electron.MenuItemConstructorOptions = {
      label: `Add to Basecamp  (${count}/${BASECAMP_MAX})`,
      enabled: count < BASECAMP_MAX,
      click: () => tabs.addToBasecamp(id),
    };
    const others = spaces.filter((s) => s.id !== tabs.activeSpaceId);
    const moveToSpace: Electron.MenuItemConstructorOptions[] = others.length
      ? [
          {
            label: 'Move to space',
            submenu: others.map((space) => ({
              label: `${space.icon}  ${space.name}`,
              click: () => tabs.moveToSpace(id, space.id),
            })),
          },
        ]
      : [];
    const items: Electron.MenuItemConstructorOptions[] = tab.basecamp
      ? [
          { label: 'Go back to home', click: () => tabs.goHome(id) },
          {
            label: 'Remove from Basecamp',
            click: () => tabs.removeFromBasecamp(id),
          },
          { type: 'separator' },
          { label: 'Unload tab', click: () => tabs.close(id) },
        ]
      : tab.pinned
        ? [
            { label: 'Go back to home', click: () => tabs.goHome(id) },
            {
              label: 'Unpin tab',
              accelerator: 'CmdOrCtrl+D',
              click: () => tabs.unpin(id),
            },
            addToBasecamp,
            ...moveToSpace,
            { type: 'separator' },
            { label: 'Unload tab', click: () => tabs.close(id) },
          ]
        : [
            {
              label: 'Pin tab',
              accelerator: 'CmdOrCtrl+D',
              click: () => tabs.pin(id),
            },
            addToBasecamp,
            ...moveToSpace,
            { type: 'separator' },
            {
              label: 'Close tab',
              accelerator: 'CmdOrCtrl+W',
              click: () => tabs.close(id),
            },
          ];
    Menu.buildFromTemplate(items).popup({ window: win });
  };

  // --- Spaces ---------------------------------------------------------------

  const sendSpaces = () =>
    send('spaces:state', { spaces, activeSpaceId: windowState.activeSpaceId });

  const switchSpace = (id: string) => {
    if (id === windowState.activeSpaceId) return;
    if (!spaces.some((s) => s.id === id)) return;
    windowState.activeSpaceId = id;
    hideOverlay();
    tabs.setSpace(id);
    sendSpaces();
    saver.schedule();
  };

  // Asks the visible sidebar to show the space's name as a text field.
  const startRenameSpace = (id: string) => {
    const sidebar = peeking ? peek.webContents : win.webContents;
    sidebar.focus();
    sidebar.send('spaces:rename', id);
  };

  const newSpace = () => {
    const used = new Set(spaces.map((s) => s.icon));
    const space: Space = {
      id: randomUUID(),
      name: 'New space',
      icon: SPACE_ICONS.find((icon) => !used.has(icon)) ?? SPACE_ICONS[0],
      color: SPACE_COLORS[spaces.length % SPACE_COLORS.length],
      order: spaces.length,
    };
    spaces = [...spaces, space];
    switchSpace(space.id);
    startRenameSpace(space.id);
  };

  const updateSpace = (
    id: string,
    changes: { name?: string; icon?: string; pinsFolded?: boolean },
  ) => {
    spaces = spaces.map((s) =>
      s.id === id
        ? {
            ...s,
            name: changes.name?.trim().slice(0, 40) || s.name,
            icon: changes.icon ?? s.icon,
            pinsFolded: changes.pinsFolded ?? s.pinsFolded,
          }
        : s,
    );
    sendSpaces();
    saver.schedule();
  };

  const deleteSpace = async (id: string) => {
    const space = spaces.find((s) => s.id === id);
    if (!space || spaces.length < 2) return;
    const count = tabs.countIn(id);
    if (count) {
      const { response } = await dialog.showMessageBox(win, {
        type: 'question',
        buttons: ['Delete space', 'Cancel'],
        defaultId: 1,
        cancelId: 1,
        message: `Delete “${space.name}”?`,
        detail: `Its ${count} tab${count === 1 ? '' : 's'} will be closed.`,
      });
      if (response !== 0) return;
    }
    const index = spaces.indexOf(space);
    if (windowState.activeSpaceId === id)
      switchSpace(spaces[index === 0 ? 1 : index - 1].id);
    tabs.closeSpace(id);
    spaces = spaces
      .filter((s) => s.id !== id)
      .map((s, i) => ({ ...s, order: i }));
    sendSpaces();
    saver.schedule();
  };

  // Right-click menu for a space's icon.
  const showSpaceMenu = (id: string) => {
    const space = spaces.find((s) => s.id === id);
    if (!space) return;
    Menu.buildFromTemplate([
      {
        label: 'Rename space',
        click: () => {
          switchSpace(id);
          startRenameSpace(id);
        },
      },
      {
        label: 'Change icon',
        submenu: SPACE_ICONS.map((icon) => ({
          label: icon,
          type: 'checkbox' as const,
          checked: icon === space.icon,
          click: () => updateSpace(id, { icon }),
        })),
      },
      { type: 'separator' },
      {
        label: 'Delete space…',
        enabled: spaces.length > 1,
        click: () => void deleteSpace(id),
      },
    ]).popup({ window: win });
  };

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
      // Without the floating layer (still starting), just flip to the last
      // tab; the switcher needs that layer to hear Ctrl being let go.
      if (!readyUi.has(floating.webContents)) {
        tabs.activate(tabIds[1]);
        return;
      }
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
    'spaces:switch': (_sender, id) => {
      if (typeof id === 'string') switchSpace(id);
    },
    'spaces:new': () => newSpace(),
    'spaces:update': (_sender, id, changes) => {
      if (typeof id !== 'string' || !changes || typeof changes !== 'object')
        return;
      const { name, icon, pinsFolded } = changes as Record<string, unknown>;
      updateSpace(id, {
        name: typeof name === 'string' ? name : undefined,
        icon:
          typeof icon === 'string' && SPACE_ICONS.includes(icon)
            ? icon
            : undefined,
        pinsFolded: typeof pinsFolded === 'boolean' ? pinsFolded : undefined,
      });
    },
    'tabs:clear': () => tabs.clearEveryday(),
    'spaces:menu': (_sender, id) => {
      if (typeof id === 'string') showSpaceMenu(id);
    },
    'tabs:menu': (_sender, id) => {
      if (typeof id === 'string') showTabMenu(id);
    },
    'tabs:move': (_sender, id, toIndex, pinned) => {
      if (typeof id !== 'string' || !Number.isInteger(toIndex)) return;
      if (typeof pinned === 'boolean')
        tabs.place(id, pinned, toIndex as number);
      else tabs.move(id, toIndex as number);
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
      onUiReady(sender);
      sender.send('tabs:state', tabs.state());
      sender.send('nav:state', tabs.navState());
      sender.send('window:maximized', win.isMaximized());
      sender.send('window:frame', frameState());
      sender.send('spaces:state', {
        spaces,
        activeSpaceId: windowState.activeSpaceId,
      });
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

  // The UI asks for a favicon's bytes so it can pick out the icon's main
  // color (for tinting the active pin). Fetching here, rather than in the
  // UI, sidesteps the browser rule that hides other sites' images' pixels.
  ipcMain.handle('icon:data', (event: IpcMainInvokeEvent, url: unknown) =>
    uiContents.includes(event.sender) && typeof url === 'string'
      ? iconAsDataUrl(url)
      : null,
  );

  // Glass turns solid while the window is out of focus.
  const frameState = (): FrameState => ({
    glass: GLASS,
    focused: win.isFocused(),
  });
  win.on('focus', () => send('window:frame', frameState()));
  win.on('blur', () => send('window:frame', frameState()));

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
    } else if (mod && key === 'd') {
      if (tabs.activeTabId) tabs.togglePin(tabs.activeTabId);
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
    } else if (mod && input.shift && /^Digit[1-9]$/.test(input.code)) {
      // Ctrl+Shift+1…9 switch to that space.
      const space = spaces[Number(input.code.slice(5)) - 1];
      if (space) switchSpace(space.id);
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
    const cursor = screen.getCursorScreenPoint();
    const content = win.getContentBounds();
    const display = screen.getDisplayMatching(content).bounds;
    console.log(
      `[Firn] cursor=${cursor.x},${cursor.y} window=${content.x},${content.y} ` +
        `${content.width}x${content.height} screen=${display.x},${display.y} ` +
        `${display.width}x${display.height} maximized=${win.isMaximized()}`,
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

  const onThemeChange = () => {
    if (!GLASS) win.setBackgroundColor(frameColor());
  };
  nativeTheme.on('updated', onThemeChange);

  // Save the whole session at once, a moment after anything changes, and
  // right away when the window closes.
  const saver = new SaveScheduler(() => {
    if (win.isDestroyed()) return;
    saveSession({
      spaces,
      tabs: tabs.serialize(),
      window: {
        ...windowState,
        bounds: win.getNormalBounds(),
        maximized: win.isMaximized(),
      },
      recentlyClosed: tabs.closedUrls,
    });
  });
  for (const event of ['resize', 'move', 'maximize', 'unmaximize'] as const)
    win.on(event as 'resize', () => saver.schedule());
  win.on('close', () => saver.flush());

  win.on('closed', () => {
    saver.cancel();
    for (const [channel, listener] of listeners)
      ipcMain.removeListener(channel, listener);
    ipcMain.removeHandler('icon:data');
    nativeTheme.removeListener('updated', onThemeChange);
    if (switcher) clearTimeout(switcher.timer);
    tabs.destroy();
    clearTimeout(topBarHideTimer);
    clearInterval(topBarWatch);
    clearInterval(topGlide);
    clearInterval(peekWatch);
    clearInterval(edgeWatch);
    clearTimeout(peekHideTimer);
    clearInterval(glide);
    for (const layer of [floating, topBar, peek])
      if (layer && !layer.webContents.isDestroyed()) layer.webContents.close();
  });

  // --- Load Firn's UI, then the first tab ---------------------------------

  for (const web of uiContents) lockUi(web);
  layersToStart = [peek, floating, topBar]
    .filter((layer) => layer !== null)
    .map((layer) => layer.webContents);
  startUi(win.webContents);

  // Restore the saved tabs; only the active one loads right away, the rest
  // load when first shown. A first run (or an empty session) opens the home
  // page.
  const savedTabs = (saved?.tabs ?? []).filter(
    (tab) => typeof tab.url === 'string' && tab.url,
  );
  tabs.closedUrls = saved?.recentlyClosed ?? [];
  // Tabs whose space is gone go to the first space.
  for (const tab of savedTabs) {
    if (!spaces.some((s) => s.id === tab.spaceId)) tab.spaceId = spaces[0].id;
    tabs.create(tab.url, { restore: tab, activate: false });
  }
  console.log(
    savedTabs.length
      ? `[Firn] Restored ${savedTabs.length} tab(s) from ${sessionPath()}`
      : `[Firn] No saved tabs found (${sessionPath()}); starting fresh.`,
  );
  if (savedTabs.length) {
    // The saved active tab, or the space's most recent one (a space can also
    // be empty).
    const inSpace = savedTabs.filter(
      (t) => t.basecamp || t.spaceId === windowState.activeSpaceId,
    );
    const activeId = inSpace.some((t) => t.id === saved?.window.activeTabId)
      ? saved!.window.activeTabId!
      : tabs.recentIds()[0];
    if (activeId) tabs.activate(activeId);
  } else {
    tabs.create(HOME_URL);
  }
};

// Only one Firn runs at a time. Opening it again brings the existing window
// forward instead, so two copies can never overwrite each other's session.
const isFirstInstance = app.requestSingleInstanceLock();
if (!isFirstInstance) app.quit();

app.on('second-instance', () => {
  const win = BrowserWindow.getAllWindows()[0];
  if (!win) return;
  if (win.isMinimized()) win.restore();
  win.focus();
});

app.whenReady().then(() => {
  if (!isFirstInstance) return;
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
