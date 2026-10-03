// The Electron engine: each page is a WebContentsView inside the window.
// Everything Electron-specific about web pages lives here (see
// src/engine/engine.ts for what the rest of Firn expects).

import { BrowserWindow, WebContentsView, type WebContents } from 'electron';
import {
  SCROLLBAR_CSS,
  SCROLLBAR_SCRIPT,
  SCROLLBAR_WORLD_ID,
} from '../scrollbar';
import { ICON_LINKS_SCRIPT, pickIcon, type IconLink } from '../favicon';
import type { SavedHistory } from '../types';
import type { Page, PageBounds, PageEngine, PageEvents } from './engine';

// Web pages, and the popup windows they open (e.g. "Sign in with Google"),
// always run with these safe settings.
const SAFE_WEB_PREFERENCES = {
  contextIsolation: true,
  sandbox: true,
  nodeIntegration: false,
};

// The isolated world where Firn reads a page's icon links (see
// src/favicon.ts), apart from the page's own scripts.
const ICON_WORLD_ID = 1998;

export class ElectronEngine implements PageEngine {
  constructor(
    private win: BrowserWindow,
    // Lets the window attach keyboard shortcuts to every page and keep its
    // own layers above new pages.
    private onPageCreated: (web: WebContents) => void,
  ) {}

  createPage(events: PageEvents): Page {
    const page = new ElectronPage(this.win, events);
    this.onPageCreated(page.web);
    return page;
  }

  windowSize() {
    const [width, height] = this.win.getContentSize();
    return { width, height };
  }

  isWindowFullscreen() {
    return this.win.isFullScreen();
  }

  setWindowFullscreen(on: boolean) {
    this.win.setFullScreen(on);
  }

  get closed() {
    return this.win.isDestroyed();
  }
}

class ElectronPage implements Page {
  private view: WebContentsView;

  private events: PageEvents;

  constructor(
    private win: BrowserWindow,
    events: PageEvents,
  ) {
    this.events = events;
    this.view = new WebContentsView({ webPreferences: SAFE_WEB_PREFERENCES });
    this.view.setBackgroundColor('#ffffff');
    this.view.setVisible(false);
    win.contentView.addChildView(this.view);
    this.wire();
  }

  get web() {
    return this.view.webContents;
  }

  get url() {
    return this.web.getURL();
  }

  get title() {
    return this.web.getTitle();
  }

  get isLoading() {
    return this.web.isLoading();
  }

  get canGoBack() {
    return this.web.navigationHistory.canGoBack();
  }

  get canGoForward() {
    return this.web.navigationHistory.canGoForward();
  }

  load(url: string) {
    this.web.loadURL(url);
  }

  restoreHistory(history: SavedHistory) {
    return this.web.navigationHistory.restore({
      entries: history.entries,
      index: history.index,
    });
  }

  history(max: number): SavedHistory {
    const all = this.web.navigationHistory.getAllEntries();
    const index = this.web.navigationHistory.getActiveIndex();
    const start = Math.max(0, all.length - max);
    return {
      entries: all.slice(start).map(({ url, title, pageState }) => ({
        url,
        title,
        pageState,
      })),
      index: Math.max(0, index - start),
    };
  }

  back() {
    if (this.canGoBack) this.web.navigationHistory.goBack();
  }

  forward() {
    if (this.canGoForward) this.web.navigationHistory.goForward();
  }

  reload(ignoreCache = false) {
    if (ignoreCache) this.web.reloadIgnoringCache();
    else this.web.reload();
  }

  stop() {
    this.web.stop();
  }

  focus() {
    this.web.focus();
  }

  toggleDevTools() {
    this.web.toggleDevTools();
  }

  place(bounds: PageBounds, cornerRadius: number) {
    this.view.setBorderRadius(cornerRadius);
    this.view.setBounds(bounds);
  }

