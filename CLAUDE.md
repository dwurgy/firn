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
- **Serial (Oxford) comma, always.** In a list of three or more, a comma goes before the final "and" or "or": "tabs, color, and icon", "macOS, Windows, and Linux". Everywhere people read Firn's words: the app's interface, the welcome, warnings, menus, the README, release notes, and the website. (Two items take no comma: "mail and calendar".)
- **Opinionated: two looks, never more.** Firn picks the layout for people, the way mainstream browsers did for decades: vertical tabs in the sidebar, the page as the star. The one choice is where the address bar sits ("In the sidebar" or "At the top"), offered on every platform, at onboarding and in settings. That's the last layout choice Firn ever gets: no top-bar tabs, no icon-only sidebar. Wanting more room is answered by hiding the sidebar (Ctrl+S, peeks at the left edge), not by more layouts.
  - *In the sidebar* (default): the current design. On Windows/Linux, reaching the top edge slides down a slim top bar with minimize/maximize/close, for dragging and double-clicking the window. On macOS there's no bar: the window's top edge itself grabs (its traffic lights stay in the sidebar).
  - *At the top*: the top bar is always there, across the whole window, and the sidebar's top row moves up into it: on the left, the window's traffic lights (macOS), the sidebar button, and back, forward, and reload; the **same address bar** (same component, height, look and width as in the sidebar) centered over the page area; on the right, the window buttons (Windows/Linux; on macOS the right side stays empty). The sidebar, docked or peeking, sits below the bar with Basecamp, tabs, and spaces. The traffic lights never move in this look (no handoff between the bar and a sliding sidebar), and the left edge only brings the sidebar out below the bar.
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

### First light (the welcome and the empty page)

Firn's brand moments use the "First light" look: sunrise in a snowy cabin, coffee in hand. Cool glacier sky high, warm sunrise low, snow at the bottom. Code: `src/ui/FirstLight.tsx` (the scene and the snow) and the "First light" section of `src/ui/styles.css`.

