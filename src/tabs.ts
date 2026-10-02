// Owns the tabs of one window: the tab records (the data model) and the web
// page view behind each one. Everything that changes tabs goes through here,
// and every change is reported back so the UI can redraw the sidebar.
//
// Tabs from every space live here together; only the active space's tabs
// are shown, switched between and counted (tabs in other spaces stay as
// they are in the background).

import { randomUUID } from 'node:crypto';
import { BrowserWindow, WebContentsView, type WebContents } from 'electron';
import {
  SCROLLBAR_CSS,
  SCROLLBAR_SCRIPT,
  SCROLLBAR_WORLD_ID,
} from './scrollbar';
import { toNavigableUrl } from './url';
import type {
  NavCommand,
  NavState,
  SavedHistory,
  SavedTab,
  Tab,
  TabsState,
} from './types';

interface Entry {
  tab: Tab;
  view: WebContentsView;
  // Restored tabs wait to load their page until they're first shown.
  loaded: boolean;
  // Saved back/forward history to restore when the tab first loads.
  savedHistory?: SavedHistory;
}

// How much back/forward history is kept per tab in the saved session.
const MAX_SAVED_HISTORY = 50;

export interface PageBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface TabManagerOptions {
  // The space shown first.
  spaceId: string;
  // Where the page sits inside the window (changes with window size).
  pageBounds: () => PageBounds;
  pageRadius: number;
  onTabsChanged: (state: TabsState) => void;
  onNavChanged: (state: NavState) => void;
  // Lets the window attach keyboard shortcuts to every page.
  onPageCreated: (web: WebContents) => void;
  // The last tab was closed.
  onEmpty: () => void;
}

// Popup windows (e.g. "Sign in with Google") keep the same safe settings.
const SAFE_WEB_PREFERENCES = {
  contextIsolation: true,
  sandbox: true,
  nodeIntegration: false,
};

export class TabManager {
  private entries = new Map<string, Entry>();
  private order: string[] = [];
  private activeId: string | null = null;
  private spaceId: string;
  private recentlyClosed: string[] = [];
  private fullscreen = false;

  constructor(
    private win: BrowserWindow,
    private options: TabManagerOptions,
  ) {
    this.spaceId = options.spaceId;
  }

  // --- Reading --------------------------------------------------------------

  get activeTabId() {
    return this.activeId;
  }

  private get active(): Entry | undefined {
    return this.activeId ? this.entries.get(this.activeId) : undefined;
  }

  get activeSpaceId() {
    return this.spaceId;
  }

  // The active space's tabs, in sidebar order.
  private get shown(): string[] {
    return this.order.filter(
      (id) => this.entries.get(id)!.tab.spaceId === this.spaceId,
    );
  }

  // How many tabs a space has (for "delete this space?").
  countIn(spaceId: string) {
    return this.order.filter(
      (id) => this.entries.get(id)!.tab.spaceId === spaceId,
    ).length;
  }

  state(): TabsState {
    return {
      activeTabId: this.activeId,
      tabs: this.shown.map((id) => {
        const { tab, view } = this.entries.get(id)!;
        return {
          id,
          url: tab.url,
          title: tab.title,
          favicon: tab.favicon,
          isLoading: view.webContents.isLoading(),
          lastActiveAt: tab.lastActiveAt,
          pinned: tab.pinned,
          loaded: this.entries.get(id)!.loaded,
        };
      }),
    };
  }

  navState(): NavState {
    const entry = this.active;
    if (!entry) {
      return {
        url: '',
        title: '',
        canGoBack: false,
        canGoForward: false,
        isLoading: false,
      };
    }
    const web = entry.view.webContents;
    return {
      url: entry.tab.url,
      title: entry.tab.title,
      canGoBack: web.navigationHistory.canGoBack(),
      canGoForward: web.navigationHistory.canGoForward(),
      isLoading: web.isLoading(),
    };
  }

  // --- Changing tabs --------------------------------------------------------

