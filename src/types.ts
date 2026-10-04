// Shapes shared between the main process, the preload bridge and the UI.

// --- Core data model (see CLAUDE.md) ----------------------------------------
// These are the records that will be saved to disk (Phase 3) and could later
// sync between devices, so they hold plain data only.

export interface Space {
  id: string;
  name: string;
  icon: string;
  color: string;
  order: number;
  // The space's pinned tabs are folded away under its name.
  pinsFolded?: boolean;
}

export interface Tab {
  id: string;
  spaceId: string;
  url: string;
  title: string;
  favicon: string;
  pinned: boolean;
  // In Basecamp: the grid of favorite sites shown in every space (then
  // `spaceId` is just the space it was added from).
  basecamp?: boolean;
  homeUrl?: string;
  order: number;
  lastActiveAt: number;
  splitGroupId?: string;
}

// Two tabs shown side by side (split view). `sizes` are each side's share
// of the width; the sidebar shows the pair as one row.
export interface SplitGroup {
  id: string;
  spaceId: string;
  tabIds: string[];
  layout: 'columns';
  sizes: number[];
}

export interface WindowState {
  id: string;
  activeSpaceId: string;
  activeTabId: string | null;
  sidebarWidth: number;
  sidebarCollapsed: boolean;
}

// --- The saved session (src/store.ts) ---------------------------------------

// A tab's back/forward history, including each page's scroll position and
// form contents (Chromium's "page state"), so a restored tab picks up
// exactly where it was.
export interface SavedHistory {
  entries: { url: string; title: string; pageState?: string }[];
  index: number;
}

export interface SavedTab extends Tab {
  history?: SavedHistory;
}

export interface SavedWindow extends WindowState {
  bounds?: { x: number; y: number; width: number; height: number };
  maximized?: boolean;
}

export interface SavedSession {
  version: number;
  spaces: Space[];
  tabs: SavedTab[];
  splits?: SplitGroup[];
  window: SavedWindow;
  recentlyClosed: string[];
  // Zoom remembered per site (host → zoom factor; 1 = 100% isn't stored).
  siteZoom?: Record<string, number>;
}

// Firn's settings (src/settings.ts). `downloadsFolder` '' means the
// system's Downloads folder.
export interface Settings {
  searchEngine: 'duckduckgo' | 'google' | 'bing' | 'ecosia' | 'startpage';
  theme: 'system' | 'light' | 'dark';
  downloadsFolder: string;
  // Where the address bar sits: in the sidebar (the default) or in a top
  // bar that's always there. See "Opinionated: two looks" in CLAUDE.md.
  addressBar: 'sidebar' | 'top';
}

// What the settings panel shows: the settings, plus the downloads folder
// actually used and Firn's version.
export interface SettingsState {
  settings: Settings;
  downloadsFolder: string;
  version: string;
}

// A downloaded file (src/downloads.ts). `missing`: it finished, but the
// file has since been moved or deleted.
export interface Download {
  id: string;
  url: string;
  name: string;
  path: string;
  state: 'progress' | 'done' | 'failed' | 'cancelled';
  received: number;
  total: number;
  startedAt: number;
  endedAt?: number;
  missing?: boolean;
}

// A page in the browsing history (src/history.ts).
export interface HistoryEntry {
  url: string;
  title: string;
  favicon: string;
  visits: number;
  lastVisit: number;
}

// Quick actions the command bar can run (see runAction in src/main.ts).
export type CommandAction =
  | 'pin'
  | 'basecamp'
  | 'close'
  | 'reopen'
  | 'separate'
  | 'sidebar'
  | 'new-space'
  | 'clear'
  | 'copy-link'
  | 'switch-space'
  | 'find'
  | 'zoom-in'
  | 'zoom-out'
  | 'zoom-reset'
  | 'downloads'
  | 'history'
  | 'settings';

// --- What the UI is told ----------------------------------------------------

