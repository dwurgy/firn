# Project Brief — Firn (native Apple prototype)

**Firn** (firnbrowser.com) is a calm, minimalist desktop browser. The name comes from firn, the settled, compacted snow high on alpine glaciers: quiet, clean, and still. Let that idea quietly inform the visual identity (soft whites, frost, gentle glacier tones alongside warm neutrals) without getting literal or icy-cold.

**This repo (`dwurgy/firn-swift-test`) is a private experiment:** Firn rebuilt from scratch as a native Apple app in Swift, SwiftUI, and WebKit, for macOS first and iOS later. The shipping Firn is the Electron app in `dwurgy/firn` (Windows and Mac); it stays the real product until David decides otherwise. If he goes ahead, this code moves into `dwurgy/firn` and Firn becomes Apple-only. Until then, nothing about this prototype is public: no mentions on the website, socials, or release notes.

This prototype also tries a new idea the Electron app doesn't have yet: **every space is truly separate** (its own Basecamp, sign-ins, cookies, and history), and the archive is a visible group in the sidebar. See "How spaces work."

Built by David with Claude. David is not a professional developer, so explain decisions in plain language and keep changes small and testable. Personal use first. No rush: quality and feel over speed.

---

## North star

**It should feel calm.** Every screen should breathe. If something feels crammed, busy, or "techy," it's wrong, even if it works.

Inspired by the *experience* of Dia, Arc, and Zen, but all visuals, icons, and names are our own. Never copy their logos, assets, or branding.

## Vision: Dia, Arc, and Zen for everyone

Dia, Arc, and Zen have great ideas, but they're built for power users or early adopters. Firn brings their best ideas to normal people (friends and family, not just enthusiasts) in a calm, beautiful package, without the power-user bloat.

**Four words: Privacy, Simplicity, Calm, Beauty.**

- **Spaces are the big idea, and each space is its own browser.** Work and Personal don't just look different: they have their own Basecamp, tabs, sign-ins, cookies, and history. That's easier to understand than any mix of Profiles, Containers, and Spaces, so Firn has Spaces and nothing else.
- **Have the guts to say no.** Before adding a feature, ask: would a non-techy person understand it and miss it if it were gone? If it mainly serves power users, leave it out, or tuck it away so it never adds clutter.
- **Short menus.** No giant right-click menus. A menu shows the few things you'd actually reach for, in plain words.
- **Discoverable, not memorized.** Anything important can be found by looking or right-clicking; keyboard shortcuts are a bonus, never the only way.
- **Nothing hidden.** If Firn tidies something away, you can see where it went (the archive is a group in the sidebar, not a box to discover).
- **Privacy by default.** Data stays on the device unless the person chooses otherwise. No tracking, no telemetry, and privacy claims are only made when they're true.
- **Names: plain words win.** Keep a familiar word when it's already plain English (Spaces, Pins, Archived). Give something our own name when other browsers' word is their brand coinage or unclear (Basecamp instead of Essentials, Lookout instead of Glance).
- **Serial (Oxford) comma, always.** In a list of three or more, a comma goes before the final "and" or "or": "tabs, color, and icon", "macOS, Windows, and Linux". Everywhere people read Firn's words: the interface, the welcome, warnings, menus, the README, and release notes. (Two items take no comma: "mail and calendar".)
- **Opinionated: two looks, never more.** Vertical tabs in the sidebar, the page as the star. The one choice is where the address bar sits ("In the sidebar" or "At the top"), at onboarding and in settings. No top-bar tabs, no icon-only sidebar. Wanting more room is answered by hiding the sidebar (it peeks at the left edge), not by more layouts.
  - *In the sidebar* (default): no title bar. The window's top edge is the grip; the traffic lights sit in the sidebar's top row.
  - *At the top*: a slim bar across the whole window. The sidebar's top row moves up into it, in exactly the same spot, so switching looks or hiding the sidebar moves nothing: traffic lights and the sidebar button on the left, back, forward, and reload at the sidebar column's right edge, and the **same address bar** (same view, height, and look) centered over the page. The traffic lights never move in this look.
