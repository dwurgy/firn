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
}

export interface Tab {
  id: string;
  spaceId: string;
  url: string;
  title: string;
  favicon: string;
  pinned: boolean;
  homeUrl?: string;
  order: number;
  lastActiveAt: number;
  splitGroupId?: string;
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
  window: SavedWindow;
  recentlyClosed: string[];
}

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
  // False for a tab whose page hasn't loaded yet (restored, or an unloaded
  // pinned tab).
  loaded: boolean;
}

export interface TabsState {
  tabs: TabView[]; // in sidebar order, top to bottom
  activeTabId: string | null;
}

// Navigation status of the active tab, for the back/forward/reload buttons.
export interface NavState {
  url: string;
  title: string;
  canGoBack: boolean;
  canGoForward: boolean;
  isLoading: boolean;
}

// The sidebar's size and whether it's tucked away. `pageLeft` is where the
// page currently starts (it glides while collapsing or expanding).
export interface SidebarState {
  width: number;
  collapsed: boolean;
  pageLeft: number;
  peeking: boolean;
}

export type NavCommand = 'back' | 'forward' | 'reload' | 'stop';

export type WindowCommand = 'minimize' | 'toggle-maximize' | 'close';

// What the floating layer above the page is showing.
export type OverlayState =
  | { mode: 'hidden' }
  // `openId` changes each time it opens, so it always starts fresh.
  | { mode: 'command'; openId: number }
  // Ctrl+Tab: tabs by most recent use, and which one is picked.
  // `revealed` turns false-to-true once Ctrl has been held a moment.
  | { mode: 'switcher'; tabIds: string[]; index: number; revealed: boolean };

// The narrow API the preload script exposes to Firn's UI as `window.firn`.
export interface FirnBridge {
  platform: string;
  navigate(input: string): void;
  command(command: NavCommand): void;
  newTab(): void;
  openUrl(input: string): void;
  closeOverlay(): void;
  toggleSidebar(): void;
  setSidebarWidth(width: number): void;
  closeTab(id: string): void;
  activateTab(id: string): void;
  moveTab(id: string, toIndex: number): void;
  showTabMenu(id: string): void;
  // A favicon as a data: URL, so the UI can read its colors.
  iconData(url: string): Promise<string | null>;
  windowCommand(command: WindowCommand): void;
  ready(): void;
  onNavState(listener: (state: NavState) => void): () => void;
  onTabsState(listener: (state: TabsState) => void): () => void;
  onFocusAddress(listener: (url: string) => void): () => void;
  onMaximizedChange(listener: (maximized: boolean) => void): () => void;
  onOverlayState(listener: (state: OverlayState) => void): () => void;
  onTopBarState(listener: (shown: boolean) => void): () => void;
  onSidebarState(listener: (state: SidebarState) => void): () => void;
}
