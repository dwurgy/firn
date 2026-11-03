# Firn for iPhone and iPad: project brief

Nov 2, 2026 · @David Wurgler

## The idea

Firn for iPhone and iPad is Safari's ease of use with Firn's ideas inside it. The controls work the way iOS people already expect; what makes it Firn is the shape of the tab list, the names, the materials, and the calm, not a copy of the Mac's layout.

- **Starts after** the Mac app is published and stable.
- **Ships together with sync.** Your Mac's Firn in your pocket is the main reason to use it, so iPhone, iPad, and sync launch as one.
- **Same principles as the Mac:** calm first, privacy by default, easy for normal people, and real-platform conventions. Here that means feeling like a real iPhone and iPad app.
- **Design so far:** the [tab overview and iPad canvas](https://claude.ai/artifact/8KD2apKPEGfsUJteoRx8Y6), built from David's paper sketch.

## Layouts and getting around

One touch design that adds columns as the window grows, chosen by how wide Firn's window is, never by how the device is held.

| Window width | Where | What you get |
| --- | --- | --- |
| Phone-wide | iPhone; a foldable iPhone folded | One-column tab overview behind the page |
| Wider | iPad in portrait; a narrow iPad window; a wide window with the sidebar hidden; a foldable open in portrait | Two-column tab overview behind the page |
| Wide enough for the sidebar | iPad full screen in landscape; a foldable open in landscape | An iOS-style sidebar beside the page, plus split view |

**Roomy sidebar.** The same overview list (Basecamp, groups, loose tabs) docked beside the page. It looks like iOS, not the Mac: slim rows by default, drag to resize, swipe to hide. It never squeezes into a window too narrow for it.

**Address bar.** Always at the bottom, on every iPhone and iPad layout; no top option. It behaves like Safari's:

- Scrolling down shrinks it into a small pill that shows only the site's domain, never the page title.
- Scrolling up, tapping the pill, or reaching the end of the page brings back the full bar.
- Swiping along the bar or the pill switches tabs.
- The glide follows your finger with Firn's easing; with Reduce Motion it simply fades.
- With the iPad sidebar showing, the bar still shrinks; the sidebar stays put.
- Build it as its own step, with a plan first: it means watching the page's scrolling, and a jittery bar breaks the calm.

The Mac keeps its address bar where it is (sidebar or top).

**Gestures.** Safari's, unchanged: swipe along the bar to switch tabs, swipe up for the overview, swipe from the edge to go back, swipe a row sideways to close it. Firn adds one: swipe sideways on the overview's bottom bar to change spaces, so it never fights a row's close swipe (David, 2026-11-03).

**New tabs.** No new-tab page, matching the Mac. Tapping + opens the command bar over the dimmed current page, just above the keyboard; no tab exists until you pick something, and swiping down cancels. It handles addresses, search, open tabs in this space, and actions.

## The tab overview

The overview follows David's sketch: the Mac's sidebar order on a phone, with tabs as wide rows that can carry a page preview.

- **Order:** Basecamp at the top, then groups and loose tabs in one shared order, as on the Mac. A group can sit anywhere.
- **Drag to reorder, like Safari:** long-press any tab or group and drag it anywhere in the overview, onto another tab to make a group, into a group, or out of one.
- **A loose tab ages in three quiet stages:** a tall preview card (the tab row with a crop of the page below it) for 24 hours after you last opened or viewed it, then a slim row, then tidied away after 7 days of using Firn, the same default as the Mac (1 day, 30 days, or Never in Settings). Opening it again makes it tall for another 24 hours. Scrolling past it in the overview doesn't count.
- **The tab on screen is always tall,** even after a weekend away, has a frost ring, and the overview opens scrolled to it.
- **Nothing changes size while you scroll.** Cards that grow as you scroll were tried and dropped as too busy.
- **Pinch** switches the whole list between previews and slim rows, as in Photos. Firn remembers the choice.
- **Groups** are frosted cards with a name and a fold arrow, the same as on the Mac. Tabs inside are always slim rows: grouping a tab means you're keeping it.
- **Two columns** (wider windows): items flow in the same order across two columns; tall cards come before slim rows, so neighbours usually match in height.
- **Bottom bar in the overview:** a glass bar with a new-tab button, search, and Done.

## Basecamp, spaces, and the rest

**Basecamp.** Each space has its own Basecamp, as on the Mac (David, 2026-11-03): one set on your Macs, and another your iPhone and iPad share. On a phone you use apps for many everyday sites (mail, calendar, music), so the Mac's tiles would mostly go unused there.

- It starts empty, and the row doesn't show until you add something.
- You add a tile by long-pressing a tab and choosing "Add to Basecamp."
- Up to 12 tiles, the same as the Mac. Few people will add that many, but on a wider iPad it fits as two even rows of six. Adding a thirteenth says so in plain words.
- It scrolls away with the tabs and groups; it isn't pinned to the top. Tapping the top edge of the screen (built into iOS) jumps back to it. The iPad sidebar works the same way.
- **Balanced rows:** as few rows as the width allows, with tiles spread as evenly as possible; a shorter row goes at the bottom, centered, and every tile stays the same size. How many fit across comes from a minimum tile width (about 56pt), so it adjusts as the iPad sidebar is dragged, and tiles glide to their new places. Should match the Mac if the Mac already balances differently.

| Tiles | iPhone (up to 4 across) | Narrow iPad sidebar (up to 3 across) | Two-column iPad (up to 6 across) |
| --- | --- | --- | --- |
| 4 | 4 | 2 + 2 | 4 |
| 5 | 3 + 2 | 3 + 2 | 5 |
| 6 | 3 + 3 | 3 + 3 | 6 |
| 7 | 4 + 3 | 3 + 2 + 2 | 4 + 3 |
| 8 | 4 + 4 | 3 + 3 + 2 | 4 + 4 |
| 9 | 3 + 3 + 3 | 3 + 3 + 3 | 5 + 4 |
| 10 | 4 + 3 + 3 | 3 + 3 + 2 + 2 | 5 + 5 |
| 11 | 4 + 4 + 3 | 3 + 3 + 3 + 2 | 6 + 5 |
| 12 | 4 + 4 + 4 | 3 + 3 + 3 + 3 | 6 + 6 |

**Spaces.** The same spaces as on the Mac, with the same separation promise: a separate space shares no sign-ins, cookies, history, or passwords with another, on any device. The space's color tints the snow and the mark, never the sky.

**Carried over from the Mac:**

- **Lookout:** iOS's own link preview when you long-press a link, plus "Open as tab."
- **Tidy away:** idle loose tabs drift into the overview button, with the same frost-and-thaw moment.
- **First light:** the welcome screen, and the empty page when every tab in a space is closed. Never everyday browsing.
- **Split view:** roomy layout only.

## Sync

Sync is off by default and goes only through the person's own iCloud, encrypted, never to Firn or any server of ours. No account.

| Syncs everywhere | Syncs between iPhone and iPad only | Stays on each device |
| --- | --- | --- |
| Spaces | Loose tabs | Sign-ins and cookies (WebKit can't sync them) |
| Groups and the tabs in them | Basecamp (each space has one set for Macs, one for iPhone and iPad) | |
| Saved passwords, through iCloud Keychain | | |

Between the Mac and iPhone or iPad, loose tabs don't sync: they're found through the command bar ("On your Mac", "On your iPhone"), as below (David, 2026-11-03).

**A group is one group everywhere,** not a copy. Rename it, add a tab, close a tab, or delete it on any device, and it changes on all of them. Dragging a loose tab into a group is what makes it a tab that syncs.

| Syncs for a group | Stays on each device |
| --- | --- |
| That it exists, and its name | Where it sits in the list |
| Which tabs are in it | Whether it's folded |
| The order of tabs inside it |  |

A group arriving from another device lands where new tabs go (the Mac's "top or bottom" setting, bottom by default). After that it stays wherever you move it on that device.

**Safety nets:**

- Deleting a group or space asks first, in plain words: "Delete 'Weekend cooking' from all your devices?" Deleting a space also says its sign-ins and site data go too.
- A short Undo appears after deleting a group.
- Single tabs never ask.

**Offline:** changes wait and catch up later. If two devices change the same thing, the latest change wins. The Mac app's data is already set up for this (stable ids, a last-changed time on every record).

**Moving a loose tab without grouping it:**

- **Handoff:** Apple's own feature. The page open on your iPhone shows in your Mac's Dock, and one click opens it in Firn. Works with sync off and sends nothing to iCloud storage.
- **"On your Mac" and "On your iPhone":** with sync on, each device can see the other's loose tabs from the address bar or command bar. Read-only; tapping one opens your own copy. They never appear in the overview.
- No "Send to" button. Two ways is enough.

**Privacy wording (needs David's OK before launch):** with sync on, spaces, groups, and the loose-tab addresses behind "On your Mac" go to the person's own iCloud, encrypted. "Your data stays on your device" has to change for people who turn sync on.

## How it differs from Arc

Arc kept the Mac's tabs in a separate "Desktop" view on the phone, made a copy when you opened one, and could only send a phone page back by saving it as a pinned tab. It also needed an account and its own servers. Firn's groups live right in the phone's overview and work both ways, through the person's own iCloud. Like Firn, Arc never synced its Favorites (its Basecamp).

## Not doing

- Cards that grow as you scroll
- A Mac-style sidebar on iPad (the roomy sidebar is iOS-style)
- A top address bar option on iPhone or iPad
- A new-tab page
- A "Send to" button
- A synced Basecamp between Mac and iPhone or iPad
- AI-first features in the style of Arc Search

## Open questions

- [ ] Exact wording of the sync setting and the delete confirmations

## Sources

- [Arc 1.5 Brings Back Today Tab Syncing (TidBITS)](https://tidbits.com/2023/08/27/arc-1-5-brings-back-today-tab-syncing/)
- [Arc Gains Instant Links, Tab Grouping, and Arc Search iPhone App (TidBITS)](https://tidbits.com/2024/02/15/arc-gains-instant-links-tab-grouping-and-arc-search-iphone-app/)
- [Arc Search iPhone App Now Syncs Arc Sidebar Tabs (TidBITS)](https://tidbits.com/2024/04/29/arc-search-iphone-app-now-syncs-arc-sidebar-tabs/)
- [How to Enable and Use Arc Sync in Arc Search (All Things How)](https://allthings.how/?p=8631)
- [Arc Search review (kvibber.com)](https://kvibber.com/reviews/apps/arc-search/)
