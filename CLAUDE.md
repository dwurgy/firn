# Project Brief — Firn

**Firn** (firnbrowser.com) is a calm, minimalist desktop browser. The name comes from firn, the settled, compacted snow high on alpine glaciers — quiet, clean, and still. Let that idea quietly inform the visual identity (soft whites, frost, gentle glacier tones alongside warm neutrals) without getting literal or icy-cold.

It is a calm, minimalist desktop browser in the spirit of Arc and Zen: sidebar-first, vertical tabs, pinned tabs, spaces, lookout, and split view. Built on Electron (real Chromium rendering). Built by David with Claude — David is not a professional developer, so explain decisions in plain language and keep changes small and testable.

Personal use first. Testers later. No rush — quality and feel over speed.

---

## North star

**It should feel calm.** Every screen should breathe. If something feels crammed, busy, or "techy," it's wrong — even if it works.

Inspired by Arc and Zen's *experience*, but all visuals, icons, and names are our own. Never copy their logos, assets, or branding.

## Vision: Zen and Arc for everyone

Zen and Arc are beautiful, but they're built for power users. Firn brings their best ideas to normal people (friends and family, not just enthusiasts), in a calm, beautiful package, on Chrome's engine, without the power-user bloat.

**Four words: Privacy, Simplicity, Calm, Beauty.**

