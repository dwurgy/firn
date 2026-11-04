# Firn for iPhone and iPad: the plan

Draft for David's review (2026-11-03, branch `ios`). Nothing is built yet. Read with `CLAUDE.md` and `docs/IOS-BRIEF.md`.

## The short version

- One Xcode project, two app targets: the Mac app (`Firn`, unchanged) and a new `Firn iOS` (iPhone and iPad together, one app).
- Both use the same `FirnCore` package: tabs, spaces, groups, Basecamp, tidying, history, passwords, blocking, the command bar's results, and the engine layer. The iOS app gets its own views, because the brief asks for iOS's ways, not the Mac's layout.
- The Mac app's behavior doesn't change in any phase before sync. Every shared change is an addition (a new iOS-only file, or an `#if os(iOS)` branch next to Mac code that stays exactly as it is).
- Ten small phases, each with a test you can do on your iPhone (iPad steps work in the Simulator if you don't have one). Sync is phase 9, with its own plan, and it's the first phase that has to touch the Mac app, so it needs your explicit OK.
- No new network traffic and no data collection before sync. The iOS app sends exactly what the Mac app already sends: the pages you visit, search suggestions (as on the Mac), and the welcome's site icons.

---

## 1. How the iPhone and iPad app fits into the project

### What I checked

- `FirnCore/Package.swift` already lists iOS 17 as a platform, and most of FirnCore already compiles for iOS.
- I tried building FirnCore for the iOS Simulator (nothing changed, nothing committed). It fails only in `Engine/WebKitPageController.swift`: printing, the page's right-click menu, giving the page keyboard focus, and turning a snapshot into a picture use Mac-only parts of Apple's frameworks. `Engine/PageView.swift` is Mac-only on purpose (it's wrapped in `#if os(macOS)`).
- The model, history (SQLite), saved passwords (Keychain), ad blocking, address handling, and the command bar's results all compile for iOS as they are.

### Shared (one copy, used by both apps)

| Shared | Where it lives today | Notes |
| --- | --- | --- |
| Tabs, spaces, groups, Basecamp, split groups, tidying, session saving | `FirnCore/Model` (`BrowserStore`, `Tab`, `Space`, `Session`…) | Same rules, same file format. iOS keeps its own `session.json` in its own container. |
| Per-space data stores (`dataStoreID`) | `FirnCore/Engine/DataStores.swift` | `WKWebsiteDataStore(forIdentifier:)` exists on iOS 17, so separate spaces work the same way. |
| Engine layer (`PageController`, `WebKitPageController`) | `FirnCore/Engine` | Needs iOS branches (see section 2). |
| Address handling, search engines, suggestions | `FirnCore/Address` | Unchanged. |
| History | `FirnCore/History` | Unchanged; one SQLite file per data store, as on the Mac. |
| Saved passwords | `FirnCore/Passwords` | The store works on iOS; the fill list is a new iOS view. |
| Ad and tracker blocking, scam warnings | `FirnCore/Blocking`, WebKit settings | WebKit's content rules work on iOS with the same limits. |
| Command bar results | `FirnCore/Model/CommandBar.swift` | The bar itself is a new iOS view. |
| Basecamp's balanced rows | `FirnCore/Model/BasecampLayout.swift` | Already does what the brief's table asks (I checked every row); only needs "up to 6 across" for iPad. |
| Colors, Fraunces, First light | `Firn/Theme.swift`, `Firn/FirstLight.swift`, `Firn/Fonts` (Mac app) | Move to a `Shared/` folder both apps build (section 2). |

### New for iOS (only in the iOS app)

- The app's entry point and its one window (iPad: one window at first; see section 5).
- The page with the bottom address bar, then the shrinking pill (its own step and plan).
- The tab overview: one column, two columns, tall cards and slim rows, pinch, long-press drag.
- The iPad's roomy sidebar and split view.
- The command bar's iOS look (over the dimmed page, above the keyboard, swipe down to cancel).
- Long-press menus (Add to Basecamp, New group with this tab…), iOS's link preview for Lookout.
- Space switching in the overview, the space sheet, Settings (iOS style: a list, not the Mac's sidebar).
- The password fill list, downloads to Files, find in page, the welcome.
- `PageView` for iOS (`UIViewRepresentable`), in its own new file.
- Its own `Info.plist`, entitlements, and icon (from `brand/`; Icon Composer's `Firn.icon` works for iOS too).

### Not on iOS

- Sparkle and "Check for Updates…" (the App Store updates it), Arc import, the demo-shot scripts, the ⌃Tab switcher (the overview does that job), the Mac menu bar, full-screen work, the mini player at first (needs background audio; later).

---

## 2. Mac code that has to change, and how it stays the same for the Mac

Rule for every one of these: the Mac's code lines stay as they are. iOS gets a new branch or a new file beside them.

1. **`WebKitPageController.swift` builds for iOS.** Wrap the four Mac-only spots (print, the right-click menu, focus, snapshot) in `#if os(macOS)`, and put the iOS versions in a new file, `WebKitPageController+iOS.swift`. The Mac lines inside the `#if` don't change; only `#if`/`#endif` lines are added around them.
2. **`PageView` for iOS** goes in a new file, `PageView+iOS.swift`. `PageView.swift` isn't touched.
3. **Page scrolling for the shrinking bar.** Views never talk to `WKWebView` (the engine rule), so the bar needs a small iOS-only protocol (for example, `PageScrolling`) that only the iOS side implements. The shared `PageController` protocol doesn't grow, so the Mac doesn't have to implement anything new.
4. **`BasecampLayout`** gets the column limit and minimum width as settings, with today's Mac values (4 across, 52pt) as the defaults. The Mac calls it exactly as now. The brief's table becomes a test.
5. **Colors, Fraunces, First light.** `Theme.swift`, the Fraunces helper, and `FirstLight.swift` move into `Shared/`, built by both apps. Their few `NSColor`/`NSImage` uses get an iOS twin behind `#if os(iOS)`. The Mac build includes the same code it does today, from a new folder.
6. **The Xcode project** gets a new target and a new scheme (`Firn iOS`). The `Firn` target's settings, the `Firn` scheme, and `scripts/release.sh` aren't touched.

**How we prove the Mac is untouched, at every commit on this branch:**

- The Mac app builds, and FirnCore's tests pass on macOS, as before.
- FirnCore's tests also run on the iOS Simulator.
- `git diff main -- Firn/` is empty, except the files moved to `Shared/` (checked line by line: only `#if` additions).
- You open the Mac Firn built from this branch and use it for a minute: nothing looks or acts differently.

**Branches.** Mac fixes keep happening on `main` in their own sessions. The `ios` branch takes `main` in regularly. I'd suggest merging phase 0's small FirnCore changes into `main` early (after your check), so later Mac fixes to the engine don't collide with them. Nothing else from `ios` goes to `main` until you decide.

---

## 3. Phases

Each phase has a "done" test you can do yourself. Like the Mac roadmap: don't start the next until the current one passes. Each phase is a few small, committed steps, planned in detail when we get there. All on Opus (they're SwiftUI, engine, or architecture work), except wording steps.

You'll install each build on your iPhone from Xcode (your iPhone needs Developer Mode on once; I'll walk you through it in phase 1).

### Phase 0: Groundwork (no iOS app yet)

FirnCore builds and passes its tests for iOS (section 2, items 1, 2, and 4), and the shared folder exists (item 5). `Package.swift`'s iOS line moves from 17 to 26 (the Mac line stays at 14).
**Done:** FirnCore's tests pass on the iPhone Simulator; the Mac app built from `ios` looks and works exactly as it does today (open it, browse, switch spaces, open Settings).

### Phase 1: A window that browses

The `Firn iOS` target; one tab; the address bar fixed at the bottom (full size, no shrinking yet); back and forward by swiping from the edge; reload; typed addresses and search, as on the Mac. One space, using its own data store (never the default one).
**Done:** you browse normally on your iPhone for 10 minutes, rotate it, use the keyboard, and swipe back and forward. *Passed* (2026-11-03): David checked light, dark, Reduce Motion, VoiceOver, and the done test on his iPhone.

Steps (written down 2026-11-03):
1. **The target** (done 2026-11-03): `Firn iOS`, iPhone and iPad, iOS 26, opening to an empty page.
2. **The page, in its own data store** (built 2026-11-03; checked in the Simulator: browse, swipe back, rotate, restart): `PageView+iOS.swift` in FirnCore (edge to edge, swipe back and forward); the app runs a `BrowserStore` with one space and saves its session in its own container; a plain field at the bottom takes an address or a search, as on the Mac. *Test:* in the iPhone Simulator, type an address, browse, swipe from the left edge to go back, rotate.
3. **The bottom address bar** (built 2026-11-03; checked in the Simulator: type and Go, search, Back and Forward, tapping out, restart, dark): `Firn iOS/AddressBar.swift`. Liquid Glass tinted with the space's color, bare like Safari's (David, 2026-11-03; a layer of the page color at 72% inside had made it look nearly solid). Back and forward in a small pill (they fade when they can't go, so nothing shifts), the address capsule beside it with reload, or stop while loading, and the Mac's loading frost (`LoadingFrost.swift`, a copy). The page runs edge to edge under the bar (`obscuredContentInsets`, so a page's end and fixed footers clear it). At rest the field is a button showing the committed site; a tap opens it with the whole address selected (tapping the text itself dropped a cursor mid-address), the pill steps aside, the bar rides up with the keyboard, the page dims, and a tap on the page cancels. A page's own fields leave the bar behind the keyboard. Tried and dropped: iOS's scroll edge effect under the bar (WebKit's scroll view didn't show it).
   *Known (2026-11-03):* in the Simulator, scrolling Wikipedia with a Mac mouse and then clicking crashed once inside UIKit (`-[UIGestureRecognizer _delayTouchesForEvent:inPhase:]`, "insertObject:atIndex: object cannot be nil"); Xcode's debugger made it look frozen. Firn's code isn't in the stack and adds no gesture recognizers; touch swipes didn't repeat it. The same crash is reported on iOS 18 with no fix (Apple Developer Forums thread 764352). Watch for it on a real iPhone in step 4, and with a trackpad on iPad (phase 7). In step 3 the Simulator tool's taps set it off on every first tap on the page after a launch (iOS 27.0 Simulator, Xcode 27.0), with step 2's build too; taps on Firn's own bar never did. On David's iPhone 15 Pro (2026-11-03) tapping links didn't crash at first, but scrolling did, the same way: it wasn't the Simulator's. **Found and fixed (2026-11-03, step 4):** a `WKWebView` made while iOS is still starting the app (in the `App`'s `init`, where restoring the session made the page) gets its touch handling wired wrong, and its first few scrolls or taps crash. Shown by a bare web view: made when shown, it never crashed; made in `init`, it crashed like Firn; made a moment after launch, it didn't. Ruled out on the way: the bar, `PageHolder`, restoring page history, blocking, the watchers, the UI delegate, the inspector, the data store, and the user agent. The fix: `FirnIOSApp` makes the browser (`Browser`: store and saver) when the screen first appears. Rule for later phases: never make a web view before the app is running. **The pill's glide smoothed (2026-11-03, from David's recording):** the glide was set on the back-and-forward pill alone, so the field jumped at once and the glass caught up late, and removing Forward snapped the pill narrow under the moving field. Now one glide on the whole bar, and the pill's width glides between round (48pt) and wide (92pt) with Forward always there, faded and clipped when unused. Reload and Stop cross-fade. Second recording (Reduce Motion on): Firn's frost and words snapped while the `GlassEffectContainer` morphed the glass on its own timing, leaving a grey ghost; the container is gone (each capsule carries its own glass, and the pill fades while typing instead of morphing into the field), and Reduce Motion gets a short plain ease rather than a jump. *Known:* after a restart, Back is greyed out: not a bug, the session never kept page history (Mac too). Planned (2026-11-03): tabs remember their back history across a restart (`docs/HISTORY.md`).
3b. **Safari's buttons, Firn's look** (David, 2026-11-03, after a recording of Safari's bar: "This is the way"): Safari's placement and behavior, kept in Firn's tinted glass, page-color frost, and loading frost; capsules stay (iOS 26's own shape). Back is one round button that widens into back and forward once there's somewhere to go forward, gliding with no bounce (Reduce Motion: no glide). A page menu (≡) takes the field's left side, where a spacer balanced reload: Share and Copy Link only, kept short (Safari's runs about 20 items). Find, Zoom, Stop Blocking, and Request Desktop Site join it in phase 6 (desktop site needs engine work: the page's content mode and remembering it per site). The round tabs button on the right comes with tabs in phase 2. The shrinking pill stays phase 5.
4. **A look over and your iPhone:** light, dark, Reduce Motion, VoiceOver, installing on your iPhone (Developer Mode), then the done test. *Look over built* (2026-11-03): VoiceOver no longer finds the hidden Clear button, VoiceOver's scrub cancels typing (the dimmed page is hidden from it), and the bar's text stops growing at the largest size its 48pt height holds (as Safari's). Known for now: a link that opens a new window becomes a new tab with no way back to the first until phase 2's tabs; mail and phone links do nothing (only http and https, per the security rules). *Installed* (2026-11-03): the phone is registered with the team; to put a build on it, `xcodebuild -scheme "Firn iOS" -destination 'id=00008130-001968EA0CC0001C' -derivedDataPath ~/Library/Caches/FirnIOS-dd -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`, then `xcrun devicectl device install app` and `device process launch` with that id.

### Phase 2: Tabs, the overview, and the command bar

The tab model on iOS; the one-column overview behind the page (swipe up on the bar or tap the tabs button); tall cards and slim rows, aging over 24 hours, the tab on screen always tall with a frost ring; page previews saved on the device so they survive a restart (decided, section 5); pinch to switch the whole list; swipe a row to close; long-press drag to reorder; + opens the command bar over the dimmed page; quit and reopen brings everything back.
**Done:** open 10 tabs from the command bar, close and reorder some, pinch to slim rows and back, force-quit Firn (swipe it away), reopen: every tab is there in the same order, tall cards still show their page pictures, and the overview opens on the tab you were on. Close a tab and its picture is gone too.

Steps (written down 2026-11-03, David's OK):
1. **More than one tab** (built 2026-11-03; checked in the Simulator): links that open a new window become a tab (the model already did), and Back on such a tab, with nowhere to go back, closes it and shows the tab it came from, as in Safari (`BrowserStore.opener(of:)`). Background tabs sleep sooner than on the Mac (`Firn iOS/TabSleeper.swift`, `sleepIdleTabs(keepingRecent: 2)`): the tab on screen and the two most recent stay awake, and all but the tab on screen sleep when iOS warns about memory; a sleeping tab keeps its place and back history, and a page holding unsent text or playing sound stays awake (the Mac's rule). The round tabs button moved to step 2: with no overview behind it, it would do nothing. Fixed on the way: a page shown again (or restored) sat below the status bar, a new one under it; WebKit now hears about the status bar too (`PageView+iOS.swift`), so every page starts just below it. *Known:* at the end of a long page, the last lines rest behind the bar (in phase 1's setup too, so not new); two tries (Firn setting the scroll room itself) didn't settle it, so it's left for a fresh look. In landscape the side gutters show Firn's page color, not the site's (Safari uses the site's); for the look over.
2. **The overview, plain:** the round tabs button on the bar's right (where 3b left room); swipe up on the bar or tap the tabs button; one column of slim rows behind the page, opening scrolled to your tab; tap to switch, swipe a row sideways to close; a glass bottom bar with + on the left (opens the command bar, which also finds open tabs, so no separate search), the space's name in its color in the middle, and Done on the right; with one space, no dots yet (David, 2026-11-03). *Built 2026-11-03; checked in the Simulator, light and dark* (`Firn iOS/TabOverview.swift`, looks from `docs/ios-overview-design.html`): the page fades and steps back (only fades with Reduce Motion); rows are 48pt, 14pt corners, the tab on screen on page white with a frost ring; iOS's own swipe closes (a full swipe at once). Until the command bar (step 6), + goes back to the page with an empty address field, and Go opens a new tab.
2b. **The overview, with life** (David, 2026-11-04, after a recording of Safari's overview). iOS doesn't let apps see the wallpaper, so the backdrop is Firn's own. Two parts, each checked on David's iPhone:
   1. *The look:* a still "space glow" behind the list (a soft mesh of the space's color with Firn's glacier and apricot glow, darker in dark mode; nothing animates while idle; cross-fades between spaces). A blurred picture of the page on screen is the other idea, to try if the glow isn't enough. Rows become glass over it, one line each: the site's icon and the title (a second line with the site's name was tried and dropped, David, 2026-11-04). The bottom bar is balanced like Safari's: + on the left, the space's name in a tinted glass pill in the middle (the switcher with its dots in phase 4), and a round check on the right instead of Done, filled with a vivid version of the space's color (each space's own, deepened just enough for a white check to read). *Built 2026-11-04; checked in the Simulator, light and dark* (`SpaceGlow` in `Firn iOS/TabOverview.swift`; `Theme.overviewGlow` and `Theme.spaceVivid`).
   2. *Closing like Safari:* an X on every row closes it in one tap; a swipe left follows the finger and, past about a third or with a flick, slides the row off and closes it with no question (a short swipe glides back); shake to undo brings it back (iOS's own Undo alert, using `reopenClosed`).
3. **Page pictures, saved:** a small store in FirnCore, one picture per tab, in Firn's own container only, protected by iOS while the phone is locked, deleted with its tab or space.
3b. **The glide into the overview, like Safari's** (David, 2026-11-04: Firn's fade-and-step-back "is not good"; needs step 3's pictures). Read frame by frame from David's recording of Safari: opening takes about 0.27s with no bounce. The page itself shrinks, corners rounding as it goes, straight into its own card's exact spot in the list, so the tab you were on *is* the card you land on. The other cards are already in place behind it: dimmed and soft at the start, sharpening as the page leaves. Only once the page has landed do its title line and X fade in. The page's bar fades out as the overview's bar fades in, in place. Closing is the same move backwards: the tapped card grows from its spot to the full screen and the rest dim behind it. Every tab gets the same move: it always aims at that tab's card. How: one matched-geometry move (the live page, or its picture as a stand-in, from full screen to its card's frame), the list opened already scrolled so the card is on screen, a bounce-free spring about 0.3s; Reduce Motion: a plain cross-fade. Check against a 30 fps recording on David's iPhone.
4. **Tall cards and aging:** tall for 24 hours after last viewed, then slim; the tab on screen always tall with a frost ring; pinch switches the whole list, remembered; nothing changes size while scrolling.
5. **Long-press drag to reorder,** like Safari (loose tabs; onto another tab to group comes with phase 3).
6. **The command bar:** + opens it over the dimmed page above the keyboard: addresses, search, open tabs in this space, history, and a short list of actions; no tab until you pick; swipe down cancels. Then a look over (light, dark, Reduce Motion, VoiceOver) and the done test on your iPhone.

Paperwork for David during phase 2: request Apple's default-browser entitlement.

### Phase 3: Groups and Basecamp

Groups as frosted cards (fold, rename, ungroup, close), made by dragging a tab onto another or from the long-press menu; drag in and out. Basecamp: starts empty and hidden, "Add to Basecamp" from a tab's long-press, up to 12 with the plain-words message on the 13th, balanced rows, scrolls with the list.
**Done:** make two groups, drag tabs between them and out of them, add five sites to Basecamp (rows read 3 + 2), try a 13th, force-quit and reopen: all of it comes back.

### Phase 4: Spaces, truly separate

Create, rename, color, reorder, and delete spaces; each with its own data store, Basecamp, groups, and tabs; the "Share sign-ins" choice; swiping sideways on the overview's bottom bar changes space, with a dot per space under the space's name, and tapping the name opens the space menu (as on the Mac); the tint cross-fades.
**Done:** two spaces signed into two different Google accounts at once on your iPhone; a new space that shares sign-ins is already signed in; deleting a space signs it out for good. (Same test as the Mac's Phase 4.)

### Phase 5: The address bar's glide (its own plan first)

Scrolling down shrinks the bar to a domain-only pill; scrolling up, tapping, or reaching the end brings it back; swiping along the bar or pill switches tabs. Follows your finger with Firn's easing; Reduce Motion simply fades.
**Done:** read three long articles; the bar never jitters, never hides the domain, and swiping along it walks through your tabs. With Reduce Motion on, it only fades.

### Phase 6: The everyday features

In small steps: Lookout (iOS's long-press link preview with "Open as tab"), tidy away (the Tidied away button beside the space's name in the overview's bottom bar, and the frost-and-thaw moment), history, find in page, downloads to Files, ad and tracker blocking with Stop Blocking per site, scam warnings, saved passwords (save, fill after a tap, Settings › Passwords behind Face ID), and Settings.
**Done:** a week of using Firn as the iPhone's only browser (it can't be the default yet, so open it yourself), plus the Mac's test pages (`docs/blocking-test.html`, `docs/password-test.html`) passing on the iPhone.

### Phase 7: iPad

The two-column overview, the roomy sidebar when the window is wide enough (drag to resize, swipe to hide), split view in that layout only, layouts chosen by window width (Stage Manager, split screen, and Slide Over included), keyboard shortcuts with a hardware keyboard.
**Done:** on an iPad (or the iPad Simulator if you don't have one): rotate, resize the window in Stage Manager, and watch it move between one column, two columns, and the sidebar without losing your place; open a split view.

### Phase 8: First light, and being the default browser

The welcome (iOS version of the Mac's steps, without Arc and Mac-only tips), the empty page, and "Set as default browser" (needs Apple's default-browser entitlement; see section 5).
**Done:** delete and reinstall Firn: the welcome plays in light, dark, and with Reduce Motion; after setting Firn as default, a link tapped in Mail opens in Firn, in the space you used last.

### Phase 9: Sync (its own plan, its own approval)

Planned separately before any code, with you, on Opus. This is the first phase that changes the Mac app (the Mac needs sync too), so it needs your explicit go-ahead for each Mac change. It covers: CloudKit in your own iCloud (off by default), what syncs per the brief's tables, delete confirmations and Undo, offline and "latest change wins", "On your Mac" / "On your iPhone", Handoff, passwords through iCloud Keychain, and the new privacy wording (needs your OK).
**Done (to be refined in its plan):** with sync on, a group made on the Mac appears on the iPhone, renaming it on the iPhone renames it on the Mac, a separate space stays signed out on the new device, and with sync off nothing leaves either device.

### Phase 10: Release

TestFlight for a few friends, the App Store listing and its privacy label, the iOS screenshots (an iOS `--demo` mode, like the Mac's), and the release notes. Ships together with phase 9, as the brief says.
**Done:** a friend installs it from TestFlight and uses it for a week.

---

## 4. What goes into CLAUDE.md

A short section after "How spaces work" (draft):

> ## iPhone and iPad
>
> The iOS app (`Firn iOS` target, `docs/IOS-BRIEF.md`) shares FirnCore with the Mac app and has its own views: iOS's ways, Firn's shapes and calm. Plan and phases: `docs/IOS-PLAN.md`.
>
> - **Never change how the Mac app behaves** from iOS work. Shared changes are additions only: an iOS-only file or an `#if os(iOS)` branch. Before every commit: the Mac builds, FirnCore's tests pass on macOS and the iOS Simulator, and `git diff main -- Firn/` holds nothing unexpected.
> - **iOS 26 and later** (David, 2026-11-03): Liquid Glass only, no fallback materials. The Mac stays on 14 and later.
> - **One design that adds columns as the window widens** (one column, two columns, the roomy sidebar), chosen by window width, never by how the device is held.
> - **Address bar always at the bottom** on iPhone and iPad; it shrinks to a domain-only pill on scroll. No top option.
> - **The same separation promise:** every web view in a space uses its `dataStoreID`, never the default store, and iOS gets the same "two Google accounts" check.
> - **No new network traffic or data collection** beyond the Mac's, until sync, which has its own plan and needs David's OK, including any Mac change it makes.
> - **Not doing on iOS:** cards that grow as you scroll, a Mac-style sidebar, a top address bar, a new-tab page, a "Send to" button, a synced Basecamp between Mac and iOS, AI-first features.
> - **Build:** `xcodebuild -scheme "Firn iOS" -destination 'platform=iOS Simulator,name=iPhone 17' build`, quiet as usual. David tests on his iPhone from Xcode.

And in "Where we are":

> - **iPhone and iPad (branch `ios`):** planned (2026-11-03, `docs/IOS-PLAN.md`), ten phases; sync is phase 9 with its own plan. David's answers recorded (iOS 26, Basecamp per space, previews saved). Next: phase 0, FirnCore building for iOS.

---

## 5. Risks, unclear parts, and pushback

### Decided (David, 2026-11-03)

- **Basecamp is per space on iOS,** as on the Mac.
- **Between iPhone and iPad, Basecamp and tabs sync; between iOS and the Mac, they don't.** A loose tab on the other kind of device is found through the command bar ("On your Mac" on iOS, "On your iPhone" on the Mac). Groups still sync everywhere. This changes the brief's sync table (loose tabs no longer stay on each device between iPhone and iPad); phase 9's plan follows this.
- **Spaces change by swiping on the overview's bottom bar;** a sideways swipe on a row closes it.
- **Page previews are saved,** as in Safari: on the device only, in Firn's own container, protected by iOS while the phone is locked, deleted with their tab (and with their space), never synced.
- **iOS 26 is the minimum.** Liquid Glass only, no fallback materials on iOS.
- **Apple paperwork:** request the default-browser entitlement during phase 2; check the bundle ID before phase 1.
- **Privacy label:** "Data Not Collected"; Apple's opt-in crash reports are Apple's, not Firn's.

The items below are kept for the reasoning; 1, 2, 3, 4, 6, 7, 8, 9, and 10 are answered above.

### Unclear in the brief (I need your answer before the phase that uses it)

1. **Is Basecamp per space on iOS?** On the Mac, every space has its own Basecamp. The brief says "your Mac has one Basecamp; your iPhone and iPad share another," which reads like one per device. My suggestion: per space on iOS too (same rule everywhere), so "one set for Macs, one for iPhone and iPad" means each space has a Mac set and an iOS set. Needed by phase 3.
2. **Basecamp does sync, a little.** The sync table puts Basecamp under "stays on each device," but iPhone and iPad sharing one set (and Macs sharing another) means Basecamp syncs between devices of the same kind. The table should say so. Phase 9.
3. **Loose tabs also reach iCloud.** The table says loose tabs stay on each device, but "On your Mac" needs their addresses in iCloud. The privacy-wording paragraph already says this; the table should match it. Phase 9.
4. **Swipe sideways to change spaces vs. swipe a row to close.** Both are sideways swipes in the overview. A swipe that starts on a row would close it; one that starts between rows would change space. That's the kind of thing people trip over. Suggestion: change spaces by swiping on the overview's bottom bar (with dots per space, as on the Mac), and let rows keep the close swipe. Decide by phase 4.
5. **Basecamp tiles' links.** On the Mac, a tile's links to other sites open in a Lookout. iOS Lookout is the long-press preview only. Suggestion: on iOS they open where new tabs go. Phase 6.

### Things I'd push back on or ask about

6. **Page previews after a restart.** iOS closes apps in the background often. The tall cards' page pictures are in memory on the Mac; on iOS they'd be gone after every restart unless Firn saves them to disk. Saving pictures of pages is new stored data (on the device only, deleted with the tab, encrypted by iOS while the phone is locked). Your call: save them, or show the site's icon on soft frost until you open the tab again. Phase 2.
7. **Minimum iOS version.** CLAUDE.md says iOS 17. Since iOS ships with sync, well after today, I'd lean toward iOS 26 (iPhone 11 and newer): one look (Liquid Glass) with no fallback to design and test twice. iOS 18 is a middle path. Your call before phase 1.
8. **The default-browser entitlement** comes from Apple, by request, and can take a while. I'd ask for it early (during phase 2), the way passkeys were requested.
9. **The bundle ID.** I'd use `com.firnbrowser.firn` for iOS too (one app ID, easier for iCloud and Keychain later), but I'm not sure how it mixes with the Mac's Developer ID provisioning profile. I'll check in Xcode before phase 1 and tell you; it's hard to change after release.
10. **App Store and "no data collection."** The Mac ships outside the App Store; iOS can't. Firn itself collects nothing, but Apple offers crash reports to developers from people who opt in ("Share with App Developers"), and TestFlight testers can send feedback. That's Apple's, opt-in, and Firn adds nothing; the privacy label can still say "Data Not Collected." Worth knowing before you make privacy claims.
11. **Sync needs Mac changes.** "Never change the Mac app" holds until phase 9. Sync (and Handoff, which also goes through Apple's services) can't work without the Mac app joining in. That phase's plan will list every Mac change for your OK.
12. **Saved passwords through iCloud Keychain** means moving the Mac's passwords from Firn's local Keychain items to ones that sync. That changes where people's passwords live, so it's part of phase 9's plan, carefully, never a quiet switch.
13. **iPad windows.** I'd start with one window on iPad (multiple windows add a lot), and add more later if you miss them.
14. **System password AutoFill.** I'm not sure whether iOS offers the Passwords app's logins inside Firn's pages on its own; I'll check in phase 6 before building Firn's fill list on iOS, so the two don't fight.

### Risks

- **The shrinking bar** is the hardest piece to make feel calm (watching the page's scroll without jitter). It's isolated in phase 5 so it can't hold up the rest.
- **Memory.** iOS is much stricter than the Mac about memory; the Mac's tab sleeping needs to be more eager on iPhone. Watched from phase 2.
- **Sync** is the biggest risk overall (conflicts, deletes across devices, and privacy wording). It gets its own plan and stays last.
- **Two branches drifting.** Mac fixes on `main` while iOS grows on `ios`. Merging `main` in often, and phase 0 into `main` early, keeps that small.

### Already true in the brief (no change needed)

- Basecamp's balanced rows match the Mac's existing code exactly, row for row; only "up to 6 across" is new.
- Tidying uses days of using Firn, 7 by default, as on the Mac.
- Lookout, tidy away, First light, and split view (roomy layout only) carry over as the brief says.