- **Calm over clever.** When a choice is between more options and less to think about, pick less to think about.

---

## Design principles

1. **Space is a feature.** Generous padding, comfortable row heights, nothing touching the edges. When in doubt, add room.
2. **Minimal chrome.** The web page is the star. Browser UI recedes until needed.
3. **Warm and organic, not techy.** Soft neutrals, warm tones, gentle contrast. No neon accents, no pure black or white.
4. **Soft translucency.** The sidebar and overlays are frosted glass, tinted by the current space's color.
5. **Quiet motion.** Short and eased. Things glide; nothing snaps or bounces. Springs are fine only with no bounce (`.smooth`, or `.spring(duration: 0.25, bounce: 0)`). Every animation respects Reduce Motion.
6. **One accent at a time.** Each space has one color; everything else stays neutral.

### Native, not a web page

Don't imitate the Electron app's DOM or CSS. Use what Apple's frameworks do best, as long as the result looks and feels like Firn:

- SwiftUI first; drop to AppKit (or UIKit on iOS) only where SwiftUI can't do the job, and say why in a comment.
- System materials for glass: Liquid Glass (`.glassEffect`) on macOS 26 and later, `.ultraThinMaterial` / `.regularMaterial` as the fallback on 14 and 15 (behind `if #available`). System materials are composited by the OS, so they're fine on large surfaces like the sidebar, unlike CSS blur.
- `NavigationSplitView` only if it can do Firn's sidebar exactly (resizable 200–360pt, collapse to 0, peek at the left edge). If it fights the design, build the sidebar with a custom layout instead; don't bend the design to fit the control.
- SF Symbols for standard actions (back, forward, reload, close, share). **Space icons stay Firn's own** line icons, drawn in the space's color; never emoji.
- Native menus, keyboard shortcuts, and the system's text, focus, and accessibility behavior. Everything works with VoiceOver and keyboard only.

### Design tokens (pt; CSS px on the Mac equal points, so the numbers carry over 1:1)

```
Sidebar width:        260pt default (resizable 200–360pt), collapsible to 0
Tab row height:       36pt, padding 8pt × 12pt, 4pt apart
Section spacing:      20pt
Corner radius:        10pt tabs and rows; 9pt Basecamp tiles (crisper, so the glass reads as ice); 14pt panels (Lookout,
                      command bar, cards); 8pt small buttons and fields
Page inset:           the page floats 8pt inside the frame, 12pt corners
                      (8pt on macOS 26+, matching Liquid Glass window corners)
Traffic lights:       placed by macOS (empty toolbar); the top row lines up with them
Font:                 system font (SF): 13pt tabs, 12pt labels, 11pt hints;
                      Fraunces (soft) only for brand moments: the welcome
                      (30pt), the scam warning (27pt), the empty page (24pt),
                      and panel titles (22pt)
Motion:               about 200ms, ease-out or bounce-free spring
Light and dark:       both, following the system
```

**Colors** (live in one place, `Theme.swift` or an asset catalog with light and dark variants; never hard-coded in views):

```
Light   frame #E9E3DA · page #FBFAF8 · ink #241F1B · muted #5E564E · faint #9D9389
Dark    frame #3A3734 · page #2B2826 · ink #F5F1EC · muted #D4CDC5 · faint #958D85
Frost   rgba(130,168,190,.45) light · rgba(160,196,214,.45) dark (focus, selection)
Danger  #B0503A light · #E3907A dark (scam warnings: muted terracotta, never alarm red)
Spaces  Glacier #7F9CB0 (default) · Sand #C9A27E · Sage #8FAE8B · Heather #B88A9E
        Ochre #C4A95B · Dusk #8E8FB8 · Clay #B07F6A · Lagoon #6FA3A0
Glow    glacier #9DB7C8 · apricot #F2C4A0 · peach #ECCEBA · sage #B9CDB5
```

