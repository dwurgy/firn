// Owns the tabs of one window: the tab records (the data model) and the web
// page behind each one. Everything that changes tabs goes through here, and
// every change is reported back so the UI can redraw the sidebar.
//
// Pages come from the browser engine (src/engine/engine.ts); nothing here
// depends on Electron.
//
// Tabs from every space live here together; only the active space's tabs
// (plus Basecamp, which every space shares) are shown, switched between and
// counted. Tabs in other spaces stay as they are in the background.
//
// The order always keeps three groups: Basecamp first, then pinned tabs,
// then everyday tabs.

import { randomUUID } from 'node:crypto';
import type { Page, PageBounds, PageEngine, PageEvents } from './engine/engine';
import { toNavigableUrl } from './url';
import type {
  NavCommand,
  NavState,
  SavedHistory,
  SavedTab,
  SplitGroup,
  Tab,
  TabsState,
} from './types';

interface Entry {
  tab: Tab;
  page: Page;
  // Restored tabs wait to load their page until they're first shown.
  loaded: boolean;
  // Saved back/forward history to restore when the tab first loads.
  savedHistory?: SavedHistory;
}

// How much back/forward history is kept per tab in the saved session.
const MAX_SAVED_HISTORY = 50;

// Basecamp holds at most this many sites.
export const BASECAMP_MAX = 12;

// Which of the three groups a tab is in (the order keeps them in this order).
const BASECAMP = 0;
const PINNED = 1;
const EVERYDAY = 2;
const groupOf = (tab: Tab) =>
  tab.basecamp ? BASECAMP : tab.pinned ? PINNED : EVERYDAY;

// Split view: the gap between the two sides (the same as the page's inset
// from the window), and how narrow a side can get.
export const SPLIT_GAP = 8;
const SPLIT_MIN = 0.2;

// Where each side of a split view sits within the page's area.
export function splitRects(area: PageBounds, sizes: number[]): PageBounds[] {
  const first = Math.round((area.width - SPLIT_GAP) * sizes[0]);
  return [
    { ...area, width: first },
    {
      ...area,
      x: area.x + first + SPLIT_GAP,
      width: area.width - first - SPLIT_GAP,
    },
  ];
}

interface TabManagerOptions {
  // The space shown first.
  spaceId: string;
  // Where the page sits inside the window (changes with window size), or
  // would sit with its top edge at `top`.
  pageBounds: (top?: number) => PageBounds;
  pageRadius: number;
  onTabsChanged: (state: TabsState) => void;
  onNavChanged: (state: NavState) => void;
  // The last tab was closed.
  onEmpty: () => void;
  // A link was Shift+clicked: preview it in Lookout.
  onLookout: (url: string) => void;
  // A tab's page went somewhere (`newVisit`), or its title or icon became
  // known (for the browsing history).
  onVisit: (
    url: string,
    title: string,
    favicon: string,
    newVisit: boolean,
  ) => void;
}

export class TabManager {
  private entries = new Map<string, Entry>();
  private order: string[] = [];
  private activeId: string | null = null;
  private spaceId: string;
  // The tab each space was last on, to return to when switching back.
  private lastInSpace = new Map<string, string>();
  // Split views, and the tabs whose pages are on screen right now (two
  // when the active tab is in a split view).
  private splits = new Map<string, SplitGroup>();
  private onScreen: string[] = [];
  private recentlyClosed: string[] = [];
  private fullscreen = false;

