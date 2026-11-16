# To check when home

Everything built but not yet seen by David, gathered from the brief on 2026-11-16. Tick a line once it looks right; anything that doesn't goes back to the brief as a bug. Check light and dark, and Reduce Motion where something moves. Install Release builds on the iPhone for anything about feel.

## Mac

- [ ] **The welcome on Sunrise** (Help › Show Welcome Again): the headlines in Gooper Deck, the scene, and "Welcome in."
- [ ] **Dark mode a little darker:** frame #28241F, page #1C1916, a held tile #332E29; a space's tint no longer greys it out.
- [ ] **Settings › Sync:** the pane, and how it reads when not signed in to iCloud.
- [ ] **Groups a link made:** click a link from a loose tab (a group forms), close tabs until one is left: the group ends, the tab stays loose where it was.
- [ ] **Group names that update:** drag a tab into an auto-named group: the name fades to a new one. Rename it, add another tab: the name stays.
- [ ] **Reader:** the book in the address bar, ⇧⌘R, and Reader in the command bar. In the reader: right-click, ⌃Tab, ⌘F, Print, and ⌘+ / ⌘−. `docs/reader-test.html` has the cases.
- [ ] **Summarize:** the pill and card in the reader, View › Summarize Article, and the command bar's Summarize. VoiceOver hears the summary arrive.
- [ ] **http-only sites:** type `neverssl.com` (no `http://`): Continue Without a Secure Connection, then "Not Secure" in terracotta and just "neverssl.com" in the bar.

## iPhone

### Overview and tabs (the newest work)

- [ ] **The space wash** behind the overview (Glacier, Sage, Heather), with "No open tabs" muted, a little above the middle.
- [ ] **Only the tab on screen is a tall card** (240pt) each time the overview opens; a pinch apart opens all of them for that visit only.
- [ ] **Tall cards on warm paper:** the slim row's line, the page in a window below with a clear mat inside the ring, the picture starting below the page's header.
- [ ] **The landing** (Done, or tapping a card): the overview there at once, blurred and dimmed, clearing as the tab lands. A tab near the end of the list lands a third down, with no snap.
- [ ] **A tab closing into its Basecamp tile** (the last round wasn't recorded).
- [ ] **The page into its tile:** smoother, the tile's spot empty during a pull.
- [ ] **The hold and sideways swipe:** the sliding pills and the strip behind the clock.
- [ ] **Firn's hold menu, last step:** Move to Group's chevron, VoiceOver focus on opening, the menu closing when Firn leaves the screen.
- [ ] **Measure the swipe up** with a cable and Xcode open (Instruments; 2i steps 3 and 4 in `docs/IOS-PLAN.md`).

### The address bar

- [ ] **The small pill:** tap only, lower, a touch smaller.
- [ ] **The page menu and Reload** ride the field's edges as it shrinks and grows.
- [ ] **Basecamp tiles swipe sideways** like tabs, tiles first.

### Spaces

- [ ] **New Space** from the space menu and the command bar.
- [ ] **Settings › Spaces:** reorder by hold and drag, name, color, sign-ins, and Delete.
- [ ] **With Reduce Motion** the swipe changes space without sliding.

### Pages

- [ ] **Reader:** the book takes •••'s place on articles, "Reader available" for a moment, Show Reader first in the page menu, the Aa pill under the clock.
- [ ] **Summarize:** in the page menu under Show Reader, the suggestion under the heading, and in the command bar.
- [ ] **A failed load** shows Firn's error page, and the bar names the failed site.
- [ ] **Alerts and confirms** show as iOS's alert, headed by the real site.
- [ ] **Ad and tracker blocking:** the Settings switch, and Stop Blocking in the page menu.
- [ ] **http-only sites:** the same `neverssl.com` check as on the Mac.
- [ ] **Groups a link made** and **group names that update**, as on the Mac.

### Dragging

- [ ] **Basecamp tiles:** reorder by hold and move, and with Reduce Motion a tab becoming a tile fades in place.

## Mac and iPhone together

- [ ] **Sync, step 4 (groups):** with Sync with iCloud on in both, make a group on the Mac: it appears on the iPhone. Rename it on the iPhone: the Mac follows. Close it on the Mac, then ⇧⌘T: it comes back on both. Delete a test space: the question says "from all your devices".

## Things only David can do

- [ ] **Default browser:** turn on the browser entitlement for the app ID in the developer portal, save the Mac's "Firn Developer ID" profile again, then pick Firn in Settings › Apps › Firn › Default Browser App (`docs/IOS-PLAN.md`, section 5).
- [ ] **A pass through the overview and the Mac sidebar** after the big file splits, just to be sure nothing moved.