- Neutrals lean warm (sand and brown), never blue-gray. Hover and press are a warm brown wash (7% and 13% of rgb(70, 55, 40) in light; warm white in dark).
- The active space tints the frame and glass at about 16% (14% in dark) and cross-fades on switch.
- Blue is branding, never text. Sand never carries text. Buttons are ink. Shadows are warm brown, never grey.
- Glacier stays #7F9CB0 / #6E98B2; no darker "contrast-fixed" versions.

**Fraunces:** bundled in the app (SIL Open Font License, keep the license file next to it), never downloaded. Soft corners on, wonky letters off (`SOFT` 100, `WONK` 0, optical size automatic). SwiftUI can't set custom font axes directly, so build the font through Core Text font variations in one helper and use it everywhere. Emphasis in Fraunces headlines is weight (360, then 600), never color, never heavier than 600.

**Logo and icons:** use only the final files from the brand kit (`brand/`). Never redraw or re-type the logo or wordmark. The app icon is the glacier tile; on macOS 26 it's the `Firn.icon` from Icon Composer.

### First light (the welcome and the empty page)

Firn's brand moments use the "First light" look: sunrise in a snowy cabin near Sisters, Oregon, coffee in hand. Cool glacier haze high, warm apricot sunrise low, snow at the bottom, a faint paper grain, and a few drifting flakes (the small-cut mark, never on text).

- **Where:** the full-window welcome and the empty page (no open tabs). Never everyday browsing, settings, Lookout, the command bar, menus, downloads, or scam warnings.
- **Only the snow and the mark take the space's color.** The sky and sunrise are always Firn's own.
- **Snow:** five wavy bands; glacier blues by default and for a Glacier space; with another space color, mix page with the space color at 20/33/47/62/78% (light) or #2B2826 with it at 12/20/29/38/48% (dark). Color changes cross-fade (about 400ms).
- **Dark = "blue hour":** a dark sky with a deep glacier haze, a faint ember low down, and dark snow.
- **The welcome's finish** ("Welcome in."): about 2.4s, unhurried; the words hold a moment, the browser rises over them (about 1.1s), then the scene fades to the real browser. Reduce Motion: a plain 300ms fade.
- **Performance (required):** gradients and shapes, not heavy filters; the grain is a static image under the content; nothing animates or redraws while idle (no `TimelineView` running in the background); motion uses transforms and opacity; everything stops with Reduce Motion.

---

## How spaces work

Each space is its own browser. This is the heart of the prototype; get it right before polishing anything else.

- **Always the space's own:** Basecamp tiles, pinned tabs, open tabs, and the Archived group. Nothing in the sidebar is shared between spaces.
- **Separate by default:** each new space has its own sign-ins, cookies, site data, history, and saved passwords. Signing into Gmail in Work doesn't sign you into Personal.
- **Sharing is one choice, made when creating a space:** "Keep this space separate" (the default, recommended) or "Share sign-ins with [another space]." Sharing joins that space's sign-ins, cookies, site data, history, and saved passwords. The new space still gets its own empty Basecamp, pins, and tabs.
- **Plain words in the "New space" sheet:** a separate space says it starts signed out of everything; a shared one says which space it shares with.
- **Later changes:** a shared space can "Stop sharing" (it starts fresh and signed out, after a confirmation). Two separate spaces can't be merged.
- **Deleting a space** deletes its tabs and its browser data, after a confirmation that says so. Shared data stays as long as another space still uses it.
- **Nothing leaks between separate spaces:** the command bar, address suggestions, history, and Lookout use only the current space's data.
- **Links from other apps** open in the space used last.

---

## Features (build in the roadmap's order)

