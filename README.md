# firn
A calm, minimalist desktop browser built on Electron and Chromium. Vertical tabs with room to breathe, pinned tabs, spaces, glance previews, and split view. Inspired by Arc and Zen, named after settled alpine snow. firnbrowser.com

## Running Firn on your computer

You need [Node.js](https://nodejs.org) (the LTS version) and Git installed once.

```
git clone https://github.com/dwurgy/firn.git
cd firn
npm install      # first time only, and whenever package.json changes
npm start        # opens Firn
```

**Windows: if PowerShell says "running scripts is disabled on this system"**, run this once and answer `Y`:

```
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

(Or use `npm.cmd install` / `npm.cmd start` instead.)

`npm start` runs Firn in development mode: if you change a file in `src/ui/`, the window updates by itself. For changes to `src/main.ts` or `src/preload.ts`, type `rs` in the terminal and press Enter to restart.

### Shortcuts (so far)

| Action | Windows / Linux | macOS |
| --- | --- | --- |
| Focus address bar | Ctrl+L | Cmd+L |
| Hide / show sidebar | Ctrl+S | Cmd+S |
| New tab (opens the command bar) | Ctrl+T | Cmd+T |
| Close tab (a pinned tab is unloaded instead) | Ctrl+W (or middle-click a tab) | Cmd+W |
| Pin / unpin tab | Ctrl+D | Cmd+D |
| Reopen closed tab | Ctrl+Shift+T | Cmd+Shift+T |
| Last-used tab (hold Ctrl and keep tapping Tab for the switcher) | Ctrl+Tab / Ctrl+Shift+Tab | Ctrl+Tab / Ctrl+Shift+Tab |
| Jump to tab 1–8 / last tab | Ctrl+1…8 / Ctrl+9 | Cmd+1…8 / Cmd+9 |
| Back / Forward | Alt+← / Alt+→ | Cmd+[ / Cmd+] |
| Reload | F5 or Ctrl+R | Cmd+R |
| Hard reload | Ctrl+Shift+R | Cmd+Shift+R |
| Developer tools for the page | F12 or Ctrl+Shift+I | Cmd+Option+I |

### Where things live

- `src/main.ts` — the main process: creates the window, handles shortcuts and messages from the UI.
- `src/tabs.ts` — the tab manager: the list of tabs and the web page behind each one.
- `src/types.ts` — the data model (spaces, tabs, window) shared by every part of the app.
- `src/preload.ts` — the narrow, safe bridge between Firn's UI and the main process.
- `src/ui/` — Firn's own interface (React): the window frame (`App.tsx`), the sidebar and tabs (`Sidebar.tsx`, `TabList.tsx`, `PinnedGrid.tsx`), the sidebar peeking over the page while collapsed (`Peek.tsx`), the command bar and tab switcher that float over the page (`Floating.tsx`), and the bar with the window buttons (`TopBar.tsx`).
- `src/url.ts` — decides whether what you typed is an address or a search.

### Your session

Firn saves your tabs (with their back/forward history and scroll position), the sidebar's width and collapsed state, and the window's size and position, and brings them back next time. Only the tab you were on loads right away; the others load when you click them. The file lives in `%APPDATA%\Firn\session.json` on Windows; deleting it starts Firn fresh.

### Pinned tabs

Pin a tab with **Ctrl+D** or by right-clicking it. Pins sit as tiles at the top of the sidebar and stay there for good. Each pin remembers the address it was pinned at as its *home*: right-click it for **Go back to home** or **Unpin tab**. Closing a pin doesn't remove it; it unloads the page and resets it to home, and the tile shows dimmed until you click it again.

### If something misbehaves

- **Ctrl+Shift+D** prints a snapshot of the window's layers, the cursor and the screen to the terminal.
- To log what the layers do as you use Firn, start it with debug logging. In PowerShell: `$env:FIRN_DEBUG=1; npm start` (close and reopen PowerShell to turn it off again).
