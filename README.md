# firn
A calm, minimalist desktop browser built on Electron and Chromium. Vertical tabs with room to breathe, Basecamp for your favorite sites, pinned tabs, spaces, Lookout link previews, and split view. Inspired by Arc and Zen, named after settled alpine snow. firnbrowser.com

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
| Close tab (a pinned or Basecamp tab is unloaded instead) | Ctrl+W (or middle-click a tab) | Cmd+W |
| Pin / unpin tab | Ctrl+D | Cmd+D |
| Preview a link in Lookout | Shift+click | Shift+click |
| Switch to space 1–9 | Ctrl+Shift+1…9 | Cmd+Shift+1…9 |
| Reopen closed tab | Ctrl+Shift+T | Cmd+Shift+T |
| Last-used tab (hold Ctrl and keep tapping Tab for the switcher) | Ctrl+Tab / Ctrl+Shift+Tab | Ctrl+Tab / Ctrl+Shift+Tab |
| Jump to tab 1–8 / last tab | Ctrl+1…8 / Ctrl+9 | Cmd+1…8 / Cmd+9 |
| Back / Forward | Alt+← / Alt+→ | Cmd+[ / Cmd+] |
| Reload | F5 or Ctrl+R | Cmd+R |
| Hard reload | Ctrl+Shift+R | Cmd+Shift+R |
| Developer tools for the page | F12 or Ctrl+Shift+I | Cmd+Option+I |

### Where things live

- `src/main.ts` — the main process: creates the window, handles shortcuts and messages from the UI.
- `src/tabs.ts` — the tab manager: tabs, spaces, Basecamp, pins and their order. It doesn't depend on Electron.
- `src/engine/` — the browser engine: `engine.ts` describes what a web page can do, and `electron.ts` is Electron's version of it (the one place web pages are created).
- `src/types.ts` — the data model (spaces, tabs, window) shared by every part of the app.
- `src/preload.ts` — the narrow, safe bridge between Firn's UI and the main process.
- `src/ui/` — Firn's own interface (React): the window frame (`App.tsx`), the sidebar and tabs (`Sidebar.tsx`, `TabList.tsx`, `Basecamp.tsx`, `Spaces.tsx`), the sidebar peeking over the page while collapsed (`Peek.tsx`), the command bar and tab switcher that float over the page (`Floating.tsx`), and the bar with the window buttons (`TopBar.tsx`).
- `src/url.ts` — decides whether what you typed is an address or a search.

### Your session

Firn saves your tabs (with their back/forward history and scroll position), the sidebar's width and collapsed state, and the window's size and position, and brings them back next time. Only the tab you were on loads right away; the others load when you click them. The file lives in `%APPDATA%\Firn\session.json` on Windows; deleting it starts Firn fresh.

### Basecamp and pinned tabs

**Basecamp** is the grid of favorite sites at the top of the sidebar: the same in every space, up to 12. Right-click any tab and choose **Add to Basecamp**. The site you're on glows softly in its own color.

**Pinned tabs** belong to one space and sit as rows under its name. Pin a tab with **Ctrl+D**, by right-clicking it, or by dragging it above the divider line (drag it back below to unpin). Click the space's name to fold its pins away (the pin you're on stays in view).

Both remember the address they were added at as their *home*: right-click for **Go back to home**. Closing one doesn't remove it; it unloads the page and resets it to home, and it rests a little dimmed until you click it again. The line below the pins has **Clear**, which closes the space's everyday tabs.

### Spaces

Spaces keep separate sets of pinned and everyday tabs, like Work and Personal. Switch with the icons at the bottom of the sidebar or **Ctrl+Shift+1…9**; **+** makes a new space and lets you name it right away. Each space has its own color, which softly tints the frame and glass (switching spaces cross-fades between them). Right-click a space's icon (or use the ⋯ next to its name) to rename it, change its icon or color, or delete it. Right-clicking any empty spot in the sidebar offers the same color, icon and name options for the space you're in. Right-click a tab to move it to another space. Each space remembers the tab you were last on, and everything is saved with your session.

### Lookout

**Shift+click** a link to preview it in Lookout: a rounded panel floating over the page, with the page dimmed behind it. Press **Esc** or click outside to close it, or use the button beside it to **open it as a tab** (the panel grows into the page and keeps everything, scroll position included). Links that open real popup windows, like "Sign in with Google", still open as windows.

### Split view

Right-click the tab you're on and choose **Split view with** to pick another tab to show beside it (or **New tab…** to open something new beside it), or right-click any other tab and choose **Split view with current tab**. The two sit side by side, each with its own address and back/forward. Click into a side to work in it (the address bar follows, and a soft ring shows which side it is). Drag the gap between them to resize, or double-click it to even them out. In the sidebar the pair is one row: click either half, or drag the row to move both. Hover it and use the button on the right (or right-click → **Separate split view**) to make them ordinary tabs again; closing one side leaves the other on its own. Split views are saved with your session.

### Frosted glass

On Windows 11 (22H2 or later) and macOS, the frame around the page is frosted glass while Firn is in focus: the colors behind the window softly show through. When you switch to another app it turns solid. To turn it off, start Firn with `FIRN_NO_GLASS=1` (in PowerShell: `$env:FIRN_NO_GLASS=1; npm start`).

### If something misbehaves

- **Ctrl+Shift+D** prints a snapshot of the window's layers, the cursor and the screen to the terminal.
- If the window ever shows black or flickers behind the sidebar, try turning frosted glass off (above) and tell Claude.
- To log what the layers do as you use Firn, start it with debug logging. In PowerShell: `$env:FIRN_DEBUG=1; npm start` (close and reopen PowerShell to turn it off again).