  constructor(
    private engine: PageEngine,
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

  // Basecamp and the active space's tabs, in sidebar order.
  private get shown(): string[] {
    return this.order.filter((id) => this.isShown(id));
  }

  private isShown(id: string) {
    const tab = this.entries.get(id)?.tab;
    return !!tab && (tab.basecamp || tab.spaceId === this.spaceId);
  }

  // Which space a tab belongs to (none for Basecamp, which is in every one).
  spaceOfTab(id: string) {
    const tab = this.entries.get(id)?.tab;
    return tab && !tab.basecamp ? tab.spaceId : undefined;
  }

  // Every tab in every space (for the command bar), Basecamp first.
  allTabs() {
    return this.order.map((id) => {
      const { tab, page, loaded } = this.entries.get(id)!;
      return {
        id,
        spaceId: tab.spaceId,
        url: tab.url,
        title: tab.title,
        favicon: tab.favicon,
        isLoading: page.isLoading,
        lastActiveAt: tab.lastActiveAt,
        pinned: tab.pinned,
        basecamp: !!tab.basecamp,
        loaded,
        splitId: tab.splitGroupId,
      };
    });
  }

  // How many tabs a space has of its own (for "delete this space?").
  countIn(spaceId: string) {
    return this.order.filter((id) => {
      const { tab } = this.entries.get(id)!;
      return !tab.basecamp && tab.spaceId === spaceId;
    }).length;
  }

  get basecampCount() {
    return this.order.filter((id) => this.entries.get(id)!.tab.basecamp).length;
  }

  state(): TabsState {
    return {
      activeTabId: this.activeId,
      tabs: this.shown.map((id) => {
        const { tab, page } = this.entries.get(id)!;
        return {
          id,
          url: tab.url,
          title: tab.title,
          favicon: tab.favicon,
          isLoading: page.isLoading,
          lastActiveAt: tab.lastActiveAt,
          pinned: tab.pinned,
          basecamp: !!tab.basecamp,
          loaded: this.entries.get(id)!.loaded,
          splitId: tab.splitGroupId,
        };
      }),
      splits: [...this.splits.values()].filter(
        (split) => split.spaceId === this.spaceId,
      ),
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
    const { page } = entry;
    return {
      url: entry.tab.url,
      title: entry.tab.title,
      canGoBack: page.canGoBack,
      canGoForward: page.canGoForward,
      isLoading: page.isLoading,
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
      basecamp: restore?.basecamp || undefined,
      homeUrl: restore?.homeUrl,
      order: 0,
      lastActiveAt: restore?.lastActiveAt ?? Date.now(),
    };

    const page = this.makePage(id);
    const entry: Entry = {
      tab,
      page,
      loaded: false,
      savedHistory: restore?.history,
    };
    this.entries.set(id, entry);
    // New tabs go to the top of the everyday tabs, or right below the
    // everyday tab they were opened from.
    const afterTab = after ? this.entries.get(after)?.tab : undefined;
    if (restore) this.order.push(id);
    else if (afterTab && groupOf(afterTab) === EVERYDAY)
      this.order.splice(this.order.indexOf(after!) + 1, 0, id);
    else this.order.splice(this.groupStart(EVERYDAY), 0, id);
    if (restore) this.keepGroupsInOrder();
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
    this.hideOnScreen();
    this.spaceId = spaceId;
    this.activeId = null;
    // The tab this space was last on, or its most recent own tab.
    const remembered = this.lastInSpace.get(spaceId);
    const recent = this.recentIds();
    const next =
      remembered && this.isShown(remembered)
        ? remembered
        : (recent.find((id) => !this.entries.get(id)!.tab.basecamp) ??
          recent[0]);
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
    if (!entry || entry.tab.basecamp || entry.tab.spaceId === spaceId) return;
    this.separate(id);
    entry.tab.spaceId = spaceId;
    if (this.activeId === id) {
      this.hideOnScreen();
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
    for (const id of this.order.slice()) {
      const entry = this.entries.get(id)!;
      if (entry.tab.basecamp || entry.tab.spaceId !== spaceId) continue;
      this.separate(id);
      this.order.splice(this.order.indexOf(id), 1);
      this.entries.delete(id);
      entry.page.destroy();
    }
    this.renumber();
  }

  // Where a group starts in the order (or would start, if it's empty).
  private groupStart(group: number) {
    const index = this.order.findIndex(
      (id) => groupOf(this.entries.get(id)!.tab) >= group,
    );
    return index < 0 ? this.order.length : index;
  }

  // Where a group ends: the spot right after its last tab.
  private groupEnd(group: number) {
    return this.groupStart(group + 1);
  }

  private keepGroupsInOrder() {
    this.order = [0, 1, 2].flatMap((group) =>
      this.order.filter((id) => groupOf(this.entries.get(id)!.tab) === group),
    );
  }

  // Takes a tab out of the order and puts it back at `index` (worked out
  // after it's been taken out).
  private reinsert(id: string, where: () => number) {
    this.order.splice(this.order.indexOf(id), 1);
    this.order.splice(where(), 0, id);
    this.renumber();
    this.emitTabs();
  }

  // --- Pinned tabs and Basecamp ----------------------------------------------

  // Pins a tab: it moves to the end of the space's pinned tabs and remembers
  // the page it's on as its home.
  pin(id: string) {
    const tab = this.entries.get(id)?.tab;
    if (!tab || groupOf(tab) !== EVERYDAY) return;
    this.separate(id);
    tab.pinned = true;
    tab.homeUrl = tab.url;
    this.reinsert(id, () => this.groupEnd(PINNED));
  }

  // Unpins a tab: it moves to the top of the everyday tabs.
  unpin(id: string) {
    const tab = this.entries.get(id)?.tab;
    if (!tab || groupOf(tab) !== PINNED) return;
    tab.pinned = false;
    tab.homeUrl = undefined;
    this.reinsert(id, () => this.groupStart(EVERYDAY));
  }

  togglePin(id: string) {
    const tab = this.entries.get(id)?.tab;
    if (tab?.pinned) this.unpin(id);
    else this.pin(id);
  }

  // Adds a tab to Basecamp (shown in every space), keeping its home page if
  // it was pinned.
  addToBasecamp(id: string) {
    const tab = this.entries.get(id)?.tab;
    if (!tab || tab.basecamp || this.basecampCount >= BASECAMP_MAX) return;
    this.separate(id);
    tab.basecamp = true;
    tab.pinned = false;
    tab.homeUrl = tab.homeUrl ?? tab.url;
    this.reinsert(id, () => this.groupEnd(BASECAMP));
  }

  // Takes a tab out of Basecamp: it becomes an everyday tab in this space.
  removeFromBasecamp(id: string) {
    const tab = this.entries.get(id)?.tab;
    if (!tab?.basecamp) return;
    tab.basecamp = undefined;
    tab.homeUrl = undefined;
    tab.spaceId = this.spaceId;
    this.reinsert(id, () => this.groupStart(EVERYDAY));
  }

  // Closes the active space's everyday tabs (the divider's "Clear").
  clearEveryday() {
    const everyday = this.shown.filter(
      (id) => groupOf(this.entries.get(id)!.tab) === EVERYDAY,
    );
    if (!everyday.length) return;
    const wasActive = this.activeId && everyday.includes(this.activeId);
    for (const id of everyday) {
      const entry = this.entries.get(id)!;
      this.separate(id);
      this.order.splice(this.order.indexOf(id), 1);
      this.entries.delete(id);
      if (entry.tab.url) this.recentlyClosed.push(entry.tab.url);
      entry.page.destroy();
    }
    this.recentlyClosed = this.recentlyClosed.slice(-20);
    this.renumber();
    if (wasActive) {
      // Back to the most recent page that's still open, if there is one.
      this.activeId = null;
      const next = this.recentIds().find((id) => this.entries.get(id)!.loaded);
      if (next) return this.activate(next);
      this.emitNav();
    }
    this.emitTabs();
  }

  // Takes a pinned tab back to its home page.
  goHome(id: string) {
    const entry = this.entries.get(id);
    const home = entry?.tab.homeUrl;
    if (!entry || !home) return;
    entry.tab.url = home;
    entry.savedHistory = undefined;
    if (entry.loaded) entry.page.load(home);
    this.emitTabs();
  }

  // "Closing" a pinned tab keeps the pin: its page is unloaded and it goes
  // back to its home page, to load again when it's next clicked.
  private unloadPinned(entry: Entry) {
    const { tab } = entry;
    const wasActive = this.activeId === tab.id;
    if (wasActive) {
      const others = this.recentIds().filter((other) => other !== tab.id);
      const next =
        others.find((other) => this.entries.get(other)!.loaded) ?? others[0];
      if (next) this.activate(next);
    }
    if (!entry.loaded && !wasActive) return;
    // Swap in a fresh, empty page.
    entry.page.destroy();
    entry.page = this.makePage(tab.id);
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
    const { page } = entry;
    const history = entry.savedHistory;
    entry.savedHistory = undefined;
    if (history?.entries.length) {
      page.restoreHistory(history).catch(() => page.load(entry.tab.url));
    } else {
      page.load(entry.tab.url);
    }
  }

  // Every tab as it should be saved, in sidebar order.
  serialize(): SavedTab[] {
    return this.order.map((id) => {
      const { tab, page, loaded, savedHistory } = this.entries.get(id)!;
      // Keep the most recent part of a long history.
      const history = loaded ? page.history(MAX_SAVED_HISTORY) : savedHistory;
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
    if (!entry || !this.isShown(id)) return;
    this.activeId = id;
    this.lastInSpace.set(this.spaceId, id);
    entry.tab.lastActiveAt = Date.now();
    // Both sides of a split view are on screen together.
    const next = this.splitOf(id)?.tabIds ?? [id];
    for (const other of this.onScreen)
      if (!next.includes(other)) this.entries.get(other)?.page.hide();
    this.onScreen = next;
    for (const shownId of next) this.load(this.entries.get(shownId)!);
    this.layout();
    entry.page.focus();
    this.emitTabs();
    this.emitNav();
  }

  private hideOnScreen() {
    for (const id of this.onScreen) this.entries.get(id)?.page.hide();
    this.onScreen = [];
  }

  // --- Split view -------------------------------------------------------------

  private splitOf(id: string) {
    const splitId = this.entries.get(id)?.tab.splitGroupId;
    return splitId ? this.splits.get(splitId) : undefined;
  }

  // Can `id` be shown beside the active tab? (Two everyday tabs of the same
  // space, neither already in a split view.)
  canSplitWith(id: string) {
    const other = this.entries.get(id)?.tab;
    const active = this.active?.tab;
    return (
      !!other &&
      !!active &&
      other !== active &&
      groupOf(other) === EVERYDAY &&
      groupOf(active) === EVERYDAY &&
      other.spaceId === active.spaceId &&
      !other.splitGroupId &&
      !active.splitGroupId
    );
  }

  // The tabs that could go beside the active one, in sidebar order.
  splitCandidates() {
    return this.shown
      .filter((id) => this.canSplitWith(id))
      .map((id) => this.entries.get(id)!.tab);
  }

  // Shows `id` beside the active tab, half and half. In the sidebar the two
  // become one row, where the active tab was.
  splitWith(id: string) {
    if (!this.canSplitWith(id)) return;
    const activeId = this.activeId!;
    const split: SplitGroup = {
      id: randomUUID(),
      spaceId: this.spaceId,
      tabIds: [activeId, id],
      layout: 'columns',
      sizes: [0.5, 0.5],
    };
    this.splits.set(split.id, split);
    for (const tabId of split.tabIds)
      this.entries.get(tabId)!.tab.splitGroupId = split.id;
    this.order.splice(this.order.indexOf(id), 1);
    this.order.splice(this.order.indexOf(activeId) + 1, 0, id);
    this.renumber();
    this.activate(activeId);
  }

  // Ends a split view: both tabs carry on as ordinary tabs, and the one that
  // was active fills the page again.
  unsplit(id: string) {
    if (!this.splitOf(id)) return;
    this.separate(id);
    if (this.activeId) this.activate(this.activeId);
    else this.emitTabs();
  }

  // Takes a tab's split view apart (without redrawing).
  private separate(id: string) {
    const split = this.splitOf(id);
    if (!split) return;
    this.splits.delete(split.id);
    for (const tabId of split.tabIds) {
      const tab = this.entries.get(tabId)?.tab;
      if (tab) tab.splitGroupId = undefined;
    }
  }

  // Dragging the gap between the two sides: `ratio` is the left side's
  // share of the width.
  resizeSplit(splitId: string, ratio: number) {
    const split = this.splits.get(splitId);
    if (!split || !Number.isFinite(ratio)) return;
    const left = Math.max(SPLIT_MIN, Math.min(1 - SPLIT_MIN, ratio));
    split.sizes = [left, 1 - left];
    this.layout();
    this.emitTabs();
  }

  // Clicking into one side makes it the current tab (the address bar and
  // buttons follow it), without anything moving.
  private focused(id: string) {
    if (id === this.activeId || !this.onScreen.includes(id)) return;
    this.activeId = id;
    this.lastInSpace.set(this.spaceId, id);
    this.entries.get(id)!.tab.lastActiveAt = Date.now();
    this.emitTabs();
    this.emitNav();
  }

  get splitGroups() {
    return [...this.splits.values()];
  }

  // Brings back saved split views whose tabs are all still here.
  restoreSplits(saved: SplitGroup[] = []) {
    for (const split of saved) {
      const tabs = split.tabIds.map((id) => this.entries.get(id)?.tab);
      if (
        split.tabIds.length !== 2 ||
        tabs.some(
          (tab) => !tab || groupOf(tab) !== EVERYDAY || tab.splitGroupId,
        )
      )
        continue;
      const left = Math.max(SPLIT_MIN, Math.min(1 - SPLIT_MIN, split.sizes[0]));
      this.splits.set(split.id, {
        ...split,
        spaceId: tabs[0]!.spaceId,
        layout: 'columns',
        sizes: [left, 1 - left],
      });
      for (const tab of tabs) tab!.splitGroupId = split.id;
      // Keep the two sides next to each other.
      const [first, second] = split.tabIds;
      this.order.splice(this.order.indexOf(second), 1);
      this.order.splice(this.order.indexOf(first) + 1, 0, second);
    }
    // A tab that says it's in a split view that didn't come back isn't.
    for (const { tab } of this.entries.values())
      if (tab.splitGroupId && !this.splits.has(tab.splitGroupId))
        tab.splitGroupId = undefined;
    this.renumber();
  }

  close(id: string) {
    const entry = this.entries.get(id);
    if (!entry) return;
    if (groupOf(entry.tab) !== EVERYDAY) {
      this.unloadPinned(entry);
      return;
    }
    // Closing one side of a split view leaves the other on its own.
    const partner = this.splitOf(id)?.tabIds.find((other) => other !== id);
    this.separate(id);
    const index = this.everyday.indexOf(id);
    this.order.splice(this.order.indexOf(id), 1);
    this.entries.delete(id);
    this.onScreen = this.onScreen.filter((other) => other !== id);
    if (entry.tab.url) this.recentlyClosed.push(entry.tab.url);
    this.recentlyClosed = this.recentlyClosed.slice(-20);

    entry.page.destroy();
    this.renumber();

    if (this.activeId !== id) {
      // The split's other side, still on screen, now fills the page.
      if (partner && this.onScreen.includes(partner)) this.layout();
      this.emitTabs();
      return;
    }
    // Move to the split's other side, else the tab that slid into its place
    // or the one above, else the most recent page still open.
    const everyday = this.everyday;
    const next =
      partner ??
      everyday[Math.min(index, everyday.length - 1)] ??
      this.recentIds().find((other) => this.entries.get(other)!.loaded);
    if (next) {
      this.activate(next);
      return;
    }
    this.activeId = null;
    this.emitTabs();
    this.emitNav();
    this.options.onEmpty();
  }

  // The active space's everyday tabs, in order.
  private get everyday() {
    return this.shown.filter(
      (id) => groupOf(this.entries.get(id)!.tab) === EVERYDAY,
    );
  }

  // Opens whatever was typed (an address or a search) in a new tab.
  openTyped(input: string) {
    const url = toNavigableUrl(input);
    return url ? this.create(url) : undefined;
  }

  // Moves a tab to a new position among the tabs of its own group that are
  // on screen (Basecamp, this space's pins, or its everyday tabs), for drag
  // to reorder. Tabs of other spaces keep their places.
  // A split view counts as one row and moves as one.
  move(id: string, toIndex: number) {
    const entry = this.entries.get(id);
    if (!entry) return;
    const groupId = groupOf(entry.tab);
    const group = this.shown.filter(
      (other) => groupOf(this.entries.get(other)!.tab) === groupId,
    );
    // The group's rows, as the sidebar shows them.
    const rows: string[][] = [];
    for (const tabId of group) {
      const splitId = this.entries.get(tabId)!.tab.splitGroupId;
      const last = rows.at(-1);
      if (
        splitId &&
        last &&
        this.entries.get(last[0])!.tab.splitGroupId === splitId
      )
        last.push(tabId);
      else rows.push([tabId]);
    }
    const from = rows.findIndex((row) => row.includes(id));
    const to = Math.max(0, Math.min(toIndex, rows.length - 1));
    if (from === to) return;
    const slots = group.map((other) => this.order.indexOf(other));
    const [row] = rows.splice(from, 1);
    rows.splice(to, 0, row);
    const flat = rows.flat();
    slots.forEach((slot, i) => (this.order[slot] = flat[i]));
    this.renumber();
    this.emitTabs();
  }

  // Drops a tab into the pinned tabs or the everyday tabs at `toIndex`
  // (dragging it across the divider pins or unpins it).
  place(id: string, pinned: boolean, toIndex: number) {
    const tab = this.entries.get(id)?.tab;
    if (!tab || tab.basecamp) return;
    if (tab.pinned !== pinned) {
      // Only single tabs can be pinned: a split view comes apart.
      if (pinned) this.unsplit(id);
      tab.pinned = pinned;
      tab.homeUrl = pinned ? tab.url : undefined;
      this.order.splice(this.order.indexOf(id), 1);
      this.order.splice(
        pinned ? this.groupEnd(PINNED) : this.groupStart(EVERYDAY),
        0,
        id,
      );
      this.renumber();
    }
    this.move(id, toIndex);
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
    this.active?.page.focus();
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
    entry.page.show();
    entry.page.load(url);
    entry.page.focus();
    this.emitTabs();
  }

  command(command: NavCommand) {
    const page = this.active?.page;
    if (!page) return;
    if (command === 'back') page.back();
    if (command === 'forward') page.forward();
    if (command === 'reload') page.reload();
    if (command === 'stop') page.stop();
  }

  hardReload() {
    this.active?.page.reload(true);
  }

  toggleDevTools() {
    this.active?.page.toggleDevTools();
  }

  // --- Layout ---------------------------------------------------------------

  layout() {
    const entry = this.active;
    if (!entry) return;
    const split = this.splitOf(entry.tab.id);
    if (this.fullscreen) {
      // A fullscreen video fills the window; a split's other side waits.
      const { width, height } = this.engine.windowSize();
      entry.page.place({ x: 0, y: 0, width, height }, 0);
      for (const id of this.onScreen)
        if (id !== entry.tab.id) this.entries.get(id)?.page.hide();
      entry.page.show();
      return;
    }
    const area = this.options.pageBounds();
    const ids = split ? split.tabIds : [entry.tab.id];
    const rects = split ? splitRects(area, split.sizes) : [area];
    ids.forEach((id, i) => {
      const page = this.entries.get(id)?.page;
      if (!page) return;
      page.place(rects[i], this.options.pageRadius);
      page.show();
    });
  }

  // Where the page would sit with its top edge at `top`.
  pageBoundsFor(top: number) {
    return this.options.pageBounds(top);
  }

  // Holds the layout of the pages on screen at a fixed size while their box
  // changes (null lets them fit their box again). `size` is the whole page
  // area's; each side of a split view gets its share. See glidePageTop in
  // src/main.ts.
  private heldPages: Page[] = [];

  holdLayout(size: { width: number; height: number } | null) {
    for (const page of this.heldPages) page.holdLayout(null);
    this.heldPages = [];
    const entry = this.active;
    if (!size || !entry || this.fullscreen) return;
    const split = this.splitOf(entry.tab.id);
    const area = { x: 0, y: 0, ...size };
    const ids = split ? split.tabIds : [entry.tab.id];
    const rects = split ? splitRects(area, split.sizes) : [area];
    ids.forEach((id, i) => {
      const page = this.entries.get(id)?.page;
      if (!page) return;
      page.holdLayout({ width: rects[i].width, height: rects[i].height });
      this.heldPages.push(page);
    });
  }

  destroy() {
    for (const { page } of this.entries.values()) page.destroy();
    this.entries.clear();
    this.order = [];
  }

  // --- Internals ------------------------------------------------------------

  private renumber() {
    this.order.forEach((id, i) => (this.entries.get(id)!.tab.order = i));
  }

  // Pages report many small changes at once while loading (title, icon,
  // address, loading...). They're gathered into one update for the UI.
  private tabsPending = false;

  private emitTabs() {
    if (this.tabsPending) return;
    this.tabsPending = true;
    setImmediate(() => {
      this.tabsPending = false;
      if (!this.engine.closed) this.options.onTabsChanged(this.state());
    });
  }

  private navPending = false;

  private emitNav() {
    if (this.navPending) return;
    this.navPending = true;
    setImmediate(() => {
      this.navPending = false;
      if (!this.engine.closed) this.options.onNavChanged(this.navState());
    });
  }

  // A fresh, empty page for a tab, kept in step with the tab's record.
  private makePage(id: string): Page {
    let page: Page | null = null;
    page = this.engine.createPage(this.eventsFor(id, () => page));
    return page;
  }

  // Keeps a tab's record in step with its page.
  private eventsFor(id: string, pageOf: () => Page | null): PageEvents {
    const entryOf = () => {
      const entry = this.entries.get(id);
      return entry && entry.page === pageOf() ? entry : undefined;
    };
    // The last page recorded in the history for this tab.
    let visited = { url: '', title: '' };
    return {
      onUpdate: () => {
        const entry = entryOf();
        if (!entry) return;
        const { url, title } = entry.page;
        if (url && (url !== visited.url || title !== visited.title)) {
          this.options.onVisit(
            url,
            title,
            entry.tab.favicon,
            url !== visited.url,
          );
          visited = { url, title };
        }
        if (url) entry.tab.url = url;
        entry.tab.title = title;
        this.emitTabs();
        if (id === this.activeId) this.emitNav();
      },
      onFavicon: (url) => {
        const entry = entryOf();
        if (!entry) return;
        entry.tab.favicon = url;
        if (visited.url) this.options.onVisit(visited.url, '', url, false);
        this.emitTabs();
      },
      // A new site gets a fresh favicon instead of keeping the old one.
      onNavigationStart: (url) => {
        const entry = entryOf();
        if (entry && safeHost(url) !== safeHost(entry.tab.url))
          entry.tab.favicon = '';
      },
      // Links that ask for a new tab open one right below this tab.
      onOpenTab: (url, background) =>
        void this.create(url, { after: id, activate: !background }),
      onLookout: (url) => this.options.onLookout(url),
      onFocus: () => {
        if (entryOf()) this.focused(id);
      },
      onFullscreen: (on) => this.setFullscreen(on),
    };
  }

  // Turns a page that's already open (one previewed in Lookout) into a new
  // tab at the top of the everyday tabs, keeping everything on it.
  adopt(page: Page, favicon = '') {
    const id = randomUUID();
    const tab: Tab = {
      id,
      spaceId: this.spaceId,
      url: page.url,
      title: page.title,
      favicon,
      pinned: false,
      order: 0,
      lastActiveAt: Date.now(),
    };
    page.listen(this.eventsFor(id, () => page));
    this.entries.set(id, { tab, page, loaded: true });
    this.order.splice(this.groupStart(EVERYDAY), 0, id);
    this.renumber();
    this.activate(id);
    return id;
  }

  // Remember whether the window was already fullscreen before the page asked,
  // so leaving video fullscreen puts things back exactly as they were.
  private wasWindowFullscreen = false;

  private setFullscreen(on: boolean) {
    this.fullscreen = on;
    if (on) {
      this.wasWindowFullscreen = this.engine.isWindowFullscreen();
      if (!this.wasWindowFullscreen) this.engine.setWindowFullscreen(true);
    } else if (!this.wasWindowFullscreen) {
      this.engine.setWindowFullscreen(false);
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
