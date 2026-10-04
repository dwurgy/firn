// The Electron engine: each page is a WebContentsView inside the window.
// Everything Electron-specific about web pages lives here (see
// src/engine/engine.ts for what the rest of Firn expects).

import path from 'node:path';
import {
  BrowserWindow,
  ipcMain,
  WebContentsView,
  type IpcMainEvent,
  type IpcMainInvokeEvent,
  type WebContents,
} from 'electron';
import {
  SCROLLBAR_CSS,
  SCROLLBAR_SCRIPT,
  SCROLLBAR_WORLD_ID,
} from '../scrollbar';
import { ICON_LINKS_SCRIPT, pickIcon, type IconLink } from '../favicon';
import type { SavedHistory } from '../types';
import type {
  EngineDownload,
  Page,
  PermissionKind,
  PermissionRequest,
  PageBounds,
  PageEngine,
  PageEvents,
} from './engine';

// Web pages, and the popup windows they open (e.g. "Sign in with Google"),
// always run with these safe settings.
const SAFE_WEB_PREFERENCES = {
  contextIsolation: true,
  sandbox: true,
  nodeIntegration: false,
  // Chromium's built-in PDF viewer, so PDFs open in the tab like in Chrome
  // instead of downloading. (Old-style browser plugins no longer exist;
  // this only turns on the PDF viewer.)
  plugins: true,
  // Firn's helper for saved passwords (src/page-preload.ts). It runs in
  // its own isolated world: the page can't see or call it.
  preload: path.join(__dirname, 'page-preload.cjs'),
};

// Saved passwords are only saved and filled on secure sites (and on this
// computer, for testing).
function loginOrigin(url: string) {
  try {
    const u = new URL(url);
    if (u.protocol === 'https:') return u.origin;
    if (u.protocol === 'http:' && /^(localhost|127\.0\.0\.1)$/.test(u.hostname))
      return u.origin;
  } catch {
    // Not a web address.
  }
  return null;
}

// The isolated world where Firn reads a page's icon links (see
// src/favicon.ts), apart from the page's own scripts.
const ICON_WORLD_ID = 1998;

// Permissions that are fine without asking, as in Chrome.
const HARMLESS_PERMISSIONS = new Set([
  'fullscreen',
  'pointerLock',
  'keyboardLock',
  'clipboard-sanitized-write',
  // Protected video (Netflix and the like).
  'mediaKeySystem',
  'persistent-storage',
  'background-sync',
  'background-fetch',
  'periodic-background-sync',
  'screen-wake-lock',
  'speaker-selection',
  'storage-access',
  'top-level-storage-access',
  'sensors',
  'payment-handler',
]);

// What a request asks for, in Firn's terms (null: nothing Firn asks about,
// so it's refused).
function kindsOf(
  permission: string,
  mediaTypes: string[] = [],
): PermissionKind[] | null {
  switch (permission) {
    case 'media': {
      const kinds: PermissionKind[] = [];
      if (mediaTypes.includes('video')) kinds.push('camera');
      if (mediaTypes.includes('audio')) kinds.push('microphone');
      return kinds.length ? kinds : null;
    }
    case 'geolocation':
    case 'geolocation-approximate':
      return ['location'];
    case 'notifications':
      return ['notifications'];
    case 'clipboard-read':
      return ['clipboard'];
    case 'openExternal':
      return ['external'];
    default:
      return null;
  }
}

function originOf(url: string | undefined) {
  try {
    return url ? new URL(url).origin : '';
  } catch {
    return '';
  }
}

// The kind of link an app opens, e.g. "zoommtg" for "zoommtg://...".
function schemeOf(url: string | undefined) {
  return /^([a-z][a-z0-9+.-]*):/i.exec(url ?? '')?.[1].toLowerCase() ?? '';
}

export class ElectronEngine implements PageEngine {
  private pages = new WeakMap<WebContents, ElectronPage>();

  constructor(
    private win: BrowserWindow,
    // Lets the window attach keyboard shortcuts to every page and keep its
    // own layers above new pages.
    private onPageCreated: (web: WebContents) => void,
  ) {}

