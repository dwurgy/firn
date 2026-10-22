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
  - *At the top*: the top bar is always there, across the whole window, and the sidebar's top row moves up into it, in exactly the same spot (switching looks or hiding the sidebar moves nothing): the window's traffic lights (macOS) and the sidebar button on the left, back, forward, and reload at the sidebar column's right edge; the **same address bar** (same component, height, look and width as in the sidebar) centered over the page area; on the right, the window buttons (Windows/Linux; on macOS the right side stays empty). The sidebar, docked or peeking, sits below the bar with Basecamp, tabs, and spaces. The traffic lights never move in this look (no handoff between the bar and a sliding sidebar), and the left edge only brings the sidebar out below the bar.
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

*Keep this short; details go in `docs/HISTORY.md`.*

- **Phases 1–5: done.** Firn browses, has the sidebar with vertical tabs, pins, Basecamp, spaces, session restore, Lookout, split view, and the command bar.
- **Phase 6 (polish & shipping): in progress.** Done so far: find in page, zoom, right-click menus, downloads, PDF viewer, permissions, history, settings, saved passwords, scam and malware warnings, the First light welcome, ad and tracker blocking, default browser, archiving old tabs, sleeping tabs, sound in tabs and the mini player, split-view dragging, keyboard shortcuts sheet, auto-updates (Windows and Mac), Apple notarization, and Windows code signing. Latest published: **0.10.4**. **The next release is the last on Electron** (Firn is becoming a native Mac app): automatic updates are turned off and a goodbye card shows once (`src/farewell.ts`, `FAREWELL_URL` is a placeholder until David has the page); details in `docs/HISTORY.md`.
- **To be checked on David's Windows PC** (0.10.0/0.10.1, and the next release for F1, F2, F3, F8, F9, F10, and F13): a Reddit post's picture opens on its own in a new tab; the peeking sidebar tucks away when the mouse goes to the taskbar; suggestions from Google as you type; the Save dialog (choose a folder, cancel); the top bar comes down quickly when the mouse rests at the top edge, while a flick up to the Azure portal's search box (maximized) brings nothing; links from other apps still open in Firn after updating; Firn's own interface still opens and looks as before (it now loads from `firn://app`, security fix F1); sign-in popups and links opening new tabs still work (F2); a sign-in popup's title bar starts with its real site, e.g. "accounts.google.com — Sign in" (F3); a Zoom or Teams link on a page still asks to open the app (F8); downloads from a click still save, e.g. an installer from a "Download" page that starts by itself (F9); everything in Firn's own interface still looks and works as before, including the welcome and Settings (F10); Saved passwords' Show asks for Windows Hello, its prompt in front of Firn, and cancelling shows nothing (F13); a fresh Google sign-in works, in a tab and through a "Sign in with Google" popup (Firn shows Google a Firefox name there); the window moves when dragged from the empty space under the tabs, and right-clicking there shows Change color…, not Windows' Restore, Move, Size… menu (the top bar keeps that one); the next signed build on main (GitHub Actions) passes "Set up Mac signing" and "Set up Windows signing" (F12).
- **Full history** (every feature's what, where in the code, and why, plus the platform-bug write-ups, signing and notarization setup, and the demo recorder's details): `docs/HISTORY.md`. Read the relevant entry there before changing an area it covers (for example the blank-page-after-minimizing fixes, the top-edge logic, or the sidebar peek). The demo recorder itself is documented in `demo/README.md`.
- **Release notes:** `CHANGELOG.md`. 0.1.0 is the first public release, written as an introduction ("Meet Firn, a calm browser for everyone."); David publishes it on GitHub once notarization and Mac auto-updates are done (its notes say Firn keeps itself up to date on Windows and Mac), and only then starts sharing the link. From the next version on, each release gets a one-line headline, a sentence or two on the biggest change, and short New / Better / Fixed lists in plain words (new features = next minor version, fixes only = next patch). Keep CHANGELOG.md's shape (`## Firn X.Y.Z`, the headline in bold on its own line, then paragraphs and `### New` / `### Better` / `### Fixed` lists): Firn's What's new reads it.
- **Not shared yet:** personal use and a few friends first. See "Decided: coming later" below for what's queued.