  // Opens a tab. `after` places it right below another tab (e.g. links
  // opened from a page); otherwise it goes to the top of the list.
  // `restore` brings back a saved tab: it goes to the end of the list and
  // waits to load until it's first shown.
  create(
    url: string,
    opts: { activate?: boolean; after?: string; restore?: SavedTab } = {},
  ) {
    const { activate = true, after, restore } = opts;
    const id = restore?.id ?? randomUUID();
    const tab: Tab = {
      id,
      spaceId: restore?.spaceId ?? this.spaceId,
      url,
      title: restore?.title ?? '',
      favicon: restore?.favicon ?? '',
      pinned: restore?.pinned ?? false,
      homeUrl: restore?.homeUrl,
      order: 0,
      lastActiveAt: restore?.lastActiveAt ?? Date.now(),
    };

    const view = this.makeView(id);
    const entry: Entry = {
      tab,
      view,
      loaded: false,
      savedHistory: restore?.history,
    };
    this.entries.set(id, entry);
    // Pinned tabs always come first. New tabs go to the top of the everyday
    // tabs, or right below the tab they were opened from.
    const afterIndex = after ? this.order.indexOf(after) : -1;
    const afterPinned = after ? this.entries.get(after)?.tab.pinned : false;
    if (restore) this.order.push(id);
    else if (afterIndex >= 0 && !afterPinned)
      this.order.splice(afterIndex + 1, 0, id);
    else this.order.splice(this.firstUnpinnedIndex(), 0, id);
    if (restore) this.keepPinnedFirst();
    this.renumber();

    if (!restore) this.load(entry);

    if (activate || (!this.activeId && !restore)) this.activate(id);
    else this.emitTabs();
    return id;
  }

  // --- Spaces ---------------------------------------------------------------

  // Shows another space: its most recently used tab comes back (or an empty
  // page, if it has no tabs yet).
  setSpace(spaceId: string) {
    if (spaceId === this.spaceId) return;
    this.active?.view.setVisible(false);
    this.spaceId = spaceId;
    this.activeId = null;
    const next = this.recentIds()[0];
    if (next) {
      this.activate(next);
    } else {
      this.emitTabs();
      this.emitNav();
    }
  }

  // Moves a tab to another space (from its right-click menu). If it was the
  // tab on screen, the space's next most recent tab takes its place.
  moveToSpace(id: string, spaceId: string) {
    const entry = this.entries.get(id);
    if (!entry || entry.tab.spaceId === spaceId) return;
    entry.tab.spaceId = spaceId;
    if (this.activeId === id) {
      entry.view.setVisible(false);
      this.activeId = null;
      const next = this.recentIds()[0];
      if (next) {
        this.activate(next);
        return;
      }
      this.emitNav();
    }
    this.emitTabs();
  }

  // Closes every tab in a space (when the space is deleted).
  closeSpace(spaceId: string) {
    for (const id of [...this.order]) {
      const entry = this.entries.get(id)!;
      if (entry.tab.spaceId !== spaceId) continue;
      this.order.splice(this.order.indexOf(id), 1);
      this.entries.delete(id);
      this.win.contentView.removeChildView(entry.view);
      entry.view.webContents.close();
    }
    this.renumber();
  }

  // A fresh, empty page view for a tab, wired up and ready to load.
  private makeView(id: string) {
    const view = new WebContentsView({ webPreferences: SAFE_WEB_PREFERENCES });
    view.setBorderRadius(this.options.pageRadius);
    view.setBackgroundColor('#ffffff');
    view.setVisible(false);
    this.win.contentView.addChildView(view);
    this.watch(id, view.webContents);
    this.options.onPageCreated(view.webContents);
    return view;
  }

  private firstUnpinnedIndex() {
    const index = this.order.findIndex(
      (id) => !this.entries.get(id)!.tab.pinned,
    );
    return index < 0 ? this.order.length : index;
  }

