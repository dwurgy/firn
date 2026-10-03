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

### The fast version, for everyday browsing

Development mode is slower than the real thing: Firn's own panels are served piece by piece, and React runs its extra-checking version. For everyday use, build the packaged app:

```
npm run package
```

Then open `out\Firn-win32-x64\Firn.exe` (on macOS, `out/Firn-darwin-*/Firn.app`). It starts several times faster and animates more smoothly. It keeps the same tabs, spaces and history as `npm start`, but only one Firn can run at a time, so close the other first. After pulling new changes, run `npm run package` again.

### Shortcuts (so far)

| Action | Windows / Linux | macOS |
| --- | --- | --- |
| Focus address bar | Ctrl+L | Cmd+L |
| Hide / show sidebar | Ctrl+S | Cmd+S |
| Command bar (new tab, find tabs and history, actions) | Ctrl+T | Cmd+T |
| Close tab (a pinned or Basecamp tab is unloaded instead) | Ctrl+W (or middle-click a tab) | Cmd+W |
| Pin / unpin tab | Ctrl+D | Cmd+D |
| Preview a link in Lookout | Shift+click | Shift+click |
| Find in page (Enter / Shift+Enter: next / previous, Esc: close) | Ctrl+F (then F3 or Ctrl+G for next) | Cmd+F (then Cmd+G) |
| Zoom in / out / back to 100% (each site remembers its zoom) | Ctrl+= / Ctrl+- / Ctrl+0, or Ctrl+mouse wheel | Cmd+= / Cmd+- / Cmd+0 |
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
- `src/ui/` — Firn's own interface (React): the window frame (`App.tsx`), the sidebar and tabs (`Sidebar.tsx`, `TabList.tsx`, `Basecamp.tsx`, `Spaces.tsx`), the sidebar peeking over the page while collapsed (`Peek.tsx`), the command bar, tab switcher and find bar that float over the page (`Floating.tsx`), and the bar with the window buttons (`TopBar.tsx`).
- `brand/` — Firn's logo, wordmark and app icons (see `brand/README.md`); `assets/` holds the app icon Firn itself uses.
- `src/url.ts` — decides whether what you typed is an address or a search.

### Command bar

**Ctrl+T** opens the command bar. Type an address or a search; it also finds your open tabs in every space (tabs in another space say which, and picking one takes you there) and pages from your history. Type a couple of letters of an action to run it: **pin**, **basecamp**, **copy** link, **close**, **reopen**, **clear**, **sidebar**, **new space**, or a space's name to go there.

### Your session

Firn saves your tabs (with their back/forward history and scroll position), the sidebar's width and collapsed state, and the window's size and position, and brings them back next time. Only the tab you were on loads right away; the others load when you click them. The file lives in `%APPDATA%\Firn\session.json` on Windows; deleting it starts Firn fresh. Your browsing history (for the command bar) is kept next to it in `history.json`, on your computer only.

### Basecamp and pinned tabs

**Basecamp** is the grid of favorite sites at the top of the sidebar: the same in every space, up to 12. Right-click any tab and choose **Add to Basecamp**. The site you're on glows softly in its own color.

**Pinned tabs** belong to one space and sit as rows under its name. Pin a tab with **Ctrl+D**, by right-clicking it, or by dragging it above the divider line (drag it back below to unpin). Click the space's name to fold its pins away (the pin you're on stays in view).

Both remember the address they were added at as their *home*: right-click for **Go back to home**. Closing one doesn't remove it; it unloads the page and resets it to home, and it rests a little dimmed until you click it again. The line below the pins has **Clear**, which closes the space's everyday tabs.

### Spaces

Spaces keep separate sets of pinned and everyday tabs, like Work and Personal. Switch with the icons at the bottom of the sidebar or **Ctrl+Shift+1…9**; **+** makes a new space and lets you name it right away. Each space has its own color, which softly tints the frame and glass (switching spaces cross-fades between them), and its own icon: one of 16 simple line icons drawn for Firn, shown in the space's color so it never looks like a website's icon. "Change icon…" opens a small grid of them under the space's name. Right-click a space's icon (or use the ⋯ next to its name) to rename it, change its icon or color, or delete it. Right-clicking any empty spot in the sidebar offers the same color, icon and name options for the space you're in. Right-click a tab to move it to another space. Each space remembers the tab you were last on, and everything is saved with your session.

### Right-click menu

Right-clicking a page shows a short menu with only what fits what you clicked:

- **A link:** open it in a new tab (in the background), open it in Lookout, or copy it. Email links offer "Copy email address".
- **An image:** save it or copy it.
- **Selected text:** copy it, or search for it.
- **A text box:** cut, copy, paste, select all, plus spelling suggestions for a misspelled word.
- **Anywhere else:** back, forward, reload.

### Lookout

**Shift+click** a link to preview it in Lookout: a rounded panel floating over the page, with the page dimmed behind it. Press **Esc** or click outside to close it, or use the button beside it to **open it as a tab** (the panel grows into the page and keeps everything, scroll position included). Links that open real popup windows, like "Sign in with Google", still open as windows.

Lookout also opens by itself in one case: in a **Basecamp or pinned tab**, a link that would open a new tab and goes to **another site** (say, a link in an email) opens in Lookout instead. Your pinned tab stays where it was and no stray tabs pile up; if you want to keep the page, use "open as tab". Middle-click or Ctrl+click such a link to open it as a background tab instead. Everyday tabs open links as usual.

### Split view

Right-click the tab you're on and choose **Split view with** to pick another tab to show beside it (or **New tab…** to open something new beside it), or right-click any other tab and choose **Split view with current tab**. The two sit side by side, each with its own address and back/forward. Click into a side to work in it (the address bar follows, and a soft ring shows which side it is). Drag the gap between them to resize, or double-click it to even them out. In the sidebar the pair is one row: click either half, or drag the row to move both. Hover it and use the button on the right (or right-click → **Separate split view**) to make them ordinary tabs again; closing one side leaves the other on its own. Split views are saved with your session.

### Frosted glass

On Windows 11 (22H2 or later) and macOS, the frame around the page is frosted glass while Firn is in focus: the colors behind the window softly show through. When you switch to another app it turns solid. To turn it off, start Firn with `FIRN_NO_GLASS=1` (in PowerShell: `$env:FIRN_NO_GLASS=1; npm start`).

### If something misbehaves

- **Ctrl+Shift+D** prints a snapshot of the window's layers, the cursor and the screen to the terminal.
- If the window ever shows black or flickers behind the sidebar, try turning frosted glass off (above) and tell Claude.
- To log what the layers do as you use Firn, start it with debug logging. In PowerShell: `$env:FIRN_DEBUG=1; npm start` (close and reopen PowerShell to turn it off again).