// A tab as the sidebar shows it: the saved record plus live status.
export interface TabView {
  id: string;
  url: string;
  title: string;
  favicon: string;
  isLoading: boolean;
  lastActiveAt: number;
  pinned: boolean;
  basecamp: boolean;
  // False for a tab whose page hasn't loaded yet (restored, or an unloaded
  // pinned tab).
  loaded: boolean;
  // Set when the tab is one side of a split view.
  splitId?: string;
}

export interface TabsState {
  tabs: TabView[]; // in sidebar order, top to bottom
  activeTabId: string | null;
  // Split views among these tabs (both sides are always next to each other
  // in `tabs`).
  splits: SplitGroup[];
}

// The spaces, in order, and which one is shown.
export interface SpacesState {
  spaces: Space[];
  activeSpaceId: string;
}

// Navigation status of the active tab, for the back/forward/reload buttons.
export interface NavState {
  url: string;
  title: string;
  canGoBack: boolean;
  canGoForward: boolean;
  isLoading: boolean;
  // The page's zoom (1 = 100%).
  zoom: number;
  // The site has camera, location... answers saved (shows a button in the
  // address bar to change them).
  sitePermissions: boolean;
}

// The sidebar's size and whether it's tucked away. `pageLeft` is where the
// page currently starts (it glides while collapsing or expanding).
export interface SidebarState {
  width: number;
  collapsed: boolean;
  pageLeft: number;
  peeking: boolean;
}

// Whether the window shows frosted glass, and whether it's in focus (glass
// turns solid out of focus).
export interface FrameState {
  glass: boolean;
  focused: boolean;
  // Firn's own panels are dark (following the system, or settings).
  dark: boolean;
}

export type NavCommand = 'back' | 'forward' | 'reload' | 'stop';

export type WindowCommand = 'minimize' | 'toggle-maximize' | 'close';

// What the floating layer above the page is showing.
export type OverlayState =
  | { mode: 'hidden' }
  // `openId` changes each time it opens, so it always starts fresh.
  // `beside`: what's picked opens in split view beside this tab (its
  // title).
  | { mode: 'command'; openId: number; beside?: string }
  // A site asking to use something: `site` (e.g. "meet.google.com") wants
  // to `ask` (e.g. "use your camera and microphone"); `kind` picks the icon.
  | {
      mode: 'permission';
      openId: number;
      site: string;
      ask: string;
      kind: string;
    }
  // The history panel (Ctrl+H) and the settings panel (Ctrl+,).
  | { mode: 'history'; openId: number }
  | { mode: 'settings'; openId: number }
  // Find in page (Ctrl+F): `text` is the last search, to start from.
  | { mode: 'find'; openId: number; text: string }
  // Ctrl+Tab: tabs by most recent use, and which one is picked.
  // `revealed` turns false-to-true once Ctrl has been held a moment.
  | { mode: 'switcher'; tabIds: string[]; index: number; revealed: boolean }
  // Lookout: a link previewed in a panel over the page. `area` is the page's
  // box and `panel` the preview's, both in window coordinates.
  | {
      mode: 'lookout';
      openId: number;
      phase: 'open' | 'closing' | 'expanding';
      area: Rect;
      panel: Rect;
    };

// How a find in page went: the match that's highlighted (1-based; 0 when
// there's none) and how many there are.
export interface FindResult {
  active: number;
  total: number;
}

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