  private keepPinnedFirst() {
    const pinned = this.order.filter((id) => this.entries.get(id)!.tab.pinned);
    const others = this.order.filter((id) => !this.entries.get(id)!.tab.pinned);
    this.order = [...pinned, ...others];
  }

  // --- Pinned tabs ----------------------------------------------------------

  // Pins a tab: it moves to the end of the pinned grid and remembers the page
  // it's on as its home.
  pin(id: string) {
    const entry = this.entries.get(id);
    if (!entry || entry.tab.pinned) return;
    entry.tab.pinned = true;
    entry.tab.homeUrl = entry.tab.url;
    this.order.splice(this.order.indexOf(id), 1);
    this.order.splice(this.firstUnpinnedIndex(), 0, id);
    this.renumber();
    this.emitTabs();
  }

  // Unpins a tab: it moves to the top of the everyday tabs.
  unpin(id: string) {
    const entry = this.entries.get(id);
    if (!entry || !entry.tab.pinned) return;
    entry.tab.pinned = false;
    entry.tab.homeUrl = undefined;
    this.order.splice(this.order.indexOf(id), 1);
    this.order.splice(this.firstUnpinnedIndex(), 0, id);
    this.renumber();
    this.emitTabs();
  }

  togglePin(id: string) {
    if (this.entries.get(id)?.tab.pinned) this.unpin(id);
    else this.pin(id);
  }

  // Takes a pinned tab back to its home page.
  goHome(id: string) {
    const entry = this.entries.get(id);
    const home = entry?.tab.homeUrl;
    if (!entry || !home) return;
    entry.tab.url = home;
    entry.savedHistory = undefined;
    if (entry.loaded) entry.view.webContents.loadURL(home);
    this.emitTabs();
  }

  // "Closing" a pinned tab keeps the pin: its page is unloaded and it goes
  // back to its home page, to load again when it's next clicked.
  private unloadPinned(entry: Entry) {
    const { tab } = entry;
    const wasActive = this.activeId === tab.id;
    if (wasActive) {
      const next = this.recentIds().find((other) => other !== tab.id);
      if (next) this.activate(next);
    }
    if (!entry.loaded && !wasActive) return;
    // Swap in a fresh, empty page view.
    this.win.contentView.removeChildView(entry.view);
    entry.view.webContents.close();
    entry.view = this.makeView(tab.id);
    entry.loaded = false;
    entry.savedHistory = undefined;
    tab.url = tab.homeUrl ?? tab.url;
    if (this.activeId === tab.id) this.activate(tab.id);
    else this.emitTabs();
  }

  // Loads a tab's page: its saved history if it has one (landing back on the
  // same page and scroll position), otherwise its address.
  private load(entry: Entry) {
    if (entry.loaded) return;
    entry.loaded = true;
    const web = entry.view.webContents;
    const history = entry.savedHistory;
    entry.savedHistory = undefined;
    if (history?.entries.length) {
      web.navigationHistory
        .restore({ entries: history.entries, index: history.index })
        .catch(() => web.loadURL(entry.tab.url));
    } else {
      web.loadURL(entry.tab.url);
    }
  }

  // Every tab as it should be saved, in sidebar order.
  serialize(): SavedTab[] {
    return this.order.map((id) => {
      const { tab, view, loaded, savedHistory } = this.entries.get(id)!;
      let history = savedHistory;
      const web = view.webContents;
      if (loaded && !web.isDestroyed()) {
        const all = web.navigationHistory.getAllEntries();
        const index = web.navigationHistory.getActiveIndex();
        // Keep the most recent part of a long history.
        const start = Math.max(0, all.length - MAX_SAVED_HISTORY);
        history = {
          entries: all.slice(start).map(({ url, title, pageState }) => ({
            url,
            title,
            pageState,
          })),
          index: Math.max(0, index - start),
        };
      }
      return { ...tab, history };
    });
  }

  get closedUrls() {
    return [...this.recentlyClosed];
  }

  set closedUrls(urls: string[]) {
    this.recentlyClosed = urls.slice(-20);
  }

