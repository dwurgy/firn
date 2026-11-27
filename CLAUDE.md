# Project Brief — Firn (native Apple)

**Firn** (firnbrowser.com) is a calm, minimalist desktop browser. The name comes from firn, the settled, compacted snow high on alpine glaciers: quiet, clean, and still. Let that idea quietly inform the visual identity (soft whites, frost, gentle glacier tones alongside warm neutrals) without getting literal or icy-cold.

**This repo (`dwurgy/firn`) is the new Firn:** rebuilt from scratch as a native Apple app in Swift, SwiftUI, and WebKit, for macOS first and iOS later. It's decided (David, 2026-10-22): this code takes over Firn, and Firn becomes Apple-only. The native Mac version has been announced. The Electron app has had its last update and is out of support; its code now lives in `dwurgy/firn-legacy`. This code moved into `dwurgy/firn` on 2026-10-23, on top of the Electron history (the local folder is still named `firn-swift-test`).

The native Firn also brings a new idea the Electron app never had: **every space is truly separate** (its own Basecamp, sign-ins, cookies, and history), and the archive is a visible group in the sidebar. See "How spaces work."

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
- **Nothing hidden.** If Firn tidies something away, you can see it go and where it went (tidied-away tabs visibly drift into a button that appears as they go, never a box to discover).
- **Privacy by default.** Data stays on the device unless the person chooses otherwise. No tracking, no telemetry, and privacy claims are only made when they're true.
- **Names: plain words win.** Keep a familiar word when it's already plain English (Spaces, Groups, Archived). Give something our own name when other browsers' word is their brand coinage or unclear (Basecamp instead of Essentials, Lookout instead of Glance).
- **Thank bug reporters.** A fixed bug's release note thanks whoever reported it, by the name they gave (David, 2026-11-01).
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
- SF Symbols for standard actions (back, forward, reload, close, share). **Spaces have no icons:** a name and a color only (David, 2026-10-25).
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
                      Gooper Deck only for brand moments (the welcome and
                      the empty page); see "Brand font" below
Motion:               about 200ms, ease-out or bounce-free spring
Light and dark:       both, following the system
```

**Colors** (live in one place, `Theme.swift` or an asset catalog with light and dark variants; never hard-coded in views):

```
Light   frame #E9E3DA · page #FBFAF8 · ink #241F1B · muted #5E564E · faint #9D9389
Dark    frame #28241F · page #1C1916 · ink #F5F1EC · muted #D4CDC5 · faint #958D85
Frost   rgba(130,168,190,.45) light · rgba(160,196,214,.45) dark (focus, selection)
Danger  #B0503A light · #E3907A dark (scam warnings: muted terracotta, never alarm red)
Spaces  Glacier #7F9CB0 (default) · Sand #C9A27E · Sage #8FAE8B · Heather #B88A9E
        Ochre #C4A95B · Dusk #8E8FB8 · Clay #B07F6A · Lagoon #6FA3A0
