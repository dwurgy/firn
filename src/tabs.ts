// Owns the tabs of one window: the tab records (the data model) and the web
// page view behind each one. Everything that changes tabs goes through here,
// and every change is reported back so the UI can redraw the sidebar.

import { randomUUID } from 'node:crypto';
import { BrowserWindow, WebContentsView, type WebContents } from 'electron';
import { toNavigableUrl } from './url';
import type { NavCommand, NavState, Tab, TabsState } from './types';

interface Entry {
  tab: Tab;
  view: WebContentsView;
}

export interface PageBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface TabManagerOptions {
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
  private recentlyClosed: string[] = [];
  private fullscreen = false;

  constructor(
    private win: BrowserWindow,
    private options: TabManagerOptions,
  ) {}

  // --- Reading --------------------------------------------------------------

  get activeTabId() {
    return this.activeId;
  }

  private get active(): Entry | undefined {
    return this.activeId ? this.entries.get(this.activeId) : undefined;
  }

  state(): TabsState {
    return {
      activeTabId: this.activeId,
      tabs: this.order.map((id) => {
        const { tab, view } = this.entries.get(id)!;
        return {
          id,
          url: tab.url,
          title: tab.title,
          favicon: tab.favicon,
          isLoading: view.webContents.isLoading(),
          lastActiveAt: tab.lastActiveAt,
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
  create(url: string, opts: { activate?: boolean; after?: string } = {}) {
    const { activate = true, after } = opts;
    const id = randomUUID();
    const tab: Tab = {
      id,
      spaceId: this.options.spaceId,
      url,
      title: '',
      favicon: '',
      pinned: false,
      order: 0,
      lastActiveAt: Date.now(),
    };

    const view = new WebContentsView({ webPreferences: SAFE_WEB_PREFERENCES });
    view.setBorderRadius(this.options.pageRadius);
    view.setBackgroundColor('#ffffff');
    view.setVisible(false);
    this.win.contentView.addChildView(view);

    this.entries.set(id, { tab, view });
    const afterIndex = after ? this.order.indexOf(after) : -1;
    if (afterIndex >= 0) this.order.splice(afterIndex + 1, 0, id);
    else this.order.unshift(id);
    this.renumber();

    this.watch(id, view.webContents);
    this.options.onPageCreated(view.webContents);
    view.webContents.loadURL(url);

    if (activate || !this.activeId) this.activate(id);
    else this.emitTabs();
    return id;
  }

  activate(id: string) {
    const entry = this.entries.get(id);
    if (!entry) return;
    const previous = this.active;
    this.activeId = id;
    entry.tab.lastActiveAt = Date.now();
    if (previous && previous !== entry) previous.view.setVisible(false);
    this.layout();
    entry.view.setVisible(true);
    entry.view.webContents.focus();
    this.emitTabs();
    this.emitNav();
  }

  close(id: string) {
    const entry = this.entries.get(id);
    if (!entry) return;
    const index = this.order.indexOf(id);
    this.order.splice(index, 1);
    this.entries.delete(id);
    if (entry.tab.url) this.recentlyClosed.push(entry.tab.url);
    this.recentlyClosed = this.recentlyClosed.slice(-20);

    this.win.contentView.removeChildView(entry.view);
    entry.view.webContents.close();
    this.renumber();

    if (this.order.length === 0) {
      this.activeId = null;
      this.emitTabs();
      this.emitNav();
      this.options.onEmpty();
      return;
    }
    if (this.activeId === id) {
      // Move to the tab that slid into its place, or the one above.
      this.activate(this.order[Math.min(index, this.order.length - 1)]);
    } else {
      this.emitTabs();
    }
  }

  // Opens whatever was typed (an address or a search) in a new tab.
  openTyped(input: string) {
    const url = toNavigableUrl(input);
    if (url) this.create(url);
  }

  reopenClosed() {
    const url = this.recentlyClosed.pop();
    if (url) this.create(url);
  }

  // Moves to the next (1) or previous (-1) tab, wrapping around.
  cycle(step: 1 | -1) {
    if (!this.activeId || this.order.length < 2) return;
    const index = this.order.indexOf(this.activeId);
    const next = (index + step + this.order.length) % this.order.length;
    this.activate(this.order[next]);
  }

  // Tab ids from most to least recently used, for Ctrl+Tab.
  recentIds(): string[] {
    return [...this.entries.values()]
      .sort((a, b) => b.tab.lastActiveAt - a.tab.lastActiveAt)
      .map((e) => e.tab.id);
  }

  focusActive() {
    this.active?.view.webContents.focus();
  }

  activateIndex(index: number) {
    const id = index < 0 ? this.order.at(-1) : this.order[index];
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