## Decided: coming later

Agreed with David; not started yet. Build them one at a time, in small steps like everything else.

- **Sound in tabs:** first a small speaker icon on any tab playing sound (click to mute; done); then a mini player (done) at the bottom of the sidebar, above the Firn button, shown only while audio plays in a tab that isn't on screen (title, play/pause, click to go to the tab).
- **Drag a tab into split view:** done, including the demo's split-view clip.
- **Archiving old tabs:** built for 0.7.0 (see "Where we are"). Everyday tabs not looked at for a while tidy themselves away. Options in Settings: 1 day, **7 days (default)**, 30 days, Never. Never archived: pinned and Basecamp tabs, the tab on screen, a tab playing sound, a tab in split view. Archived isn't deleted: an Archive list (Firn menu, command bar) brings any of them back, and they stay in History. Count days Firn was used, not calendar days (a vacation doesn't empty the sidebar).
- **Import passwords from another browser:** from the export file every browser and password manager can make (Chrome, Edge, Firefox, Safari, Bitwarden, 1Password), with short plain steps for each browser; imported passwords are encrypted like Firn's own, and Firn offers to delete the export file afterwards (it holds every password as plain text). In Settings > Saved passwords ("Import…") and as an optional welcome step. Reading them straight from Chrome or Edge isn't possible on Windows (they lock their passwords to themselves since 2024). Open question, decide separately: bookmarks and history. They can be read directly, but Firn has no bookmarks (pins and Basecamp instead), so they probably belong in what the command bar can search, not in the sidebar.
- **From the first look back, still to do** (each checked by reading the code; fix in small steps): smoother and lighter: the daily ad-block and Safe Browsing list preparation freezes the main thread for about half a second to a second (move to a worker). Small bugs: on a Mac, closing and reopening the window duplicates the ad blocker and downloads (services are per window; make them app-wide) and an open Lookout keeps playing.
- **Other languages: to explore** (David: a handful of the most popular, nothing crazy). Today every word is written into the code (about 400 to 600 phrases: buttons, menus, Settings, the welcome, warnings, hover labels), with no language handling. Websites already get the system's languages from Chromium (check). The plan if it goes ahead: (1) move every phrase into an English list (`settings.title` = "Settings"), nothing visibly changing, plus a check that catches a phrase left in the code; (2) Spanish end to end, following the system's language with a "Language" setting to choose, and a look at tight spots for longer words (German runs about 30% longer); (3) French, German, Portuguese (Brazil), maybe Italian, one at a time. Plurals and dates through the engine's built-in `Intl` (no new dependency); right-to-left languages (Arabic, Hebrew) left out (the whole layout mirrors). Claude drafts translations; ideally a native speaker reads each once for Firn's calm voice. Release notes may stay English at first; the website is its own session's job.
- **Extension support: researched, postponed** (David: not worth the hassle for now). Electron supports only a small part of Chrome's extension APIs (no toolbar popups, native messaging, or declarativeNetRequest); the add-on that fills most gaps, electron-chrome-extensions, is GPL-3 unless you buy its patron license (electron-chrome-web-store, for Web Store installs, is MIT). Ad-blocking extensions can't work beside Firn's own blocker (Electron's webRequest hook always wins, and today's blockers need declarativeNetRequest), and Firn's blocker covers that need anyway. Password managers might work (1Password's link to its desktop app won't: Firn isn't on its list of browsers); untested. If it comes back: a throwaway test build with Bitwarden, 1Password, and a few everyday extensions, after deciding the license. Full support would come with a Chromium fork.
- **Where a tab came from: to explore, not decided** (David's idea): a new tab opened from a link quietly shows which tab it came from, so related tabs are easy to spot, without a tree, indenting, or extra menus. Investigated, nothing built; leaning toward a hover echo in the space's one color (Claude's report in the session of 14 Oct 2026).

## Deliberately not doing

The "guts to say no" list. Don't add these without David asking again.

- **A separate mini-window for links from other apps** (Arc's "Little Arc"): links open in the normal window, as people expect.
- **Easels** (Arc's canvases of clippings): niche.
- **Boosts** (restyling websites, forcing dark mode): bloat; even tinkerers rarely use them.
- **A developer mode:** F12 already opens the developer tools; that's enough.
- **Tab folders:** not now. Spaces, pins and Basecamp already organize tabs, and folders would add a fourth layer to explain. If testers ask (e.g. "my pinned list is too long"), consider simple one-level folders inside a space's pinned tabs only.

## How to work on this project (instructions for Claude)

- **Pick the model before starting** (David is on the Pro plan and wants his limits to last the week). Before starting any task, say in one line which model it needs and why: "Sonnet is fine: <reason>" or "This needs Opus: <reason>. Switch with /model, then say go." If it needs Opus and you're running Sonnet, stop and wait. If you're running Opus and Sonnet would do, say so and wait, so David can switch. Don't start the work until the model fits. If a Sonnet task turns out harder than it looked (the first fix didn't work, the cause isn't clear, it spreads across many files), stop and say so rather than guessing on.
  - **Sonnet:** release prep (version bump, CHANGELOG entry), Electron patch updates, copy and wording changes, README edits, small style tweaks in styles.css, a setting or menu item following an existing pattern, adding or updating a check, a bug in one place with a clear cause, renames and tidying, answering questions about the code.
  - **Opus:** new features that touch several files or the main process (like split-view dragging or archiving), anything security-related (passwords, page-preload.ts, permissions, the sandbox and preload bridge, the request blocker, signing), platform bugs that need investigating (Windows or Mac only, like the blank page after minimizing), performance work, the engine layer and data model, the build and release pipeline, and "look back" reviews.
  - When unsure, say which way it leans and why, in one line, and let David pick.
- **Spend David's budget carefully** (Pro plan). The aim is less bloat and less rehashing, never lower quality. Never save budget by skipping these: reading code before editing it, lint, typecheck and the checks before a commit, the security defaults, keeping privacy claims literally true, or asking David when something is a real fork.
  - **Read less.** Find with Grep and Glob, then Read only the part you need (offset and limit). Don't read all of big files like src/main.ts, src/tabs.ts, or styles.css. Don't re-read a file already read in this conversation unless it changed.
  - **Keep searching out of this conversation.** For broad questions ("where does X happen", "what touches Y"), use the Explore agent so the file dumps stay out of the main conversation. Don't spawn agents for anything else (each starts cold).
  - **Plan before multi-file work.** Say the plan in a few lines and wait for my OK. A wrong direction costs far more than the plan.
  - **One task per conversation, small steps.** A long conversation is re-read on every message, so its cost grows with every reply.
  - **Checkpoints.** When a step works and is committed, say so and tell me which fits: "/clear" (next task is unrelated) or "/compact" (same feature continues). You can't run these yourself, so tell me. Before I clear, anything worth keeping must be committed or in CLAUDE.md as a short note, not only in the chat.
  - **Short replies.** After a change: what changed, where, and how to test, in a few lines. Don't recap the diff, repeat my request back, or paste whole files. Use Edit for changes, not rewriting a file.
  - **Quiet output.** Pipe long command output through tail or grep. Never dump a whole log.
  - **Checks:** run the one targeted check while working, and the full suite once before committing.
  - **Stuck rule.** After two failed attempts at the same fix, stop. Say what's known, what's been ruled out, and whether a fresh session or Opus would help. Don't try a third time.
  - **Breaks.** The conversation's saved copy goes cold after about 5 minutes idle, so resuming a long one costs a full re-read. Finish and commit a step before I step away, and suggest /clear if it's a good moment.
  - **Keep CLAUDE.md lean.** When a step lands, put its detailed entry (what changed, where in the code, how to check it) in `docs/HISTORY.md`, and touch CLAUDE.md's "Where we are" only to update the latest version and the short "To be checked" list. The reasoning belongs in the commit message.
- **Only work in dwurgy/firn.** The website (dwurgy/firn-site) has its own separate Claude Code session. Never attach, clone, or change another repository; if a task touches the website, tell David so he can take it there.
- Work in **small steps**: one feature at a time, then stop so David can run the app and look at it.
- After each step, say in plain words what changed and how to test it.
- **Design is half the job.** When building UI, follow the design principles and tokens above. If something would look cramped or loud, flag it.
- Ask before adding new dependencies; prefer few, well-maintained ones.
- **Security.** The fuller plan, the hardening checklist, and the review routine are in `docs/SECURITY-PLAN.md`; read it before security work.
  - **Security comes before features and before saving budget.** Firn is a browser: people trust it with their passwords, history, and everything they read. Privacy and safety are the product. Being built on Chromium and Electron doesn't make Firn safe by default; it only gives a good start.
  - **Never weaken the security defaults above** (contextIsolation, sandbox, no nodeIntegration for web content, the narrow preload bridge, the page-preload.ts limits). If a task seems to need weakening one, stop and ask David first.
  - **Web pages are untrusted, always.** Anything that comes from a page (addresses, titles, favicons, messages from page-preload.ts, downloads, permission requests, anything inside a frame) is hostile input. The main process validates every message from the UI and from pages: who sent it (the right window or frame), what it is, and that it's the expected shape. Never trust a page's claim about which site it is.
  - **Only the schemes Firn means to handle** (http, https, and the existing local file cases) reach navigation, new tabs, links from other apps, and anything opened outside Firn. Anything else is refused or asked about. Check addresses before they're opened with the system (`shell.openExternal` and similar).
  - **The address bar must never lie.** Whatever Firn shows as the site is the site actually loaded. Flag anything that could show a different address than the page's real one.
  - **Secrets and personal data:** none in the repo, in logs, in error messages, or in anything sent over the network. Logs never contain addresses people visited. Passwords stay encrypted with the system's protection, or aren't saved.
  - **No new network traffic without asking David,** and every privacy claim (README, website, release notes) stays literally true. If a change alters what Firn sends or stores, say so, and flag that the README's "What Firn sends, and to whom" list and the website may need a matching update.
  - **Dependencies:** ask before adding one. Keep versions exact, keep the lockfile, run `npm audit --omit=dev` (stays at 0), and keep Electron current (below).
  - **Every change gets a security check before commit.** Answer these in one line each in the reply: What new input does this accept, and from whom? What does it let a web page do that it couldn't? What does it send, store, or log? What happens if the input is malformed or hostile? If the answer to all four is "nothing new", say so in one line.
  - **Say so when unsure.** If you can't tell whether something is safe, say that, and say what would settle it. Never present a guess as a guarantee.
- **Keep Electron current.** Its updates carry Chrome's security fixes, the most important upkeep a browser has. About monthly, update to the newest patch of the current major (`npm install --save-dev --save-exact electron@<version>`), run every check, and release it as a patch version ("Safer under the hood."). Move to a new major version as its own step, tested on both computers. (`npm audit --omit=dev` should stay at 0; the dev-only `tinypool` warning comes from the oxfmt formatter and never ships.)
- Before committing, run `npm run lint`, `npm run typecheck` and the end-to-end checks (`bash tests/e2e/run.sh`, see `tests/e2e/README.md`); add or update a check for what changed.
- Commit to Git after each working step with a clear message.
- **Every so often, a look back** (David): a review of what's been built, for bugs and for places to make Firn faster or lighter, then fixes in small steps like everything else.
- Primary platform for now: **Windows**. Keep code cross-platform anyway.