Glow    glacier #9DB7C8 · apricot #F2C4A0 · peach #ECCEBA · sage #B9CDB5
```

- Neutrals lean warm (sand and brown), never blue-gray. Except menus, cards, and the iPhone's bars: neutral greys and whites, never warm or tinted by the space, so they sit beside Apple's own (David, 2026-11-15). The space's color stays on the overview's tint, the tab on screen's ring (none in the iPhone's grid, as Safari's; David, 2026-11-16), the check, the loading frost, and the Mac's sidebar and frame. Hover and press are a warm brown wash (7% and 13% of rgb(70, 55, 40) in light; warm white in dark).
- iOS's own menus on the iPhone show Close rows (Close Tab, Close Group, a tile's Close, Delete) in iOS's destructive red, as every app does (David, 2026-11-17); terracotta stays for scam warnings and Firn's own surfaces.
- The active space tints the frame and glass at about 16% (14% in dark) and cross-fades on switch.
- Blue is branding, never text. On the iPhone's sheets (Settings, New Space) the tint is ink, so no words are Glacier; only switches, the cursor, and a choice's check take it (David, 2026-11-23: tinted text is hard to read). Sand never carries text. Buttons are ink. Shadows are warm brown, never grey.
- Glacier stays #7F9CB0 / #6E98B2; no darker "contrast-fixed" versions. The one exception is the system accent (switches, radio buttons, selection, focus rings): a slightly more saturated Glacier, #689ABB light and #5F98BB dark, so controls don't look washed out (David, 2026-10-24). Buttons stay ink, alerts' main buttons on the iPhone included (dark mode: muted #5E564E, since iOS writes their label in white); switches and the other system controls stay Glacier (David, 2026-11-14).

**Brand font: Gooper Deck** (David, 2026-11-13: Fraunces is no more). Brand moments only, the same rule as before. Licensed: it lives in the git-ignored `PrivateFonts/`, is copied in by a build step when present, and is never committed (the repo is public). Emphasis is weight (Regular, then SemiBold), never color. Everything else, reader mode included, is Apple's system fonts. Panel titles (Settings, History, and sheets) are SF semibold, Mac and iPhone; without Gooper Deck (a fresh clone) the welcome falls back to the system serif. Fraunces is out of the app (2026-11-14).

**Logo and icons:** use only the final files from the brand kit (`brand/`). Never redraw or re-type the logo or wordmark. The app icon is the glacier tile; on macOS 26 it's the `Firn.icon` from Icon Composer.

### Frost (the welcome and the "no tabs" screen)

Firn's brand moments use "Frost" (David, 2026-11-24; it replaced Sunrise): a frosted window on a snowy morning, everything outside soft and out of focus. The approved designs are in `docs/design/frost` (start with its README; its BRAND.md has every value), the scene is `Shared/Frost.swift`, and the plan is in `docs/HISTORY.md` ("Plan: Frost"). Built on the Mac; on the iPhone and iPad "no tabs" is built (2026-11-25; not yet on David's iPhone), and the welcome too (steps 1 to 5 done; David hasn't judged it yet). Sunrise's code is gone.

- **Where:** only the welcome and "no tabs." Never everyday browsing, Settings, Lookout, the command bar, menus, downloads, or scam warnings. Everyday screens are plain warm paper.
- **The sky:** one plain gradient, with a faint warm horizon along the bottom in light mode only. Dark is "blue hour," and the logo on it is always cream.
- **Hello** is the logo out of focus; **the steps** are the plain sky, a question on the left and its choices on the right, with one glass pill; **"Welcome in."** is the logo in focus. **No lens in the apps:** it's the website's landing page's alone (David).
- **"No tabs"** is one very large blurred flake in the space's color, the one place the logo takes it. No words.
- **The finish** runs about 3.4s, unhurried: the fog lifts, the words hold a moment, the window glides up over them (David's speeds, 2026-11-25). Reduce Motion: a plain 300ms fade.
- The tab switcher's space wash (the iPhone's overview) is its own thing, unchanged.
- **Performance (required):** the blur is always a ready-made picture, never a live blur; nothing moves or redraws while idle; no snow in the app; everything moving is off with Reduce Motion.

---

## How spaces work

Each space is its own browser. This is the heart of the new Firn; get it right before polishing anything else.

- **Always the space's own:** Basecamp tiles, groups, loose tabs, and the Archived group. Nothing in the sidebar is shared between spaces.
- **Separate by default:** each new space has its own sign-ins, cookies, site data, history, and saved passwords. Signing into Gmail in Work doesn't sign you into Personal.
- **Sharing is one choice, made when creating a space:** "Keep this space separate" (the default, recommended) or "Share sign-ins with [another space]." Sharing joins that space's sign-ins, cookies, site data, history, and saved passwords. The new space still gets its own empty Basecamp, groups, and tabs.
- **Plain words in the "New space" sheet:** a separate space says it starts signed out of everything; a shared one says which space it shares with.
- **Later changes:** a shared space can "Stop sharing" (it starts fresh and signed out, after a confirmation). Two separate spaces can't be merged.
- **Deleting a space** deletes its tabs and its browser data, after a confirmation that says so. Shared data stays as long as another space still uses it.
- **Nothing leaks between separate spaces:** the command bar, address suggestions, history, and Lookout use only the current space's data.
- **Links from other apps** open in the space used last.

---

## Features (build in the roadmap's order)

- **Vertical tabs:** favicon and title; close button on hover; drag to reorder with rows gliding into place; sidebar collapses and peeks at the left edge.
- **Basecamp:** the grid of everyday sites at the top of each space (up to 12), different in every space. Tiles remember their home address; ⌘W lets one rest until clicked, and Close in its menu removes it (⇧⌘T brings it back); "Go back to home" resets it.
- **Groups** (replace pins; David, 2026-10-18): the way to keep tabs. Two tiers in one clean sidebar, top to bottom: the address bar, Basecamp tiles, then the tab list (groups and loose tabs in one order). No divider line: the groups' frosted cards already set what's kept apart from loose tabs.
  - A group is a name and a flat set of tabs (no nesting), shown as a soft frosted card, the same frost as the Basecamp tiles (David, 2026-10-22): the name, lined up over the tabs' icons, and a fold arrow just after it; no dot (David, 2026-10-22) and no count, even folded (David, 2026-10-18). Folded, it's a tab row's height, and cards sit the same 4pt apart as tabs (David, 2026-10-22). No emoji or custom icons, no indenting: the card already sets the tabs apart.
  - **New tabs go at the top or the bottom** (David, 2026-10-19): one setting, "Bottom" by default. The New tab button sits there too (just below Basecamp, or below every tab), so you can see where tabs will appear. Ungrouping leaves tabs right where the group was, and a tab taken out of a group lands just below it (David, 2026-10-19). Groups and loose tabs share one order, so a group can sit anywhere: new tabs at the top push groups down. A new group appears where its tab already was (the tab doesn't move); drag groups anywhere, drag tabs between them, and drag a tab out of its card to take it out. A group of one is fine; closing its last tab ends it.
  - Make one by dragging a tab onto another, or right-click a tab: "New group with this tab." Right-click a group: Rename, Ungroup, and Close group. A close button shows only while the pointer is on the group's name line; ⇧⌘T brings a closed group back whole, with all its tabs (once ⇧⌘T exists).
  - Grouped tabs are ordinary tabs: no home address, closing one really closes it (⇧⌘T brings it back), and they never archive. Links from a grouped tab open inside its group, right below it, as in Dia (David, 2026-10-19). A link from a loose tab makes a group of the two, in the loose tab's place (David, 2026-11-06). Such a group tidies away like loose tabs until it's renamed or a tab is put in it by hand, and until then it ends when it's down to one tab, leaving that tab loose where it is, its card going as Ungroup's does (David, 2026-11-13; built, not yet checked by David).
  - **Auto names** (David, 2026-11-06): every new group is named by Apple's on-device model from its tabs' titles and sites, on macOS 26 and iOS 26 with Apple Intelligence (otherwise "New Group"). Always on, no setting; Rename changes it. Nothing leaves the device. **Wanted, not built** (David, 2026-11-13): the name keeps updating as tabs join the group, as in Dia, until the person renames it; after a rename it never changes again. Planned (David, 2026-11-13; three steps in `docs/HISTORY.md`): a tab joining or leaving asks again, with the current name as a hint; existing groups count as named by hand. Step 1, FirnCore, done (2026-11-13): names now update as tabs join and leave; step 2, the fade in both apps, built (2026-11-13); step 3, a look over, built (2026-11-13); neither yet checked by David.
- **Spaces:** name, color, and their own browser data (see "How spaces work"); no icons (David, 2026-10-25). The bottom row shows the space on screen's name, centered and in ink, with a dot per space under it (this one's in its color; David, 2026-11-25, as on the iPhone); clicking the name opens a native menu of spaces (checked, with ⌃1–9), New Space…, and Space Settings… (a Spaces section in Settings). Shortcuts switch too; the tint cross-fades.
- **Tidied away** (David, 2026-10-20; replaces "Archived" and the "Drifted tabs" group; "drifted" in code only): loose tabs not looked at for a while (7 days of using Firn by default; 1 day, 30 days, or Never in Settings) are tidied away. Never tidied: Basecamp tiles, grouped tabs (except groups a link made, until kept by hand), the tab on screen, a tab playing sound, and a tab in split view. Count days Firn was used, not calendar days.
  - **The moment** (like Dia's, in Firn's language): when Firn comes back to the front, after a beat, idle rows fade in place one after another while each site icon drifts down into the overflow button. The button frosts over in the space's color, widens to "Tidied away 4 tabs", holds, and thaws back; a dot in the space's color stays until the overflow is opened. Reduce Motion: rows and pill fade. No section in the tab list.
  - **The overflow:** one small button in the sidebar's bottom row (Firn's archive box) (with the spaces; no more top-row buttons), there only while it holds tidied tabs (David, 2026-10-23): it fades in as the first are tidied, just before their icons fall in, and out once the last is gone. Its native popover holds only the space's Tidied away tabs; Recently closed lives in File › Reopen Closed Tab and the command bar, and History will get its own place (its own step). Click one to bring it back where new tabs go.
- **Downloads:** a button at the right of the bottom row, there only while the space has downloads; its popover opens as one starts (2026-10-23).
  - Tidied tabs are deleted 30 calendar days after they're tidied (as in Dia; David, 2026-10-20), or when closed. Only this cutoff uses calendar days.
- **Lookout:** a link preview in a floating rounded panel over the page with a dimmed backdrop; Esc or clicking outside closes it; one button turns it into a tab (at the top of the loose tabs). Links clicked in a Basecamp tile should open as a Lookout first, so you glance before keeping (David, 2026-10-18); until Lookout exists they open where new tabs go.
- **Split view:** two pages side by side, each with its own address and back/forward; drag the gap to resize; one row in the sidebar. Made by dragging a tab onto the page (the tab on screen too: a blank half opens beside it, as Open as Split) or from a tab's or tile's right-click; a Basecamp tile is copied into the tab list, never moved (David, 2026-10-21).
- **Command bar:** ⌘T opens a floating bar, Zen style, and no tab exists until you pick something (decided, David, 2026-10-23). The bar: type an address, search, jump to an open tab in this space, or run an action by name.
- **Later, as on Electron:** sleeping tabs, sound and the mini player, downloads, find in page, zoom, permissions, saved passwords, ad and tracker blocking, and scam warnings.
- **Later, new ideas (each its own step, ask first):**
  - **Reader and Summarize** (built, Mac and iPhone; David checked both on his iPhone, 2026-11-16; the Mac not yet checked): a calm, text-only view of an article, using Mozilla's Readability.js 0.6.0 (approved; bundled in FirnCore, run in Firn's world on a copy of the page, its HTML rebuilt from an allowlist). ⇧⌘R on the Mac; on the iPhone the way in is Safari's: the book takes •••'s place on articles, "Reader available" for a moment, and Show Reader first in the page menu. Summarize: Reader only, only when asked, a few calm sentences at the top (as Safari's, not points; David), on Apple's on-device model, the article fenced as data. Designs: `docs/reader-design.html` and `docs/summarize-design.html`; test page `docs/reader-test.html`. Open: Reader comes down from the top on the iPhone (`docs/HISTORY.md`, "Plan: Reader comes down from the top"; step 3, the look over, is next).
  - **Back and skip in the mini player:** left out for now (David, 2026-10-23: maybe unnecessary; play and pause first). Investigated: a site's own previous and next (Media Session) can't be reached from Firn's world, only by a small script in the page's own world, an exception to the content-world rule that David would have to approve.
  - **Import passwords** from the export file other browsers and password managers make, then offer to delete that file (it holds every password as plain text). Opus.
  - **Saved passwords, then imports from Arc** (David, 2026-10-24: passwords are a must): plan saved passwords first, then CSV import, then Arc's sidebar (spaces, favorites as Basecamp, pinned as groups). Research in `docs/HISTORY.md`. Opus.
  - **Move a tab to another space** (David, 2026-10-19: wanted, but not in Phase 4). Between separate spaces the tab reloads with the other space's sign-ins, so the menu should say that plainly.
  - **Extensions:** look into how Orion (Kagi's browser, Mac native on WebKit) runs Chrome and Firefox extensions: what it built on top of `WKWebExtension` or before it, what works, and what doesn't (David, 2026-10-23). Research so far is in `docs/HISTORY.md` ("Research: extensions"). Opus. **Decided (David, 2026-11-13, dwurgy/firn#85):** Safari extensions people install from the App Store, loaded with `WKWebExtension(appExtensionBundle:)`, plus a short list in Settings of the ones tested; never Firefox's or Chrome's stores (Firn never downloads or updates others' code). Max (maxmeis) is reworking his draft dwurgy/firn#83 around it: each extension's Safari ID, and WebKit passing native messages to the extension's own app (its default), to see whether 1Password for Safari signs in and unlocks with Touch ID. Unknown: whether sandboxed Firn can find and load other apps' extensions, and whether their native parts run with Firn as the host.
  - **Zen and Dia import:** research first (David, 2026-10-24). Zen keeps compressed session files in a profile folder named differently on each Mac; Dia: researched (2026-11-14, `docs/HISTORY.md`): its tab list is encrypted, so only profiles and open tabs could come over, not pinned tabs; skipped for now (David). Not Chrome or Safari (no spaces to map). Opus.
  - **Translate a page** (planned, David, 2026-11-27; seven steps in `docs/HISTORY.md`, "Plan: translating pages"): whole pages, Mac first, on the device with Apple's Translation framework; offered only when the page's language isn't one of the device's. Step 1 done (2026-11-27): macOS and iOS 26.4+ only (David), so links stay in place; the design (`docs/translate-design.html`, approved) has a mark beside the book on the Mac (hidden in Reader) and only a menu row on the iPhone (David); the tab's title translates too (David). Step 2 done (2026-11-27): FirnCore reads and writes the page (`Translate/PageText`). Step 3 done (2026-11-27): the translator (`Translate/PageTranslation`). Step 4, the Mac, built (2026-11-27; not yet checked by David). Next: step 5, the look over.
  - **Where a tab came from:** a new tab opened from a link quietly shows which tab it came from (leaning toward a hover echo in the space's color), without a tree, indenting, or extra menus.

Keyboard shortcuts match the Mac version of the Electron app unless David decides otherwise.

---

## Architecture

- **Platforms:** macOS 14+ now; iOS 17+ later (both needed for separate website data per space). Swift 6 language mode with strict concurrency; SwiftUI.
- **Project shape:** a thin Xcode app target (`Firn.app`, for signing, entitlements, Info.plist, and the icon) plus a local Swift package (`FirnCore`) holding the logic, so most code builds and tests from the command line and can later be shared with an iOS target. If the Xcode project file becomes a pain to edit, propose XcodeGen and ask first.
- **Engine:** `WKWebView`, wrapped with `NSViewRepresentable` (and `UIViewRepresentable` on iOS). On macOS 26 and later, SwiftUI's own `WebView`/`WebPage` may replace the wrapper; decide that as its own step.
- **Engine layer:** two rules, as on Electron:
  1. Views never talk to `WKWebView` directly; they talk to a small `BrowserEngine` / `PageController` protocol.
  2. App logic (tabs, spaces, Basecamp, groups, archive, session) never touches WebKit; only the engine's implementation does. Each tab owns its controller; the model owns no views.
- **Per-space data:** each space has a `dataStoreId`. Separate spaces get a new one; a shared space uses the same id as the space it shares with. Every web view in a space, including Lookout and split view, uses `WKWebsiteDataStore(forIdentifier: dataStoreId)`, never `.default()`. Firn's own history and saved passwords are stored per `dataStoreId` too. Deleting the last space that uses an id removes its store (`WKWebsiteDataStore.remove(forIdentifier:)`).
- **State:** one observable store (`@Observable`) for the tab model, saved to disk as Codable JSON in Application Support so sessions survive restarts. Keep it sync-ready (stable ids, a last-changed time on every record), but no sync now.

### Core data model (get this right first)

```
Space      { id, name, color, order, dataStoreId }
Tab        { id, spaceId, url, title, favicon,
             place (basecamp, open, or archived), groupId?,
             homeUrl? (Basecamp only), order, lastActiveAt, openerTabId?, splitGroupId? }