// The narrow API the preload script exposes to Firn's UI as `window.firn`.
export interface FirnBridge {
  platform: string;
  navigate(input: string): void;
  command(command: NavCommand): void;
  newTab(): void;
  openUrl(input: string): void;
  closeOverlay(): void;
  // The command bar: every open tab (all spaces), history matches, and its
  // quick actions (`arg` is a space id for 'switch-space').
  allTabs(): Promise<(TabView & { spaceId: string })[]>;
  searchHistory(query: string): Promise<HistoryEntry[]>;
  // The history panel: pages visited (newest first), forgetting one, and
  // the "Clear history" menu (last hour, today, all time).
  listHistory(query: string): Promise<HistoryEntry[]>;
  removeHistory(url: string): void;
  showClearHistoryMenu(): void;
  onHistoryChanged(listener: () => void): () => void;
  // Settings: change some, pick the downloads folder, clear cookies and
  // site data (asks first), forget every site's permission answers.
  updateSettings(changes: Partial<Settings>): void;
  chooseDownloadsFolder(): void;
  clearSiteData(): void;
  resetAllPermissions(): void;
  onSettingsState(listener: (state: SettingsState) => void): () => void;
  // The sidebar's ⋯ menu (new tab, history, downloads, settings).
  showFirnMenu(): void;
  runAction(action: CommandAction, arg?: string): void;
  // Lookout's "Open as tab".
  expandLookout(): void;
  // Find in page: search for `text` (`newSearch` when it changed; otherwise
  // the next or, with `forward` false, the previous match), or close it.
  find(text: string, forward: boolean, newSearch: boolean): void;
  closeFind(): void;
  // Zoom the page in (1), out (-1) or back to 100% (0).
  zoom(step: 1 | -1 | 0): void;
  // Downloads (by id): open the file, show it in its folder, stop it, take
  // it off the list, or try again.
  // The answer to a site's permission prompt ('dismiss': closed without
  // answering, so it asks again next time).
  answerPermission(answer: 'allow' | 'block' | 'dismiss'): void;
  // The address bar's site button: what the current site may use.
  showSitePermissions(): void;
  openDownload(id: string): void;
  showDownload(id: string): void;
  cancelDownload(id: string): void;
  removeDownload(id: string): void;
  retryDownload(id: string): void;
  // Split view: drag the gap (`ratio` is the left side's share), or end it.
  resizeSplit(id: string, ratio: number): void;
  separateSplit(tabId: string): void;
  toggleSidebar(): void;
  // The peeking sidebar has a text field focused (so it stays open).
  setPeekTyping(typing: boolean): void;
  setSidebarWidth(width: number): void;
  closeTab(id: string): void;
  activateTab(id: string): void;
  // Moves a tab within its group, or (with `pinned`) into the pinned or
  // everyday tabs at that spot.
  moveTab(id: string, toIndex: number, pinned?: boolean): void;
  showTabMenu(id: string): void;
  switchSpace(id: string): void;
  newSpace(): void;
  updateSpace(
    id: string,
    changes: {
      name?: string;
      icon?: string;
      color?: string;
      pinsFolded?: boolean;
    },
  ): void;
  // Closes the active space's everyday (unpinned) tabs.
  clearTabs(): void;
  showSpaceMenu(id: string): void;
  // Right-click on empty space in the sidebar.
  showSidebarMenu(): void;
  // A favicon as a data: URL, so the UI can read its colors.
  iconData(url: string): Promise<string | null>;
  windowCommand(command: WindowCommand): void;
  ready(): void;
  onNavState(listener: (state: NavState) => void): () => void;
  onTabsState(listener: (state: TabsState) => void): () => void;
  onFocusAddress(listener: (url: string) => void): () => void;
  onMaximizedChange(listener: (maximized: boolean) => void): () => void;
  onOverlayState(listener: (state: OverlayState) => void): () => void;
  onFindResult(listener: (result: FindResult) => void): () => void;
  onDownloadsState(listener: (downloads: Download[]) => void): () => void;
  onTopBarState(listener: (shown: boolean) => void): () => void;
  onSidebarState(listener: (state: SidebarState) => void): () => void;
  onFrameState(listener: (state: FrameState) => void): () => void;
  onSpacesState(listener: (state: SpacesState) => void): () => void;
  // The main process asks the sidebar to start renaming a space.
  onRenameSpace(listener: (id: string) => void): () => void;
  // ...or to show the icon picker for a space.
  onPickSpaceIcon(listener: (id: string) => void): () => void;
}
