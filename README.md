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

`npm start` runs Firn in development mode: if you change a file in `src/ui/`, the window updates by itself. For changes to `src/main.ts` or `src/preload.ts`, type `rs` in the terminal and press Enter to restart.

### Shortcuts (so far)

| Action | Windows / Linux | macOS |
| --- | --- | --- |
| Focus address bar | Ctrl+L | Cmd+L |
| Back / Forward | Alt+← / Alt+→ | Cmd+[ / Cmd+] |
| Reload | F5 or Ctrl+R | Cmd+R |
| Hard reload | Ctrl+Shift+R | Cmd+Shift+R |
| Developer tools for the page | F12 or Ctrl+Shift+I | Cmd+Option+I |

### Where things live

- `src/main.ts` — the main process: creates the window and the web page view, handles shortcuts.
- `src/preload.ts` — the narrow, safe bridge between Firn's UI and the main process.
- `src/ui/` — Firn's own interface (React): the toolbar and its styles.
- `src/url.ts` — decides whether what you typed is an address or a search.