TabGroup   { id, spaceId, name, order, folded }
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
- **Ad and tracker blocking** (later): WebKit content rule lists compiled from the public lists; check rule limits per list. **Scam warnings:** on, through WebKit's Deceptive Website Warning (macOS's Safe Browsing service, via one sandbox exception for `com.apple.Safari.SafeBrowsing.Service`). It's Apple's look; a Firn-styled warning would be its own design.
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
- Tab folders: groups stay flat, never nested.
- Pins: groups do their job (David, 2026-10-18).
- More layouts than the two looks.

---

## Open questions (David hasn't decided; don't build these)

- **Firn's own frost everywhere:** one frosted glass of Firn's own (flat and icy, not bubbly; looks native, like nothing else), replacing stock Liquid Glass on the address bars, the command bar, the overview's bars, and more, on Mac and iPhone; system menus may keep stock glass (David, 2026-11-08). The idea is in `docs/IOS-PLAN.md`; its own plan first, on Opus, after the iPhone's glass groups. Since then (David, 2026-11-17) the iPhone's bars went the other way: iOS's own glass, "Frosty, no tint" (the thinnest blur under regular Liquid Glass); then the Mac too (David, 2026-11-18): tiles, group cards, and every `FrostGlass` on native glass from macOS 26, Firn's frost before it (`docs/HISTORY.md`, "Plan: the Mac on native glass"; steps 1 and 2 built, not yet checked by David).

