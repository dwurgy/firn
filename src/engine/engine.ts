// The browser engine, as the rest of Firn sees it: what a web page can do
// and what it tells us. Nothing here depends on Electron, so the tab model
// (src/tabs.ts) works the same on any engine. Today the only engine is
// Electron (src/engine/electron.ts); a Chromium fork would provide its own.

import type { SavedHistory } from '../types';

export interface PageBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

// What a page reports back as it loads and changes.
export interface PageEvents {
  // The address, title or loading state may have changed.
  onUpdate(): void;
  onFavicon(url: string): void;
  // The page started going to another document (not just a jump within the
  // same page).
  onNavigationStart(url: string): void;
  // A link asked to open in a new tab (`background`: without switching to
  // it). Real popup windows, such as sign-in flows, are handled by the
  // engine and never come here.
  onOpenTab(url: string, background: boolean): void;
  // A link was Shift+clicked: preview it in Glance.
  onGlance(url: string): void;
  // The page went into or out of fullscreen (e.g. a video).
  onFullscreen(on: boolean): void;
}

// One web page: the content of a tab.
export interface Page {
  readonly url: string;
  readonly title: string;
  readonly isLoading: boolean;
  readonly canGoBack: boolean;
  readonly canGoForward: boolean;

  load(url: string): void;
  // Brings back saved back/forward history (with scroll positions); fails
  // if the engine can't.
  restoreHistory(history: SavedHistory): Promise<void>;
  // The back/forward history to save, keeping at most `max` entries (the
  // most recent ones).
  history(max: number): SavedHistory;

  back(): void;
  forward(): void;
  reload(ignoreCache?: boolean): void;
  stop(): void;
  focus(): void;
  toggleDevTools(): void;

  // Where the page sits in the window, and how round its corners are.
  place(bounds: PageBounds, cornerRadius: number): void;
  // Lays the page out at a fixed size whatever its box (null: fit the box
  // again). While its box changes size for a moment, the site doesn't have
  // to re-fit on every step; whatever doesn't fit is simply hidden.
  holdLayout(size: { width: number; height: number } | null): void;
  show(): void;
  hide(): void;
  // Puts the page above everything else in the window (Glance floats over
  // Firn's own layers).
  raise(): void;
  // Sends the page's reports somewhere else from now on (a page previewed
  // in Glance becomes a tab).
  listen(events: PageEvents): void;
  // Closes the page for good.
  destroy(): void;
}

// What the engine offers the tab model.
export interface PageEngine {
  createPage(events: PageEvents): Page;
  // The window's inside size (a fullscreen video fills all of it).
  windowSize(): { width: number; height: number };
  isWindowFullscreen(): boolean;
  setWindowFullscreen(on: boolean): void;
  // True once the window is gone (late updates are then dropped).
  readonly closed: boolean;
}
