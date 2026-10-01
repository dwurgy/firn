import {
  app,
  BrowserWindow,
  ipcMain,
  nativeTheme,
  WebContentsView,
  type IpcMainEvent,
  type Input,
} from 'electron';
import path from 'node:path';
import started from 'electron-squirrel-startup';
import { toNavigableUrl } from './url';
import type { NavState } from './types';

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (started) {
  app.quit();
}

const HOME_URL = 'https://duckduckgo.com';

// Layout of the window frame (keep in sync with the CSS in src/ui/styles.css).
const TOOLBAR_HEIGHT = 52;
const PAGE_INSET = 8;
const PAGE_RADIUS = 12;

// Warm neutral frame colors, used before the UI has painted.
const FRAME = { light: '#e9e3da', dark: '#3a3734' };

const frameColor = () =>
  nativeTheme.shouldUseDarkColors ? FRAME.dark : FRAME.light;

const createWindow = () => {
  // The window itself hosts Firn's own UI (the toolbar).
  const win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 520,
    minHeight: 360,
    title: 'Firn',
    backgroundColor: frameColor(),
    // Hide the OS title bar so the toolbar can sit in it. macOS keeps its
    // traffic lights; on Windows and Linux Firn draws its own window buttons.
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 16, y: 18 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });

  // The web page lives in its own isolated view, floating inside the frame.
  const page = new WebContentsView({
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });
  page.setBackgroundColor('#ffffff');
  win.contentView.addChildView(page);

  // When a video (or any page) goes fullscreen, the page fills the whole
  // window edge to edge; otherwise it floats inside the frame.
  let pageFullscreen = false;

  const layoutPage = () => {
    const [width, height] = win.getContentSize();
    if (pageFullscreen) {
      page.setBorderRadius(0);
      page.setBounds({ x: 0, y: 0, width, height });
      return;
    }
    page.setBorderRadius(PAGE_RADIUS);
    page.setBounds({
      x: PAGE_INSET,
      y: TOOLBAR_HEIGHT,
      width: Math.max(0, width - PAGE_INSET * 2),
      height: Math.max(0, height - TOOLBAR_HEIGHT - PAGE_INSET),
    });
  };
  layoutPage();
  win.on('resize', layoutPage);

  // Remember whether the window was already fullscreen before the page asked,
  // so leaving video fullscreen puts things back exactly as they were.
  let wasWindowFullscreen = false;
  page.webContents.on('enter-html-full-screen', () => {
    pageFullscreen = true;
    wasWindowFullscreen = win.isFullScreen();
    if (!wasWindowFullscreen) win.setFullScreen(true);
    layoutPage();
  });
  page.webContents.on('leave-html-full-screen', () => {
    pageFullscreen = false;
    if (!wasWindowFullscreen) win.setFullScreen(false);
    layoutPage();
  });

  // --- Tell the UI what the page is doing ---------------------------------

  const web = page.webContents;
  const sendNavState = () => {
    if (win.isDestroyed()) return;
    const state: NavState = {
      url: web.getURL(),
      title: web.getTitle(),
      canGoBack: web.navigationHistory.canGoBack(),
      canGoForward: web.navigationHistory.canGoForward(),
      isLoading: web.isLoading(),
    };
    win.setTitle(state.title ? `${state.title} — Firn` : 'Firn');
    win.webContents.send('nav:state', state);
  };
  web.on('did-start-loading', sendNavState);
  web.on('did-stop-loading', sendNavState);
  web.on('did-navigate', sendNavState);
  web.on('did-navigate-in-page', sendNavState);
  web.on('page-title-updated', sendNavState);

  // No tabs yet, so links that want a new window open in the same view.
  web.setWindowOpenHandler(({ url }) => {
    if (/^https?:/i.test(url)) web.loadURL(url);
    return { action: 'deny' };
  });

  // Firn's own UI must never navigate away from itself.
  win.webContents.on('will-navigate', (event) => event.preventDefault());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));

  // --- Commands from the UI -----------------------------------------------

  // Only accept messages that come from this window's own UI.
  const fromOurUi = (event: IpcMainEvent) => event.sender === win.webContents;

  const onNavigate = (event: IpcMainEvent, input: unknown) => {
    if (!fromOurUi(event) || typeof input !== 'string') return;
    const url = toNavigableUrl(input);
    if (url) web.loadURL(url);
  };
  const onCommand = (event: IpcMainEvent, command: unknown) => {
    if (!fromOurUi(event)) return;
    runCommand(command);
  };
  const onReady = (event: IpcMainEvent) => {
    if (!fromOurUi(event)) return;
    sendNavState();
    sendMaximized();
  };
  const onWindowCommand = (event: IpcMainEvent, command: unknown) => {
    if (!fromOurUi(event)) return;
    if (command === 'minimize') win.minimize();
    else if (command === 'toggle-maximize')
      win.isMaximized() ? win.unmaximize() : win.maximize();
    else if (command === 'close') win.close();
  };

  // Lets the UI swap the maximize icon for a restore icon.
  const sendMaximized = () => {
    if (!win.isDestroyed())
      win.webContents.send('window:maximized', win.isMaximized());
  };
  win.on('maximize', sendMaximized);
  win.on('unmaximize', sendMaximized);

  const runCommand = (command: unknown) => {
    switch (command) {
      case 'back':
        if (web.navigationHistory.canGoBack()) web.navigationHistory.goBack();
        break;
      case 'forward':
        if (web.navigationHistory.canGoForward())
          web.navigationHistory.goForward();
        break;
      case 'reload':
        web.reload();
        break;
      case 'stop':
        web.stop();
        break;
    }
  };

  ipcMain.on('nav:navigate', onNavigate);
  ipcMain.on('nav:command', onCommand);
  ipcMain.on('ui:ready', onReady);
  ipcMain.on('window:command', onWindowCommand);

  // --- Keyboard shortcuts (work whether the page or the toolbar has focus) --

  const handleShortcut = (event: Electron.Event, input: Input) => {
    if (input.type !== 'keyDown') return;
    const mod = process.platform === 'darwin' ? input.meta : input.control;
    const key = input.key.toLowerCase();

    let handled = true;
    if (mod && key === 'l') {
      win.webContents.focus();
      win.webContents.send('ui:focus-address');
    } else if ((input.alt && key === 'arrowleft') || (mod && key === '[')) {
      runCommand('back');
    } else if ((input.alt && key === 'arrowright') || (mod && key === ']')) {
      runCommand('forward');
    } else if (key === 'f5' || (mod && key === 'r')) {
      if (input.shift) web.reloadIgnoringCache();
      else web.reload();
    } else if (
      key === 'f12' ||
      (mod && input.shift && key === 'i') ||
      (input.meta && input.alt && key === 'i')
    ) {
      web.toggleDevTools();
    } else {
      handled = false;
    }
    if (handled) event.preventDefault();
  };
  web.on('before-input-event', handleShortcut);
  win.webContents.on('before-input-event', handleShortcut);

  // --- Follow the OS light/dark setting ------------------------------------

  const onThemeChange = () => win.setBackgroundColor(frameColor());
  nativeTheme.on('updated', onThemeChange);

  win.on('closed', () => {
    ipcMain.removeListener('nav:navigate', onNavigate);
    ipcMain.removeListener('nav:command', onCommand);
    ipcMain.removeListener('ui:ready', onReady);
    ipcMain.removeListener('window:command', onWindowCommand);
    nativeTheme.removeListener('updated', onThemeChange);
    if (!web.isDestroyed()) web.close();
  });

  // --- Load Firn's UI, then the first page ---------------------------------

  if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
    win.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
  } else {
    win.loadFile(
      path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`),
    );
  }
  web.loadURL(HOME_URL);
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