- **Small on-device AI touches:** quiet, optional helpers that use Apple's on-device model (the Foundation Models framework, macOS 26 and later with Apple Intelligence), such as a "Summarize" in Lookout or reader, and automatic names for groups (decided and planned, David, 2026-11-06: always on, see Groups). Everything runs on the Mac: no cloud service, no account, no network traffic, so "your data stays on your device" stays literally true. They must be optional and simply absent on macOS 14 and 15 or when Apple Intelligence is off. No chat panel and no sidebar assistant; if it isn't quiet, it doesn't fit. If David decides to try one, it's its own step with a plan first, on Opus.
- **iCloud sync: decided** (David, 2026-11-13); see "Where we are" and `docs/SYNC-PLAN.md`.
- **Dark mode a little darker: decided** (David, 2026-11-15): frame #28241F, page #1C1916, held tile #332E29 (option B in `docs/dark-mode-design.html`); the old frame let a space's tint grey it out. Then on the iPhone, in dark: the card pills #4E4843, the bars' frost the frame at 40%, the hold menu #38332E, and the hold menu's corners 22pt (rows 18pt); David checked it on his iPhone (2026-11-15). The Mac not yet checked. The brand moments and `brand/` keep the site's values.

---

## Roadmap

Each phase has a "done" test. Don't start the next until the current one passes.