  activate(id: string) {
    const entry = this.entries.get(id);
    if (!entry || entry.tab.spaceId !== this.spaceId) return;
    const previous = this.active;
    this.activeId = id;
    entry.tab.lastActiveAt = Date.now();
    if (previous && previous !== entry) previous.view.setVisible(false);
    this.load(entry);
    this.layout();
    entry.view.setVisible(true);
    entry.view.webContents.focus();
    this.emitTabs();
    this.emitNav();
  }

  close(id: string) {
    const entry = this.entries.get(id);
    if (!entry) return;
    if (entry.tab.pinned) {
      this.unloadPinned(entry);
      return;
    }
    const index = this.shown.indexOf(id);
    this.order.splice(this.order.indexOf(id), 1);
    this.entries.delete(id);
    if (entry.tab.url) this.recentlyClosed.push(entry.tab.url);
    this.recentlyClosed = this.recentlyClosed.slice(-20);

    this.win.contentView.removeChildView(entry.view);
    entry.view.webContents.close();
    this.renumber();

    const shown = this.shown;
    if (shown.length === 0) {
      this.activeId = null;
      this.emitTabs();
      this.emitNav();
      this.options.onEmpty();
      return;
    }
    if (this.activeId === id) {
      // Move to the tab that slid into its place, or the one above.
      this.activate(shown[Math.min(index, shown.length - 1)]);
    } else {
      this.emitTabs();
    }
  }

  // Opens whatever was typed (an address or a search) in a new tab.
  openTyped(input: string) {
    const url = toNavigableUrl(input);
    if (url) this.create(url);
  }

  // Moves a tab to a new position within its own group (pinned tiles or
  // everyday tabs), for drag to reorder.
  move(id: string, toIndex: number) {
    const entry = this.entries.get(id);
    if (!entry) return;
    const group = this.shown.filter(
      (other) => this.entries.get(other)!.tab.pinned === entry.tab.pinned,
    );
    const to = Math.max(0, Math.min(toIndex, group.length - 1));
    if (group.indexOf(id) === to) return;
    group.splice(group.indexOf(id), 1);
    group.splice(to, 0, id);
    const others = this.order.filter((other) => !group.includes(other));
    this.order = entry.tab.pinned
      ? [...group, ...others]
      : [...others, ...group];
    this.renumber();
    this.emitTabs();
  }

  reopenClosed() {
    const url = this.recentlyClosed.pop();
    if (url) this.create(url);
  }

  // Moves to the next (1) or previous (-1) tab, wrapping around.
  cycle(step: 1 | -1) {
    const shown = this.shown;
    if (!this.activeId || shown.length < 2) return;
    const index = shown.indexOf(this.activeId);
    const next = (index + step + shown.length) % shown.length;
    this.activate(shown[next]);
  }

  // The active space's tab ids from most to least recently used, for
  // Ctrl+Tab.
  recentIds(): string[] {
    return [...this.entries.values()]
      .filter((e) => e.tab.spaceId === this.spaceId)
      .sort((a, b) => b.tab.lastActiveAt - a.tab.lastActiveAt)
      .map((e) => e.tab.id);
  }

  focusActive() {
    this.active?.view.webContents.focus();
  }

  activateIndex(index: number) {
    const shown = this.shown;
    const id = index < 0 ? shown.at(-1) : shown[index];
    if (id) this.activate(id);
  }

  // --- The active tab ------------------------------------------------------

  navigate(input: string) {
    const url = toNavigableUrl(input);
    if (!url) return;
    const entry = this.active;
    if (!entry) {
      this.create(url);
      return;
    }
    entry.tab.url = url;
    entry.loaded = true;
    entry.savedHistory = undefined;
    entry.view.setVisible(true);
    entry.view.webContents.loadURL(url);
    entry.view.webContents.focus();
    this.emitTabs();
  }