- **Vertical tabs:** favicon and title; close button on hover; drag to reorder with rows gliding into place; sidebar collapses and peeks at the left edge.
- **Basecamp:** the grid of everyday sites at the top of each space (up to 12), different in every space.
- **Pins:** per space, under the space's name. Basecamp and pinned tabs remember their home address; closing one lets it rest until clicked; "Go back to home" resets it.
- **Spaces:** name, color, Firn's own icon, and their own browser data (see "How spaces work"); switch from the row at the bottom of the sidebar or with a shortcut; the tint cross-fades.
- **Archived:** everyday tabs not looked at for a while (7 days of using Firn by default; 1 day, 30 days, or Never in Settings) move into a group named "Archived" at the bottom of the space's tab list. It's folded by default and shows a count; open it to see them, click one to bring it back. Never archived: Basecamp and pinned tabs, the tab on screen, a tab playing sound, and a tab in split view. Count days Firn was used, not calendar days.
- **Lookout:** a link preview in a floating rounded panel over the page with a dimmed backdrop; Esc or clicking outside closes it; one button turns it into a tab.
- **Split view:** two pages side by side, each with its own address and back/forward; drag the gap to resize; one row in the sidebar.
- **Command bar:** one shortcut opens a centered bar: type an address, search, jump to an open tab in this space, or run an action by name.
- **Later, as on Electron:** sleeping tabs, sound and the mini player, downloads, find in page, zoom, permissions, saved passwords, ad and tracker blocking, and scam warnings.
- **Later, new ideas (each its own step, ask first):**
  - **Reading mode:** a calm, text-only view of an article. WebKit has no built-in reader for other browsers, so this likely needs an open-source article parser (a dependency: ask).
  - **Back and skip in the mini player:** previous and next track, not only play and pause. Investigate how the page's media controls can be reached first.
  - **Import passwords** from the export file other browsers and password managers make, then offer to delete that file (it holds every password as plain text). Opus.
  - **Where a tab came from:** a new tab opened from a link quietly shows which tab it came from (leaning toward a hover echo in the space's color), without a tree, indenting, or extra menus.

Keyboard shortcuts match the Mac version of the Electron app unless David decides otherwise.

---

## Architecture

- **Platforms:** macOS 14+ now; iOS 17+ later (both needed for separate website data per space). Swift 6 language mode with strict concurrency; SwiftUI.
- **Project shape:** a thin Xcode app target (`Firn.app`, for signing, entitlements, Info.plist, and the icon) plus a local Swift package (`FirnCore`) holding the logic, so most code builds and tests from the command line and can later be shared with an iOS target. If the Xcode project file becomes a pain to edit, propose XcodeGen and ask first.
- **Engine:** `WKWebView`, wrapped with `NSViewRepresentable` (and `UIViewRepresentable` on iOS). On macOS 26 and later, SwiftUI's own `WebView`/`WebPage` may replace the wrapper; decide that as its own step.
- **Engine layer:** two rules, as on Electron:
  1. Views never talk to `WKWebView` directly; they talk to a small `BrowserEngine` / `PageController` protocol.
  2. App logic (tabs, spaces, Basecamp, pins, archive, session) never touches WebKit; only the engine's implementation does. Each tab owns its controller; the model owns no views.
- **Per-space data:** each space has a `dataStoreId`. Separate spaces get a new one; a shared space uses the same id as the space it shares with. Every web view in a space, including Lookout and split view, uses `WKWebsiteDataStore(forIdentifier: dataStoreId)`, never `.default()`. Firn's own history and saved passwords are stored per `dataStoreId` too. Deleting the last space that uses an id removes its store (`WKWebsiteDataStore.remove(forIdentifier:)`).
- **State:** one observable store (`@Observable`) for the tab model, saved to disk as Codable JSON in Application Support so sessions survive restarts. Keep it sync-ready (stable ids, a last-changed time on every record), but no sync now.

### Core data model (get this right first)

```
Space      { id, name, icon, color, order, dataStoreId }
Tab        { id, spaceId, url, title, favicon,
             place (basecamp, pinned, open, or archived),
             homeUrl?, order, lastActiveAt, openerTabId?, splitGroupId? }
SplitGroup { id, spaceId, tabIds[], layout, sizes[] }
Window     { id, activeSpaceId, activeTabId, sidebarWidth, sidebarCollapsed }
```

Lookout panels are temporary and aren't stored as tabs until promoted.

---

## Security

Firn is a browser: people trust it with their passwords, history, and everything they read. **Security comes before features and before saving budget.** WebKit's process isolation is a good start, not a guarantee.

- **App Sandbox on, Hardened Runtime on.** Only the entitlements Firn needs (network client, user-selected files and Downloads, camera and microphone only when a site asks). Never add an entitlement without telling David why.
- **Space separation is a privacy promise.** If a space says it's separate, no cookie, sign-in, history entry, suggestion, or saved password from another space may reach it. Add a check that proves it (sign in to a test site in one space; the other stays signed out). Never fall back to the default data store.
- **Web pages are untrusted, always.** Anything from a page (addresses, titles, favicons, script messages, downloads, permission requests, anything in a frame) is hostile input.
- **Script messages:** any `WKScriptMessageHandler` checks the frame (main frame only where that's the rule), the real origin from `WKFrameInfo.securityOrigin` (never what the message claims), and the message's exact shape. Firn's own page scripts run in their own `WKContentWorld`, never the page's world, and expose nothing to the page.
- **Only http and https** (plus the existing local file cases) reach navigation, new tabs, and links from other apps. Anything else is refused or asked about. Check addresses before handing them to `NSWorkspace.open`.
- **The address bar must never lie.** Show the committed URL, not a pending one; watch for spoofing during slow or failed navigations and in popups.
- **Saved passwords** (later): encrypted in the Keychain, per data store, filled only into the very same site over https, only after a click into a sign-in form. Opus, and a plan first.
- **Ad and tracker blocking** (later): WebKit content rule lists compiled from the public lists; check rule limits per list. **Scam warnings** (later): WebKit has no built-in Safe Browsing for third-party browsers, so this needs its own design; ask before adding any network traffic for it.
- **Secrets and personal data:** none in the repo, logs, error messages, or anything sent over the network. Logs never contain addresses people visited.
- **No new network traffic without asking David,** and every privacy claim stays literally true. **Sync (CloudKit or otherwise) changes "your data stays on your device":** ask David first.
- **Dependencies:** ask before adding one (Sparkle for updates and a reading-mode parser included). Pin exact versions in `Package.resolved`.
- **Every change gets a security check before commit.** One line each: What new input does this accept, and from whom? What does it let a web page do that it couldn't? What does it send, store, or log? What happens if the input is malformed or hostile? If all four are "nothing new," say so in one line.
- **Say so when unsure.** Never present a guess as a guarantee.

---

## Deliberately not doing

Don't add these without David asking again.

- A separate mini-window for links from other apps (Arc's "Little Arc").
- Easels (Arc's canvases of clippings).
- Boosts (restyling websites, forcing dark mode).
- A developer mode (the Web Inspector is enough).
- Profiles or containers on top of spaces: spaces already are both.
- Tab folders. (Tab groups are a separate, open question: see "Open questions.")
- More layouts than the two looks.

---

## Open questions (David hasn't decided; don't build these)

- **Tab groups:** a light, good-looking way to gather a few related tabs in a space's tab list, like Dia's: flat, collapsible, and named by the person. Not folders: no nesting, and no hiding tabs inside other things. If David decides to try it, it's its own step with a plan first. The Firn version would be a name and the space's color dot, with no emoji or custom icons (Firn uses its own line icons) and no cloud-based auto-naming (naming on the device is fine; see the next question). Things to weigh then: how it sits beside Basecamp, pins, split view (already one combined row), and Archived without adding a layer people have to learn.
- **Small on-device AI touches:** quiet, optional helpers that use Apple's on-device model (the Foundation Models framework, macOS 26 and later with Apple Intelligence), such as a "Summarize" in Lookout or reader, and automatic names for tab groups if groups happen. Everything runs on the Mac: no cloud service, no account, no network traffic, so "your data stays on your device" stays literally true. They must be optional and simply absent on macOS 14 and 15 or when Apple Intelligence is off. No chat panel and no sidebar assistant; if it isn't quiet, it doesn't fit. If David decides to try one, it's its own step with a plan first, on Opus.
- **Optional sync across devices (iCloud):** tabs, spaces, Basecamp, and pins appear on a person's other Macs and, later, their iPhone. Off by default, and a plain-words choice when turned on: the data goes only to the person's own iCloud (CloudKit), never to Firn or any server of ours. Saved passwords would use iCloud Keychain, not our own sync. Cookies and sign-ins can't sync (WebKit doesn't allow it), so each device signs in on its own; the setting should say so. Each space's separation rules carry over: a separate space stays separate on every device. Sync changes "your data stays on your device" for people who turn it on, so any wording about it needs David's OK. It's its own step with a plan first, on Opus, after the core browser feels right.

---

## Roadmap

Each phase has a "done" test. Don't start the next until the current one passes.

1. **Window that browses:** a native window, one `WKWebView`, address bar, back, forward, and reload. *Done:* David browses normally in it for 10 minutes.
2. **Sidebar and vertical tabs:** tab model, sidebar, new, close, switch, and reorder; tokens applied. *Done:* it already looks calm and feels smoother than the Electron app.
3. **Pins, Basecamp, and persistence:** *Done:* quit and reopen; everything comes back exactly as it was.
4. **Spaces, truly separate:** create, switch, color, and delete spaces, each with its own data store and Basecamp, plus the "share sign-ins" choice. *Done:* two spaces signed into two different Google accounts at once, and a shared space that's already signed in.
5. **Archived, Lookout, split view, and the command bar:** *Done:* used daily without reaching for another browser.
6. **First light and the two looks:** the welcome, the empty page, and the address bar setting.
7. **Decision point:** David compares this with the Electron app and decides whether to continue. If yes, plan the move into `dwurgy/firn` as its own step (see "If this replaces the Electron app" below). Only then: privacy features, signing and notarization, updates, and iOS.

### If this replaces the Electron app

Not now; this is so nothing is a surprise at the decision point. Each is its own step, planned with David, on Opus.

- **Existing users.** Installed Electron copies update themselves from `dwurgy/firn`'s releases. They need one last Electron release that tells Mac users where the native app is, and tells Windows users plainly that Firn is now Mac-only.
- **Their data.** The Electron app keeps tabs, spaces, history, and passwords in `~/Library/Application Support/Firn`. A sandboxed app can't read that folder on its own, so moving people's tabs and spaces over needs a deliberate import. Passwords need extra care. Electron's shared Basecamp has to become per-space Basecamps (probably copied into each space).
- **Same identity.** Keep the app's name, icon, and signing team so macOS treats it as Firn. The bundle ID can be new.
- **Public copy.** The README, the website, and "a calm browser for everyone" all assume Windows. David decides how to say it.

### Where we are

- **Phase 1: done** (2026-10-17). Swipe back/forward still untested (no trackpad yet).
- **Phase 2: done** (2026-10-18).
- **Phase 3: in progress.** 3a (model and saving) done; 3b-i (Basecamp grid) done, next 3b-ii (pins, to be discussed first), then 3c (site icons, read from the page).

---

## How to work on this project (instructions for Claude)

- **Only work in `dwurgy/firn-swift-test`.** The Electron app (`dwurgy/firn`) and the website (`dwurgy/firn-site`) have their own sessions. Never attach, clone, or change another repository, even when the plan is to move this code into `dwurgy/firn` later: that move is its own step, done by David. You may describe how the Electron app does something only if David pastes it in.
- **Pick the model before starting** (David is on the Pro plan and wants his limits to last the week). Before any task, say in one line which model it needs and why: "Sonnet is fine: <reason>" or "This needs Opus: <reason>. Switch with /model, then say go." If it needs Opus and you're on Sonnet, stop and wait. If you're on Opus and Sonnet would do, say so and wait. If a Sonnet task turns out harder than it looked, stop and say so rather than guessing on.
  - **Sonnet (only the most basic tasks):** copy and wording, README edits, renames, and simple questions about the code. David's rule (2026-10-18): Sonnet wasted his time on design work, so anything visual, any SwiftUI view or layout, and anything else goes to Opus.
  - **Opus:** all design and SwiftUI work, core architecture and the data model, per-space data stores and sharing, the engine layer and `WKWebView` delegates (navigation, UI delegate, downloads, script messages), multi-window and app lifecycle, sandbox and entitlements, anything security-related (passwords, content worlds, permissions, content blocking, URL handling), performance work, signing, notarization, and updates, sync, and "look back" reviews.
  - When unsure, say which way it leans and why, in one line, and let David pick.
- **Spend David's budget carefully.** The aim is less bloat and less rehashing, never lower quality. Never skip reading code before editing it, building and testing before a commit, the security rules, or asking David at a real fork.
  - **Read less.** Find with Grep and Glob, then Read only the part you need. Don't re-read a file already read in this conversation unless it changed.
  - **Keep searching out of this conversation.** For broad questions, use the Explore agent. Don't spawn agents for anything else.
  - **Plan before multi-file work.** Say the plan in a few lines and wait for David's OK.
  - **One task per conversation, small steps.**
  - **Checkpoints.** When a step works and is committed, say so and always recommend one, with a one-line reason: "/clear" when everything that matters is saved (commits, this file, `docs/HISTORY.md`, memory), even if the same feature continues; "/compact" only when something important lives only in the conversation (a half-done change, an undocumented decision, a bug mid-hunt). Anything worth keeping goes in a commit or a short note here first.
  - **Short replies.** After a change: what changed, where, and how to test it, in a few lines. Don't recap the diff or paste whole files. Use Edit, not rewrites.
  - **Quiet output.** `xcodebuild` is very loud: pipe it through `tail` or `grep -E "error|warning: |BUILD"`. Never dump a whole log.
  - **Stuck rule.** After two failed attempts at the same fix, stop. Say what's known, what's been ruled out, and whether a fresh session or Opus would help.
- **Build and test from the command line** (on David's Mac, with Xcode installed):
  - `swift test --scratch-path ~/Library/Caches/FirnCore-build` inside `FirnCore` for logic (building inside `~/Documents` leaves Finder metadata that breaks code signing).
  - `xcodebuild -scheme Firn -destination 'platform=macOS' build` for the app, and `xcodebuild test -scheme FirnCore -destination 'platform=macOS'` inside `FirnCore` before committing (then delete the `FirnCore/.swiftpm` it leaves).
  - You can't see the running app. After each step, tell David exactly what to open and look at (light and dark, sidebar shown and hidden, Reduce Motion on).
- **Design is half the job.** Follow the principles and tokens above; flag anything that would look cramped, loud, or like a web page in a box.
- Ask before adding dependencies; prefer Apple's frameworks.
- Commit after each working step with a clear message. Keep this file lean: details and reasoning go in `docs/HISTORY.md` and commit messages; update "Where we are" in a line or two.
- **Every so often, a look back:** a review for bugs and for places to make Firn faster or lighter, then fixes in small steps.

## License

Firn's code is open source under the Mozilla Public License 2.0. **The Firn name, logo, and app icons are not covered by the license** (`brand/` and the app icon). Fraunces has its own license, the SIL Open Font License.