1. **Window that browses:** a native window, one `WKWebView`, address bar, back, forward, and reload. *Done:* David browses normally in it for 10 minutes.
2. **Sidebar and vertical tabs:** tab model, sidebar, new, close, switch, and reorder; tokens applied. *Done:* it already looks calm and feels smoother than the Electron app.
3. **Basecamp, groups, and persistence:** *Done:* quit and reopen; everything comes back exactly as it was.
4. **Spaces, truly separate:** create, switch, color, and delete spaces, each with its own data store and Basecamp, plus the "share sign-ins" choice. *Done:* two spaces signed into two different Google accounts at once, and a shared space that's already signed in.
5. **Archived, Lookout, split view, and the command bar:** *Done:* used daily without reaching for another browser.
6. **First light and the two looks:** the welcome, the empty page, and the address bar setting.
7. **Decision: made** (2026-10-22). This code takes over Firn. The move into `dwurgy/firn` is done (2026-10-23). Next: privacy features, signing and notarization, updates, and iOS.

### Taking over from the Electron app

Each is its own step, planned with David, on Opus.

- **Existing users: done.** The Electron app's last release announced the end of support; its code is in `dwurgy/firn-legacy`.
- **The move: done** (2026-10-23). The native history was joined onto `dwurgy/firn`'s (one merge, no force push), so the Electron releases and tags still work. `dwurgy/firn-swift-test` is retired.
- **Their data: not moved** (David, 2026-10-26: 1.0 starts fresh). The Electron app keeps tabs, spaces, history, and passwords in `~/Library/Application Support/Firn`. A sandboxed app can't read that folder on its own, so moving people's tabs and spaces over needs a deliberate import. Passwords need extra care. Electron's shared Basecamp has to become per-space Basecamps (probably copied into each space).
- **Same identity: done** (2026-10-24). Bundle ID `com.firnbrowser.firn` (Electron's was Forge's default, likely `com.electron.firn`, so the two are separate apps), version 1.0.0 (Electron was 0.x), signed with David's Developer ID (team 72LHR8K4P5), the Electron app's team.
- **Public copy.** The README, the website, and "a calm browser for everyone" all assume Windows. David decides how to say it.