  createPage(events: PageEvents): Page {
    const page = new ElectronPage(this.win, events);
    this.pages.set(page.web, page);
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

  // Downloads come from the browsing session that every page shares.
  onDownload(listener: (download: EngineDownload) => void) {
    const session = this.win.webContents.session;
    const handler = (_event: Electron.Event, item: Electron.DownloadItem) =>
      listener(wrapDownload(item));
    session.on('will-download', handler);
    this.win.on('closed', () =>
      session.removeListener('will-download', handler),
    );
  }

  onPermissionRequest(
    listener: (request: PermissionRequest) => void,
    isAllowed: (
      origin: string,
      kind: PermissionKind,
      detail: string,
    ) => boolean,
  ) {
    const session = this.win.webContents.session;
    session.setPermissionRequestHandler(
      (web, permission, callback, details) => {
        if (HARMLESS_PERMISSIONS.has(permission)) return callback(true);
        const media = 'mediaTypes' in details ? details.mediaTypes : undefined;
        const kinds = kindsOf(permission, media);
        const page = web ? (this.pages.get(web) ?? null) : null;
        if (!kinds || !page) return callback(false);
        const external =
          'externalURL' in details ? details.externalURL : undefined;
        let answered = false;
        listener({
          page,
          origin: originOf(details.requestingUrl),
          kinds,
          detail: permission === 'openExternal' ? schemeOf(external) : '',
          respond: (allow) => {
            if (answered) return;
            answered = true;
            callback(allow);
          },
        });
      },
    );
    session.setPermissionCheckHandler(
      (_web, permission, requestingOrigin, details) => {
        if (HARMLESS_PERMISSIONS.has(permission)) return true;
        const media =
          'mediaType' in details && details.mediaType
            ? [details.mediaType]
            : [];
        const kinds = kindsOf(permission, media);
        return (
          !!kinds &&
          kinds.every((kind) => isAllowed(originOf(requestingOrigin), kind, ''))
        );
      },
    );
    this.win.on('closed', () => {
      session.setPermissionRequestHandler(null);
      session.setPermissionCheckHandler(null);
    });
  }

  // The page helper's messages. Only Firn's own tab and Lookout pages, and
  // only their top frame, are listened to; the site is taken from the
  // frame's real address, never from the message.
  private loginProvider:
    | ((origin: string) => { username: string; password: string } | null)
    | null = null;
  private loginListening = false;

  private senderOrigin(event: IpcMainEvent | IpcMainInvokeEvent) {
    const page = this.pages.get(event.sender);
    const frame = event.senderFrame;
    // The top frame only (a frame inside the page could be another site).
    if (
      !page ||
      !frame ||
      frame.parent ||
      frame.frameTreeNodeId !== event.sender.mainFrame.frameTreeNodeId
    )
      return null;
    const origin = loginOrigin(frame.url);
    return origin ? { page, origin } : null;
  }

  setSavedLoginProvider(
    provider: (origin: string) => { username: string; password: string } | null,
  ) {
    this.loginProvider = provider;
    if (this.loginListening) return;
    this.loginListening = true;
    const onLogin = (event: IpcMainEvent, login: unknown) => {
      const from = this.senderOrigin(event);
      if (!from || !login || typeof login !== 'object') return;
      const { username, password } = login as Record<string, unknown>;
      if (typeof password !== 'string' || !password) return;
      from.page.reportLogin(
        from.origin,
        typeof username === 'string' ? username.slice(0, 200) : '',
        password.slice(0, 500),
      );
    };
    const onSavedLogin = (event: IpcMainInvokeEvent) => {
      const from = this.senderOrigin(event);
      return from ? (this.loginProvider?.(from.origin) ?? null) : null;
    };
    ipcMain.on('firn-page:login', onLogin);
    ipcMain.handle('firn-page:saved-login', onSavedLogin);
    this.win.on('closed', () => {
      ipcMain.removeListener('firn-page:login', onLogin);
      ipcMain.removeHandler('firn-page:saved-login');
    });
  }

  setNavigationGuard(
    check: (url: string) => Promise<string | null> | string | null,
    onBlocked: (page: Page | null, url: string, threat: string) => void,
  ) {
    const session = this.win.webContents.session;
    session.webRequest.onBeforeRequest(
      { urls: ['http://*/*', 'https://*/*'] },
      (details, callback) => {
        // Only whole pages (a frame inside a page is part of it).
        if (details.resourceType !== 'mainFrame') return callback({});
        const web = details.webContents;
        // Firn's own panels aren't checked.
        if (web && !this.pages.has(web) && this.isOwnUi(web))
          return callback({});
        Promise.resolve(check(details.url))
          .catch(() => null)
          .then((threat) => {
            if (!threat) return callback({});
            callback({ cancel: true });
            const page = web ? (this.pages.get(web) ?? null) : null;
            onBlocked(page, details.url, threat);
          });
      },
    );
    this.win.on('closed', () => session.webRequest.onBeforeRequest(null));
  }

  // The window's own web contents and its child views that aren't pages.
  private isOwnUi(web: WebContents) {
    if (web === this.win.webContents) return true;
    return this.win.contentView.children.some(
      (view) => view instanceof WebContentsView && view.webContents === web,
    );
  }

  download(url: string) {
    if (!this.win.isDestroyed()) this.win.webContents.session.downloadURL(url);
  }
}

function wrapDownload(item: Electron.DownloadItem): EngineDownload {
  return {
    url: item.getURL(),
    suggestedName: item.getFilename(),
    setSavePath: (path) => item.setSavePath(path),
    onProgress: (listener) =>
      item.on('updated', () =>
        listener(item.getReceivedBytes(), item.getTotalBytes()),
      ),
    onDone: (listener) =>
      item.on('done', (_event, state) =>
        listener(
          state === 'completed'
            ? 'completed'
            : state === 'cancelled'
              ? 'cancelled'
              : 'failed',
        ),
      ),
    cancel: () => item.cancel(),
  };
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

  find(
    text: string,
    { forward, newSearch }: { forward: boolean; newSearch: boolean },
  ) {
    if (!text) return this.stopFind();
    // Electron's `findNext` means "start a new search".
    this.web.findInPage(text, { forward, findNext: newSearch });
  }

  stopFind() {
    if (!this.web.isDestroyed()) this.web.stopFindInPage('keepSelection');
  }

  get zoom() {
    return this.web.getZoomFactor();
  }

  // Chromium shares a zoom between pages of the same site, like Chrome.
  setZoom(factor: number) {
    if (!this.web.isDestroyed()) this.web.setZoomFactor(factor);
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

  reportLogin(origin: string, username: string, password: string) {
    this.events.onLogin(origin, username, password);
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
    web.on('context-menu', (_event, params) =>
      events().onContextMenu({
        linkUrl: params.linkURL,
        imageUrl: params.mediaType === 'image' ? params.srcURL : '',
        selectionText: params.selectionText,
        isEditable: params.isEditable,
        canCut: params.editFlags.canCut,
        canCopy: params.editFlags.canCopy,
        canPaste: params.editFlags.canPaste,
        misspelledWord: params.misspelledWord,
        suggestions: params.dictionarySuggestions,
        cut: () => web.cut(),
        copy: () => web.copy(),
        paste: () => web.paste(),
        selectAll: () => web.selectAll(),
        copyImage: () => web.copyImageAt(params.x, params.y),
        // With no download handler yet, Chromium asks where to save it.
        saveImage: () => web.downloadURL(params.srcURL),
        replaceMisspelling: (word) => web.replaceMisspelling(word),
      }),
    );
    web.on('found-in-page', (_event, result) =>
      events().onFindResult({
        active: result.activeMatchOrdinal,
        total: result.matches,
      }),
    );
    web.on('zoom-changed', (_event, direction) =>
      events().onZoomRequest(direction),
    );
    web.on('enter-html-full-screen', () => events().onFullscreen(true));
    web.on('leave-html-full-screen', () => events().onFullscreen(false));
  }
}
