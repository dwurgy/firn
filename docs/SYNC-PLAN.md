# iCloud sync: the plan

Planned 2026-11-13 with David. Built now, ahead of the iPhone's remaining phases (it was phase 9 in `docs/IOS-PLAN.md`). Opus throughout. Work on the `ios` branch, where both apps build. This is the first work that changes the Mac app for the iPhone's sake, so every Mac change is named in its step.

The aim (David): Apple users should find it seamless, using every piece of Apple's encrypted sync that fits.

## What syncs (David, 2026-11-13)

Sync is off until the person turns it on, and goes only to their own iCloud, never to Firn or any server of ours. No account.

| Syncs | Found in the command bar | Never |
| --- | --- | --- |
| Spaces: name, color, order, separate or shared | Other devices' loose tabs ("On your Mac", "On your iPhone", "On your iPad") | Basecamp (no sync at all, not even iPhone to iPad) |
| Groups and the tabs in them | | Loose tabs as a list (each device keeps its own) |
| Saved passwords (iCloud Keychain) | | Sign-ins, cookies, and site data (WebKit can't sync them) |
| History, as Safari does | | Settings (each device keeps its own) |
| | | Page pictures, downloads, and a tab's back history |

- **Spaces sync, and stay what they are.** A space arrives on a new device with its data store id, so a separate space is still separate there, and starts signed out (its cookies can't travel). A shared space still shares. Its passwords and history come with it, because both are kept per data store id.
- **One switch, no other options** (David, 2026-11-13: intuitive and polished, not many options; "whatever is best"). Sync on or off, and that's all. An earlier draft had a "Tabs" choice; it's gone.
- **Loose tabs work as in Arc** (David, 2026-11-13). Arc synced what you deliberately kept (spaces, pinned tabs, favorites), never the day's unpinned tabs. In Firn, keeping a tab is putting it in a group, so groups sync and loose tabs don't, on any device (iPhone and iPad included). A loose tab on another device is found by going to it: the command bar lists it under "On your Mac" (or iPhone, or iPad), read-only; picking one opens your own copy. They never appear in the sidebar or the overview. Their addresses and titles go to iCloud, encrypted, so the command bar can show them.
- **Settings stay on each device** (Claude's call, 2026-11-13, for less to think about): the tidy-away timing, where new tabs go, and the address bar's place often differ between a Mac and a phone anyway.
- **History:** whatever Safari does (David). To check in step 1: how far back Safari's synced history reaches. If it's the whole year Firn keeps and that proves too much to sync, the fallback is the last 30 days.
- **Handoff** works with sync on or off and stores nothing in iCloud.

This replaces the sync tables in `docs/IOS-BRIEF.md` (Basecamp and loose tabs no longer sync between iPhone and iPad).

## Apple's technology

- **CloudKit's private database,** through `CKSyncEngine` (macOS 14 and iOS 17, Firn's minimums). It keeps changes made offline, sends them later, takes pushes from other devices, retries, and reports iCloud sign-in and sign-out. One custom zone for Firn.
- **Every field in `encryptedValues`:** names, colors, addresses, titles, and times are encrypted on the device with keys kept in iCloud Keychain, so Apple can't read them (to confirm against Apple's documentation in step 1, before any wording promises it). Record names are random UUIDs (already Firn's ids), so they say nothing. Record types (`Space`, `TabGroup`, `Tab`, `Visit`) are visible to Apple but hold nothing personal.
- **Saved passwords in iCloud Keychain** (`kSecAttrSynchronizable`), end-to-end encrypted. Passkeys go the same way once Apple grants their entitlement.
- **Handoff** through `NSUserActivity` (web browsing activity): the page on the iPhone shows in the Mac's Dock, and the other way around.
- **Latest change wins,** per record, by its last-changed time (every record already has one). Things that belong to one device (where a group sits in the list, whether it's folded, which tab is on screen) never go in a record.
- **iCloud signed out:** sync pauses, and everything stays on the device.

## Steps

1. **Groundwork.** Check the facts above: Developer ID Mac apps with CloudKit and push notifications, what `encryptedValues` promises, and how far back Safari syncs history. Then the iCloud container (`iCloud.com.firnbrowser.firn`), and the iCloud and push entitlements on both apps. David makes the new provisioning profiles in the developer portal. *Mac change:* two entitlements and a new profile. *Done:* both apps launch signed, and nothing is sent yet.
2. **Records in FirnCore.** Spaces, groups, tabs, and visits to and from records, with the merge rules (latest wins, per-device fields kept apart, a deleted group's tabs). Tested without iCloud.
3. **The engine and spaces.** A sync engine in both apps, and Settings › Sync: one switch, off by default. Spaces sync. *Mac change:* the new Settings section. *Done:* a space made on the Mac appears on the iPhone, and a separate one is signed out there.
4. **Groups.** Groups and their tabs. Deleting a group or space asks "from all your devices", and a group's delete has an Undo. *Done:* a group made on the Mac appears on the iPhone, and renaming it on the iPhone renames it on the Mac.
5. **"On your Mac" and "On your iPhone":** each device shares its open loose tabs' addresses and titles (kept current, removed as they close), and the command bar lists the other devices' under their names. *Mac change:* a command bar section.
6. **History.**
7. **Handoff.**
8. **Passwords to iCloud Keychain.** Its own short plan first: it moves where people's passwords live, so never a quiet switch.
9. **A look over.** The privacy wording (David's OK; `docs/privacy-page.md` and the README), "Turn off and delete from iCloud", the security check, VoiceOver, and the two-device test. *Done:* with sync off, nothing leaves either device.

## Open

Nothing yet. (Settled 2026-11-13: loose tabs as in Arc, and no Tabs setting.)