  // Chromium's device emulation (what DevTools' device preview uses) lays
  // the page out at a set size, independent of the view's own size.
  holdLayout(size: { width: number; height: number } | null) {
    if (this.web.isDestroyed()) return;
    if (!size) {
      this.web.disableDeviceEmulation();
      return;
    }
    this.web.enableDeviceEmulation({
      screenPosition: 'desktop',
      screenSize: { width: 0, height: 0 },
      viewPosition: { x: 0, y: 0 },
      deviceScaleFactor: 0,
      viewSize: {
        width: Math.round(size.width),
        height: Math.round(size.height),
      },
      scale: 1,
    });
  }

  show() {
    this.view.setVisible(true);
  }

  hide() {
    this.view.setVisible(false);
  }

  raise() {
    if (!this.win.isDestroyed()) this.win.contentView.addChildView(this.view);
  }

  listen(events: PageEvents) {
    this.events = events;
  }

  destroy() {
    if (!this.win.isDestroyed())
      this.win.contentView.removeChildView(this.view);
    if (!this.web.isDestroyed()) this.web.close();
  }

  // Passes the page's reports on to whoever is listening now.
  private wire() {
    const web = this.web;
    const events = () => this.events;
    web.on('dom-ready', () => {
      // Firn's own floating scrollbar (src/scrollbar.ts).
      web.insertCSS(SCROLLBAR_CSS, { cssOrigin: 'user' }).catch(() => {});
      web
        .executeJavaScriptInIsolatedWorld(SCROLLBAR_WORLD_ID, [
          { code: SCROLLBAR_SCRIPT },
        ])
        .catch(() => {});
    });

    const update = () => {
      if (!web.isDestroyed()) events().onUpdate();
    };
    web.on('did-start-loading', update);
    web.on('did-stop-loading', update);
    web.on('did-navigate', update);
    web.on('did-navigate-in-page', update);
    web.on('page-title-updated', update);
    // Chromium reports the page's first favicon; look at all the icons the
    // page lists and pass on the best one (src/favicon.ts).
    let iconCheck = 0;
    web.on('page-favicon-updated', (_event, favicons) => {
      const fallback = favicons[0] ?? '';
      const check = ++iconCheck;
      const report = (url: string) => {
        if (check === iconCheck && !web.isDestroyed()) events().onFavicon(url);
      };
      web
        .executeJavaScriptInIsolatedWorld(ICON_WORLD_ID, [
          { code: ICON_LINKS_SCRIPT },
        ])
        .then((links: IconLink[]) =>
          report(pickIcon(Array.isArray(links) ? links : [], fallback)),
        )
        .catch(() => report(fallback));
    });
    web.on('did-start-navigation', (details) => {
      if (details.isMainFrame && !details.isSameDocument)
        events().onNavigationStart(details.url);
    });

    // Links that ask for a new tab become tabs, and Shift+clicked links
    // (which Chromium treats as "open in a new window") open in Lookout.
    // Real popup windows (sign-in flows and the like, which a page opens
    // with a size or other window features) stay popups so they keep
    // working.
    web.setWindowOpenHandler(({ url, disposition, features }) => {
      const isWeb = /^https?:/i.test(url);
      if (disposition === 'new-window' && !features && isWeb) {
        events().onLookout(url);
        return { action: 'deny' };
      }
      if (disposition === 'new-window') {
        return {
          action: 'allow',
          overrideBrowserWindowOptions: {
            autoHideMenuBar: true,
            webPreferences: SAFE_WEB_PREFERENCES,
          },
        };
      }
      if (isWeb) events().onOpenTab(url, disposition === 'background-tab');
      return { action: 'deny' };
    });

    // A press inside the page (the person starting to work in it).
    web.on('before-mouse-event', (_event, mouse) => {
      if (mouse.type === 'mouseDown') events().onFocus();
    });
    web.on('enter-html-full-screen', () => events().onFullscreen(true));
    web.on('leave-html-full-screen', () => events().onFullscreen(false));
  }
}