- **Where:** the full-window welcome (sky, sun, drifting flakes, snow, grain) and the empty page (the same sky and sunrise, snow, and the mark). Not on everyday browser UI.
- **Only the snow and the mark take the space's color.** The glacier sky haze and the orange sunrise glow stay the same for every space (David's call: they're First light's constant).
- **Snow:** five wavy bands. Glacier blues by default and for a Glacier space (the first color, the default for new spaces, so nothing shifts at the welcome's space step); with another space color, `mix(page, space, 20/33/47/62/78%)` in light and `mix(#2B2826, space, 12/20/29/38/48%)` in dark. A color change cross-fades (400ms).
- **Dark = "blue hour":** a dark sky with a deep glacier haze and a faint ember low down, dark snow, light ink buttons.
- **Performance (required):** no `backdrop-filter` on large surfaces ("glass" is a semi-clear color); the paper grain sits under the content, never over blurred things; glows are plain gradients and the snow is one SVG; nothing re-renders while idle; motion is transform and opacity only, and stops with reduced motion.
- **The welcome's finish** ("Welcome in."): about 2.4s, unhurried (David found 1.6s too fast to enjoy); the words hold a moment, the browser rises over them (about 1.1s), then the scene fades to the real browser. Reduced motion: a plain 300ms fade.

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
  - Done: find in page, zoom, right-click menus, downloads, PDF viewer, site permissions, history, settings (including the address bar's two looks), saved passwords, scam and malware warnings (Google Safe Browsing), the welcome, Fraunces brand headings, the Firn menu at the bottom-left, the Windows installer ("Firn Setup.exe"), version 0.1.0, the MPL 2.0 license, and automatic Windows and Mac builds on GitHub (releases attach the downloads), and the first round of testing on real Macs (traffic lights that move with the sidebar, page corners matching macOS 26+, the window's top edge to grab it).
  - First light: the full-window welcome (sunrise scene, frosted cards, snow in the space's color, the "Welcome in." finish) and the empty page (the sky and sunrise, with snow and the mark in the space's color). Glacier is the first space color and the default for new spaces. See "First light" under the design principles.
  - Auto-updates: Windows built, to be tested on a real install (an installed copy checks GitHub releases through update.electronjs.org and updates on the next start); Mac follows notarization.
  - Mac menu bar: short Firn / File / Edit / View / Window / Help menus (`src/menu.ts`), Firn > Settings… (Cmd+,); Ctrl+, already opened Settings on Windows. To be checked on David's Mac mini.
  - Mac app icon: the Liquid Glass icon (`brand/icon-composer/Firn.icon`) on macOS 26+, compiled by GitHub's Mac build; older Macs keep the .icns. To be checked on David's Mac mini.
  - **Apple notarization: done** (checked on David's Mac: opens with no "Open Anyway"; the first notarization took about 37 minutes). David made the Developer ID Application certificate and the App Store Connect API key, and added the six GitHub secrets (`MAC_CERTIFICATE_P12` as base64, `MAC_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_TEAM_ID`; never pasted to Claude). GitHub's Mac build imports the certificate into a keychain of its own, signs with the hardened runtime and osx-sign's default (Chrome-like) entitlements, notarizes with the API key, staples, and checks the result (`codesign`, `stapler`, `spctl`, the team ID). Without the secrets a push falls back to the ad-hoc signature; a release fails. Camera, microphone, and location have plain usage texts (`extendInfo` in `forge.config.mts`). Next: Mac auto-updates. Later: Windows code signing (optional).
- **Release notes:** `CHANGELOG.md`. 0.1.0 is the first public release, written as an introduction ("Meet Firn, a calm browser for everyone."); David publishes it on GitHub once notarization and Mac auto-updates are done (its notes say Firn keeps itself up to date on Windows and Mac), and only then starts sharing the link. From the next version on, each release gets a one-line headline, a sentence or two on the biggest change, and short New / Better / Fixed lists in plain words (new features = next minor version, fixes only = next patch).
- **Not shared yet:** personal use and a few friends first. See "Decided: coming later" below for what's queued.

## Decided: coming later

Agreed with David; not started yet. Build them one at a time, in small steps like everything else.

- **Drag to reorder Basecamp tiles (for 0.1.0):** the tiles move like the sidebar's tabs do, gliding as you drag. Reordering within Basecamp only; dragging a tab into Basecamp or a tile out of it can come later.
- **Built-in ad blocking (the headline of 0.2.0: "Firn now blocks ads and trackers."):** on by default, with an obvious, gentle way out when a site breaks ("Allow ads on this site"). Likely Ghostery's open-source ad blocker for Electron (a new dependency: ask David first). Firn downloads and updates the block lists, and the README says so plainly, so the privacy claims stay true.
- **Make Firn the default browser:** a plain option in Settings and in the welcome, so links clicked in other apps open in Firn (the normal browser window, no special mini-window).
- **Sound in tabs:** first a small speaker icon on any tab playing sound (click to mute); then a mini player at the bottom of the sidebar, above the Firn button, shown only while audio plays in a tab that isn't on screen (title, play/pause, click to go to the tab).
- **Archiving old tabs:** everyday tabs not looked at for a while tidy themselves away. Options in Settings: 1 day, 7 days, **30 days (default)**, Never. Never archived: pinned and Basecamp tabs, the tab on screen, a tab playing sound, a tab in split view. Archived isn't deleted: an Archive list (Firn menu, command bar) brings any of them back, and they stay in History. Count days Firn was used, not calendar days (a vacation doesn't empty the sidebar).
- **Import passwords from another browser:** from the export file every browser and password manager can make (Chrome, Edge, Firefox, Safari, Bitwarden, 1Password), with short plain steps for each browser; imported passwords are encrypted like Firn's own, and Firn offers to delete the export file afterwards (it holds every password as plain text). In Settings > Saved passwords ("Import…") and as an optional welcome step. Reading them straight from Chrome or Edge isn't possible on Windows (they lock their passwords to themselves since 2024). Open question, decide separately: bookmarks and history. They can be read directly, but Firn has no bookmarks (pins and Basecamp instead), so they probably belong in what the command bar can search, not in the sidebar.
- **Extension support:** many people rely on one or two (password managers, ad blockers). Electron only partly supports Chrome extensions: research what works before promising anything.

## Deliberately not doing

The "guts to say no" list. Don't add these without David asking again.

- **A separate mini-window for links from other apps** (Arc's "Little Arc"): links open in the normal window, as people expect.
- **Easels** (Arc's canvases of clippings): niche.
- **Boosts** (restyling websites, forcing dark mode): bloat; even tinkerers rarely use them.
- **A developer mode:** F12 already opens the developer tools; that's enough.
- **Tab folders:** not now. Spaces, pins and Basecamp already organize tabs, and folders would add a fourth layer to explain. If testers ask (e.g. "my pinned list is too long"), consider simple one-level folders inside a space's pinned tabs only.

## How to work on this project (instructions for Claude)

- **Only work in dwurgy/firn.** The website (dwurgy/firn-site) has its own separate Claude Code session. Never attach, clone, or change another repository; if a task touches the website, tell David so he can take it there.
- Work in **small steps**: one feature at a time, then stop so David can run the app and look at it.
- After each step, say in plain words what changed and how to test it.
- **Design is half the job.** When building UI, follow the design principles and tokens above. If something would look cramped or loud, flag it.
- Ask before adding new dependencies; prefer few, well-maintained ones.
- Never weaken the security defaults above.
- Before committing, run `npm run lint`, `npm run typecheck` and the end-to-end checks (`bash tests/e2e/run.sh`, see `tests/e2e/README.md`); add or update a check for what changed.
- Commit to Git after each working step with a clear message.
- Primary platform for now: **Windows**. Keep code cross-platform anyway.