- **Spaces are the big idea.** They're powerful and still easy for anyone to understand. Firn doesn't need Profiles, Containers *and* Spaces; Spaces alone should cover it.
- **Have the guts to say no.** Before adding a feature, ask: would a non-techy person understand it and miss it if it were gone? If it mainly serves power users, leave it out, or tuck it away so it never adds clutter.
- **Short menus.** No giant right-click menus (Zen's tab menu is the anti-example). A menu shows the few things you'd actually reach for, in plain words.
- **Discoverable, not memorized.** Anything important can be found by looking or right-clicking; keyboard shortcuts are a bonus, never the only way.
- **Privacy by default.** Data stays on the device unless the person chooses otherwise. No tracking, no telemetry, and privacy claims are only made when they're true.
- **Names: plain words win.** Keep a familiar word when it's already plain English (Spaces, Pins). Give something our own name when the other browsers' word is their brand coinage or unclear (Basecamp instead of Essentials, Lookout instead of Glance).
- **Opinionated: two looks, never more.** Firn picks the layout for people, the way mainstream browsers did for decades: vertical tabs in the sidebar, the page as the star. The one choice is where the address bar sits ("In the sidebar" or "At the top"), offered on every platform, at onboarding and in settings. That's the last layout choice Firn ever gets: no top-bar tabs, no icon-only sidebar. Wanting more room is answered by hiding the sidebar (Ctrl+S, peeks at the left edge), not by more layouts.
  - *In the sidebar* (default): the current design. Reaching the top edge slides down a slim top bar on every platform, for dragging and double-clicking the window; Windows/Linux show minimize/maximize/close in it, macOS just grabs (its traffic lights stay in the sidebar).
  - *At the top*: the top bar is always there (window buttons always visible), with the **same address bar** (same component, height, look and width as in the sidebar) centered over the page area; the sidebar keeps tabs, Basecamp and spaces. On macOS the traffic lights sit at the left of the bar and its right side stays empty.
- **Calm over clever.** When a choice is between more options and less to think about, pick less to think about.

We're not removing features now; this is the lens for everything from here on.

---

## Design principles

1. **Space is a feature.** Generous padding, comfortable row heights, nothing touching the edges. When in doubt, add room.
2. **Minimal chrome.** The web page is the star. Browser UI recedes until needed.
3. **Warm and organic, not techy.** Soft neutrals, warm tones, gentle contrast. No neon accents, no harsh pure black/white.
4. **Soft translucency.** Sidebar and overlays use subtle frosted-glass blur (Liquid Glass–like), tinted by the current space's color.
5. **Quiet motion.** Short, eased animations (150–250ms). Things glide, never snap or bounce.
6. **One accent at a time.** Each space has one theme color; everything else stays neutral.

### Starter design tokens (tune freely)

```
Sidebar width:        260px default (resizable 200–360), collapsible to 0
Tab row height:       36px
Tab row padding:      8px 12px
Gap between tabs:     4px
Section spacing:      20px
Corner radius:        10px (tabs), 14px (panels/overlays)
Window content inset: 8px around the web view, radius 12px (page floats in the frame)
Font:                 system UI font, 13px tabs, 12px labels; brand moments
                      (big headings only: the welcome, panel titles, the
                      empty page, the scam warning) use Fraunces, soft
Motion:               200ms, ease-out
Neutrals:             warm grays (slight brown/sand undertone), not blue-gray
Light & dark:         both, following the OS setting
```

---

## Features

### Vertical tabs (sidebar)
- Tabs live in a left sidebar, top to bottom.
- Favicon + title, close button appears only on hover.
- Drag to reorder. Smooth animation as rows shift.
- Sidebar can collapse fully and reappear on hover at the left edge.

### Pinned tabs
- Pinned area at the top of the sidebar, shown as a compact grid of favicon tiles.
- Pinned tabs persist forever (across restarts), per space.
- A pinned tab remembers its "home" URL; a reset action returns it there.

### Today tabs (unpinned)
- Below pinned tabs, divided by a soft separator.
- Optional later: auto-archive unpinned tabs after X hours of inactivity (like Arc).

### Spaces
- Groups of pinned + unpinned tabs, each with a name, icon (Firn's own simple line icons, drawn in the space's color — not emoji, which look like site favicons), and theme color.
- Switch with a row of dots/icons at the bottom of the sidebar, or with a keyboard shortcut / horizontal swipe.
- Switching spaces gently cross-fades the sidebar tint.

### Lookout (link preview)
- Configurable trigger (e.g. modifier+click or click on links that leave the site).
- Opens the link in a floating rounded overlay over the current page, with a dimmed backdrop.
- Close with Esc or clicking outside. One button promotes it to a full tab.
- Opens with a subtle scale + fade.

### Split view
- Two (later up to four) tabs side by side, with a draggable divider.
- Each pane keeps its own address and navigation.
- Split groups show as one combined item in the sidebar.

### Command bar
- One shortcut (Ctrl/Cmd+T or Ctrl/Cmd+L) opens a centered floating bar: type a URL, search, or jump to an open tab.

### Essentials (unglamorous but required)
- Session restore on restart.
- Keyboard shortcuts for everything.
- History, downloads, basic settings page.
- Find in page, zoom, dev tools.

---

## Architecture

- **Electron + TypeScript.** UI built with React + Vite (via Electron Forge's Vite template) unless there's a strong reason otherwise.
- **Web pages** render in `WebContentsView`s managed by the main process (not the deprecated `BrowserView`, and avoid the `<webview>` tag). The sidebar and overlays are the app's own UI layer.
- **Security defaults, always:** `contextIsolation: true`, `sandbox: true`, `nodeIntegration: false` for any web content. Only a narrow preload bridge between UI and main process.
  - The one exception, for saved passwords: a tiny helper inside web pages (`src/page-preload.ts`), in its own isolated world, that exposes nothing to the page. It only reports a sign-in and asks for a login to fill. The main process trusts nothing it says about which site it is: it only accepts Firn's own pages' top frames, takes the site from the frame's real address, and only on https (or this computer). Passwords are encrypted with the system's protection (`safeStorage`) or not saved at all.
- **Engine layer:** keep Firn able to move to a Chromium fork later. Two rules for all code:
  1. The UI (`src/ui/`) never touches Electron; it only talks through the preload bridge (`window.firn`).
  2. App logic (tabs, spaces, Basecamp, pins, session) never touches Electron's page views directly; it uses the engine interface in `src/engine/engine.ts`. Electron's version lives in `src/engine/electron.ts`.
  Window and overlay code (`src/main.ts`) may stay Electron-specific; a fork would rewrite it natively anyway.
- **State:** one central store for the tab model, saved to disk so sessions survive restarts. Design it so it can later sync to a cloud database (Supabase or Firebase) for multi-device.

### Core data model (get this right first)

```
Space   { id, name, icon, color, order }
Tab     { id, spaceId, url, title, favicon, pinned, homeUrl?,
          order, lastActiveAt, splitGroupId? }
SplitGroup { id, spaceId, tabIds[], layout, sizes[] }
Window  { id, activeSpaceId, activeTabId, sidebarWidth, sidebarCollapsed }
```

Lookout overlays are temporary and are not stored as tabs until promoted.

---

## Roadmap

Each phase has a "done" test. Don't start the next phase until the current one passes.

1. **Window that browses** — Electron app opens, loads a site, address bar, back/forward/reload.
   *Done:* David can browse normally in it for 10 minutes.
2. **Sidebar + vertical tabs** — Tab model, sidebar UI, new/close/switch/reorder tabs, design tokens applied.
   *Done:* It already looks calm and spacious, and David prefers it to Chrome's vertical tabs.
3. **Pinned tabs + persistence** — Pinned grid, session restore.
   *Done:* Close and reopen; everything comes back exactly as it was.
4. **Spaces** — Create/switch/theme spaces.
   *Done:* Work and personal spaces feel like separate browsers.
5. **Lookout + split view + command bar.**
   *Done:* Used daily without reaching for another browser.
6. **Polish & shipping** — Shortcuts, settings, auto-updates, Windows/Mac/Linux builds, code signing (later, when sharing with testers).
7. **Later** — Cross-device sync, mobile companion app (iOS requires WebKit, so it's a separate native app).

---

### Where we are

*Update this note whenever a step lands.*

- **Phases 1–5: done.** Firn browses, has the sidebar with vertical tabs, pins, Basecamp, spaces, session restore, Lookout, split view and the command bar.
- **Phase 6 (polish & shipping): in progress.**
  - Done: find in page, zoom, right-click menus, downloads, PDF viewer, site permissions, history, settings (including the address bar's two looks), saved passwords, scam and malware warnings (Google Safe Browsing), the welcome, Fraunces brand headings, the Firn menu at the bottom-left, the Windows installer ("Firn Setup.exe"), version 0.1.0, the MPL 2.0 license, and automatic Windows and Mac builds on GitHub (releases attach the downloads).
  - Next: test on a real Mac, then auto-updates. Later: Apple notarization ($99/year, needed before sharing widely and for Mac auto-updates) and Windows code signing (optional).
- **Not shared yet:** personal use and a few friends first. See "Decided: coming later" below for what's queued.

## Decided: coming later

Agreed with David; not started yet. Build them one at a time, in small steps like everything else.

- **Make Firn the default browser:** a plain option in Settings and in the welcome, so links clicked in other apps open in Firn (the normal browser window, no special mini-window).
- **Sound in tabs:** first a small speaker icon on any tab playing sound (click to mute); then a mini player at the bottom of the sidebar, above the Firn button, shown only while audio plays in a tab that isn't on screen (title, play/pause, click to go to the tab).
- **Archiving old tabs:** everyday tabs not looked at for a while tidy themselves away. Options in Settings: 1 day, 7 days, **30 days (default)**, Never. Never archived: pinned and Basecamp tabs, the tab on screen, a tab playing sound, a tab in split view. Archived isn't deleted: an Archive list (Firn menu, command bar) brings any of them back, and they stay in History. Count days Firn was used, not calendar days (a vacation doesn't empty the sidebar).
- **Import passwords from another browser:** from the export file every browser and password manager can make (Chrome, Edge, Firefox, Safari, Bitwarden, 1Password), with short plain steps for each browser; imported passwords are encrypted like Firn's own, and Firn offers to delete the export file afterwards (it holds every password as plain text). In Settings > Saved passwords ("Import…") and as an optional welcome step. Reading them straight from Chrome or Edge isn't possible on Windows (they lock their passwords to themselves since 2024). Open question, decide separately: bookmarks and history. They can be read directly, but Firn has no bookmarks (pins and Basecamp instead), so they probably belong in what the command bar can search, not in the sidebar.
- **Extension support:** many people rely on one or two (password managers, ad blockers). Electron only partly supports Chrome extensions: research what works before promising anything.
- **A full-window welcome:** the welcome fills the whole window (calm background, big Fraunces headlines, choices reflected live), then glides away to reveal the browser. Do it before sharing Firn widely.

## Deliberately not doing

The "guts to say no" list. Don't add these without David asking again.

- **A separate mini-window for links from other apps** (Arc's "Little Arc"): links open in the normal window, as people expect.
- **Easels** (Arc's canvases of clippings): niche.
- **Boosts** (restyling websites, forcing dark mode): bloat; even tinkerers rarely use them.
- **A developer mode:** F12 already opens the developer tools; that's enough.
- **Tab folders:** not now. Spaces, pins and Basecamp already organize tabs, and folders would add a fourth layer to explain. If testers ask (e.g. "my pinned list is too long"), consider simple one-level folders inside a space's pinned tabs only.

## How to work on this project (instructions for Claude)

- Work in **small steps**: one feature at a time, then stop so David can run the app and look at it.
- After each step, say in plain words what changed and how to test it.
- **Design is half the job.** When building UI, follow the design principles and tokens above. If something would look cramped or loud, flag it.
- Ask before adding new dependencies; prefer few, well-maintained ones.
- Never weaken the security defaults above.
- Commit to Git after each working step with a clear message.
- Primary platform for now: **Windows**. Keep code cross-platform anyway.