  command(command: NavCommand) {
    const web = this.active?.view.webContents;
    if (!web) return;
    const history = web.navigationHistory;
    if (command === 'back' && history.canGoBack()) history.goBack();
    if (command === 'forward' && history.canGoForward()) history.goForward();
    if (command === 'reload') web.reload();
    if (command === 'stop') web.stop();
  }

  hardReload() {
    this.active?.view.webContents.reloadIgnoringCache();
  }

  toggleDevTools() {
    this.active?.view.webContents.toggleDevTools();
  }

  // --- Layout ---------------------------------------------------------------

  layout() {
    const entry = this.active;
    if (!entry) return;
    if (this.fullscreen) {
      const [width, height] = this.win.getContentSize();
      entry.view.setBorderRadius(0);
      entry.view.setBounds({ x: 0, y: 0, width, height });
    } else {
      entry.view.setBorderRadius(this.options.pageRadius);
      entry.view.setBounds(this.options.pageBounds());
    }
  }

  destroy() {
    for (const { view } of this.entries.values()) {
      if (!view.webContents.isDestroyed()) view.webContents.close();
    }
    this.entries.clear();
    this.order = [];
  }

  // --- Internals ------------------------------------------------------------

  private renumber() {
    this.order.forEach((id, i) => (this.entries.get(id)!.tab.order = i));
  }

  private emitTabs() {
    this.options.onTabsChanged(this.state());
  }

  private emitNav() {
    this.options.onNavChanged(this.navState());
  }

  // Keeps a tab's record in step with its page, and reports changes.
  private watch(id: string, web: WebContents) {
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
      const entry = this.entries.get(id);
      if (!entry || web.isDestroyed()) return;
      const url = web.getURL();
      if (url) entry.tab.url = url;
      entry.tab.title = web.getTitle();
      this.emitTabs();
      if (id === this.activeId) this.emitNav();
    };
    web.on('did-start-loading', update);
    web.on('did-stop-loading', update);
    web.on('did-navigate', update);
    web.on('did-navigate-in-page', update);
    web.on('page-title-updated', update);
    web.on('page-favicon-updated', (_event, favicons) => {
      const entry = this.entries.get(id);
      if (!entry) return;
      entry.tab.favicon = favicons[0] ?? '';
      this.emitTabs();
    });
    web.on('did-start-navigation', (details) => {
      // A new site gets a fresh favicon instead of keeping the old one.
      const entry = this.entries.get(id);
      if (entry && details.isMainFrame && !details.isSameDocument) {
        if (safeHost(details.url) !== safeHost(entry.tab.url)) {
          entry.tab.favicon = '';
        }
      }
    });

    // Links that ask for a new tab open one right below this tab. Real popup
    // windows (sign-in flows and the like) stay popups so they keep working.
    web.setWindowOpenHandler(({ url, disposition }) => {
      if (disposition === 'new-window') {
        return {
          action: 'allow',
          overrideBrowserWindowOptions: {
            autoHideMenuBar: true,
            webPreferences: SAFE_WEB_PREFERENCES,
          },
        };
      }
      if (/^https?:/i.test(url)) {
        this.create(url, {
          after: id,
          activate: disposition !== 'background-tab',
        });
      }
      return { action: 'deny' };
    });

    web.on('enter-html-full-screen', () => this.setFullscreen(true));
    web.on('leave-html-full-screen', () => this.setFullscreen(false));
  }

  // Remember whether the window was already fullscreen before the page asked,
  // so leaving video fullscreen puts things back exactly as they were.
  private wasWindowFullscreen = false;

  private setFullscreen(on: boolean) {
    this.fullscreen = on;
    if (on) {
      this.wasWindowFullscreen = this.win.isFullScreen();
      if (!this.wasWindowFullscreen) this.win.setFullScreen(true);
    } else if (!this.wasWindowFullscreen) {
      this.win.setFullScreen(false);
    }
    this.layout();
  }
}

function safeHost(url: string) {
  try {
    return new URL(url).host;
  } catch {
    return '';
  }
}
