# History

Details and reasoning that don't belong in CLAUDE.md.

## Phase 1: a window that browses (2026-10-17)

- **Project shape.** `Firn.xcodeproj` is a thin app target using Xcode's folder-synced groups (files added to `Firn/` show up without editing the project file). Logic lives in the local package `FirnCore`. No XcodeGen.
- **Engine layer.** Views use `PageController` and `PageView`; only `WebKitPageController` and `PageView` touch WebKit. `BrowserEngine.makePage(dataStoreID:)` is the one place that picks the engine.
- **Data store.** Phase 1 uses one fixed, named `WKWebsiteDataStore(forIdentifier:)` (never `.default()`), so per-space stores in Phase 4 change the id, not the habit.
- **Honest address bar.** The bar shows the committed URL. WKWebView's `url` can change before a navigation commits, so cross-origin changes are only taken in `didCommit`; same-origin changes (pushState, #links) are taken from KVO.
- **Addresses.** Only http and https open. `javascript:`, `file:`, `mailto:`, other apps' schemes, and top-level `data:` are refused, both when typed and when a page navigates. Links meant for a new window open in the same page for now.
- **Search.** Google by default; Bing, DuckDuckGo, Ecosia, and Yahoo exist in code for the welcome and Settings later.
- **User agent.** Adds a Safari-style `Version/… Safari/…` suffix; without it some sites (Google sign-in among them) treat WKWebView as an embedded app view.
- **Signing.** "Sign to Run Locally" (ad-hoc). Xcode skips the hardened runtime for ad-hoc builds, so it's forced with `--options=runtime`; that in turn needs `ENABLE_DEBUG_DYLIB = NO` in Debug (ad-hoc signatures have no team, and library validation refused the separate debug dylib). Side effect: no SwiftUI Previews canvas. Once a development team is set, this can be revisited.
- **Tests from Xcode.** Adding the package's tests to the Firn scheme didn't work (Xcode found no test bundles), so `xcodebuild test` runs from inside `FirnCore`.

## Phase 2: sidebar and vertical tabs (in progress)

- **Tab model (2a).** `BrowserStore` in FirnCore is the one place tabs and spaces change. Each `Tab` makes its page the first time it's shown, through a factory, so tests use a fake page. Closing the tab on screen shows the one below (or above, if it was last).
- **Sidebar (2b).** Custom layout, not `NavigationSplitView` (it can't collapse to 0 or peek). ⌘T focuses the address bar for a new tab; the tab only appears on Return. At rest the address bar shows just the site (IDN hosts stay in their `xn--` form); clicking in shows the whole address. Shortcuts follow Arc and Dia: ⌘W closes the tab, ⇧⌘W the window (replacing the system "Close" item), ⌘1–9, ⌃Tab, and ⇧⌘[ / ⇧⌘].
- **Traffic lights: let macOS place them.** A window without a toolbar gets the old compact spot (about 16pt from the corner); every app with a toolbar, even an invisible one, gets the roomier spot. Moving the buttons by hand didn't hold: macOS lays the title bar out again on title changes and undid it. Firn gives the window an empty `NSToolbar` (like Electron's `hiddenInset`) and lines the sidebar's top row up with where the lights land, measured, not guessed.