### Where we are

Only what's open lives here. The full step-by-step log up to 2026-11-23 is in `docs/HISTORY.md` ("Where we were"); plans and their progress are in `docs/IOS-PLAN.md`, `docs/SYNC-PLAN.md`, and `docs/HISTORY.md`. Keep this section short: when something is finished and checked, take it out; details go in the plan it belongs to.

- **The Mac: 1.1.1 is out** (2026-11-25, build 6; the iPhone's notes are in `CHANGELOG-iOS.md`). Phases 1 to 6 are done except the "At the top" look (waiting) and Phase 5's daily-use test. Saved passwords, CSV and Arc import, notarization, Sparkle updates, History, spaces without icons, the ⌃Tab switcher, demo mode (`--demo`, `scripts/demo-shots.sh`), and ad and tracker blocking are finished. Releasing: `docs/RELEASING.md`.
  - **Waiting on Apple:** passkeys (entitlement requested 2026-10-26; then a new provisioning profile).
  - **Open bugs:** page corners vs. the window's on macOS 26 (Noah; `docs/HISTORY.md`, "Bug reports after 1.0"). Swipe back/forward never tested on a trackpad.
  - **Built, not yet checked by David on the Mac:** the welcome's steps and "no tabs" on Frost (the finish's speed is David's pick; VoiceOver, keyboard, Reduce Motion, and macOS 14 and 15 not checked), link-made groups ending at one tab, group names updating as tabs join, Reader and Summarize, native glass on tiles, group cards, and `FrostGlass` (fine from demo shots), the darker dark mode, http-only sites ("Not Secure", Continue Without a Secure Connection), Settings › Sync, Send to My iPhone, and Help › Send Feedback….
- **iCloud sync** (`docs/SYNC-PLAN.md`): spaces sync (step 3 done, two-device test passed). Groups and tabs don't sync (step 4 dropped, David, 2026-11-16). Step 5 ("On your Mac" in the command bar) and step 6 (Send to My Mac / Send to My iPhone) are built, untried against iCloud. Step 6 part 3(b), the three menus rearranged, is built (2026-11-23; on David's iPhone, Paste and Go works; the rest not yet judged). Next: (c), the two-device test (`Device` and `SentTab` are in Production, 2026-11-25). Later: step 8, Basecamp Mac to Mac. Held until the iPhone app is out: an iCloud sync step in the welcome (David, 2026-11-24).
- **The iPhone (`docs/IOS-PLAN.md`): 1.0.0 is out (2026-11-25), iPhone and iPad together** (David, 2026-11-24, replacing 2026-11-23's "iPhone only": a quick look over of the iPad and the iPhone Duo's open screen before submitting, refined later; Apple doesn't let an app drop iPad support once released with it). Device family switched and a quick look over done in the Simulator (2026-11-24; `docs/IOS-PLAN.md`, "The iPad and Duo look over"): nothing broken; Phase 7 (the iPad's sidebar and split view) isn't built, so the iPad ships as the iPhone's layout, wider. Raw iPad captures (2064 × 2752) are in `docs/app-store/ipad/plain` (git-ignored).
  - **On the App Store: 1.0.0, build 4** (approved and released 2026-11-25; commit `289ebde`; apps.apple.com/app/firn-browser/id6829053602). **No new iPhone builds until David says** (a few days, gathering fixes); the next build is 5 (App Store Connect, never TestFlight Internal Only). Waiting for it on `main`: Reader both ways and waiting for its article, and Reader no longer blank after a quick tab switch. Not known to have been run: the two-device test for sending tabs. The listing's words: `docs/app-store-listing.md`. A real iPad or Duo has never run it (Simulator only). The Duo pass is done in the Simulator (2026-11-25; `docs/IOS-PLAN.md`, "The Duo pass"). The privacy manifest is built (`Firn iOS/PrivacyInfo.xcprivacy`): code that starts reading file dates or free disk space adds its reason there first.
  - **In progress, opening and closing tabs and tiles as Safari's** ("Plan: opening and closing tabs and tiles as Safari's", and "Plan: the held page's size, the side tabs, and a let-go that carries the finger"): steps 1 to 5 done; the let-go on a spring, part 1 (a tab into its card), built on Firn's own frame clock (`Flight`, `FlightClock`, `Follower`), David: "feels pretty good". Left: the tap's own late frame, the other six differences listed under step 3, part 2 (the let-go back to the page and onto a side tab), a darker blur by eye, the page's sideways travel, then step 6, tiles (they glide at a lower frame rate than tabs).
  - **The drag polish: done but for David's look at step 6** (`docs/IOS-PLAN.md`, "Plan: the drag polish"). Steps 1 to 5 hold on David's iPhone (2026-11-24: tabs, tiles, and a dropped tab's landing "feels good"). Step 6 built (2026-11-24): Firn's own hold menu, hold-to-drag, and SwiftUI drag are out (about 2,570 lines), and iOS 26 now runs the same grid as iOS 27 (David: 1.0 keeps iOS 26); checked in the Simulator on iOS 26 and 27. Reduce Motion and VoiceOver checked and fixed in the Simulator (2026-11-24: tab cards had no name, the page's bar stayed reachable behind the overview); VoiceOver on a real iPhone not run. A carried group now lands solid and then opens (not yet on David's iPhone). On the Mac, six `.accessibilityHidden(condition)` likely have the same un-hiding bug.
  - **Tidying away on the iPhone** (`docs/IOS-PLAN.md`, "Plan: tidying away"; David picked "Sink into pill", 2026-11-25): the space's pill is the box, Tidied Away in its menu only while needed. Steps 1 to 3 built and checked in the Simulator; not yet on David's iPhone. Step 4, the look over, is next. The setting and days of use are each device's own.
  - **Known, left alone:** a page sometimes wakes a little zoomed in: WebKit saves a pinch in the tab's place (2026-11-24; `docs/IOS-PLAN.md`, "A page sometimes sits a little zoomed in").
  - **Other open plans:** the address bar's shrink (section 11; piece 2, `BarFollow`, not yet judged beside Safari); iOS's own glass buttons (step 5, the look over on his iPhone); Basecamp tiles on iOS's glass (step 2, motion); tiles opening like an app (2k; step 3 built); Find on Page (step 3); Reader comes down from the top (step 4: both ways, both apps, 0.4s, built 2026-11-25; not yet judged by David); the swipe up's performance (2i: measure steps 3 and 4 with a cable, then step 5).
  - **Built, not yet judged on David's iPhone:** the space name growing into its menu (section 8), New Space and Downloads as iOS's own sheets (section 9), the next space under the finger with Reduce Motion, three spaces, and groups (section 10), search suggestions and the Settings rows, Send Feedback, pages sized to one screen (`svh`), Send to My Mac, the error page, site alerts, and folded groups in dark.
  - **Decided, keep in mind:** the grid is the only overview; the iPhone's glass is iOS's own at "Frosty, no tint" (`FirnGlass`, `GlassFrame`); iOS's own menus and drag on iOS 26 and 27 alike (one grid, no split); no site icon under grid cards; builds for David's iPhone are Release; the `Firn iOS` scheme archives the TestFlight configuration and App Store builds archive Release.

---

## How to work on this project (instructions for Claude)

- **Only work in `dwurgy/firn`** (this folder, still named `firn-swift-test` on David's Mac). Both apps live and release from `main` (David, 2026-11-27; `ios` was merged in and is retired). The Electron app (`dwurgy/firn-legacy`) and the website (`dwurgy/firn-site`) have their own sessions. Never attach, clone, or change another repository, including `dwurgy/firn-legacy` and the retired `dwurgy/firn-swift-test`. You may describe how the Electron app does something only if David pastes it in.
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
  - **Say when a step isn't worth testing** (David, 2026-11-20). When steps are links of one thing that can only be judged whole (one motion, say), say so up front, do them in a row, and ask David to test once at the end; testing between them is chasing ghosts. Say too whether to /clear between them.
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

Firn's code is open source under the Mozilla Public License 2.0. **The Firn name, logo, and app icons are not covered by the license** (`brand/` and the app icon).
