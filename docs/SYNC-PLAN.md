# iCloud sync: the plan

Planned 2026-11-13 with David. Built now, ahead of the iPhone's remaining phases (it was phase 9 in `docs/IOS-PLAN.md`). Opus throughout. Work on the `ios` branch, where both apps build. This is the first work that changes the Mac app for the iPhone's sake, so every Mac change is named in its step.

The aim (David): Apple users should find it seamless, using every piece of Apple's encrypted sync that fits.

## What syncs (David, 2026-11-13)

Sync is off until the person says yes, and goes only to their own iCloud, never to Firn or any server of ours. No account.

| Syncs | Found in the command bar | Never |
| --- | --- | --- |
| Spaces: name, color, order, separate or shared | Other devices' loose tabs ("On your Mac", "On your iPhone", "On your iPad") | Basecamp (no sync at all, not even iPhone to iPad) |
| Groups and the tabs in them | | Loose tabs as a list (each device keeps its own) |
| Saved passwords (iCloud Keychain) | | Sign-ins, cookies, and site data (WebKit can't sync them) |
| History, the last 30 days | | Settings (each device keeps its own) |
| | | Page pictures, downloads, and a tab's back history |

- **Spaces sync, and stay what they are.** A space arrives on a new device with its data store id, so a separate space is still separate there, and starts signed out (its cookies can't travel). A shared space still shares. Its passwords and history come with it, because both are kept per data store id.
- **Two switches, no other options** (David, 2026-11-13: intuitive and polished, not many options), as in Apple's own iCloud settings, where Safari and Passwords are separate. **Sync with iCloud:** spaces, groups, history, and "On your Mac". **Passwords:** just under it, on when sync is turned on, easy to turn off (for people who use another password manager; turning on sync never quietly moves passwords). An earlier draft had a "Tabs" choice; it's gone.
- **Asked once, in the welcome** (David, 2026-11-13), on the Mac and the iPhone, not switched on silently (Firn's promise: data stays on the device unless you choose otherwise). "Keep your spaces on all your devices?", a line saying it goes through your own iCloud, encrypted so only your devices can read it, and **Use iCloud** (the main button, turning on both switches) or Not Now. Skipped when the device isn't signed in to iCloud (Settings says why). People past the welcome find the switches in Settings › Sync, and one line in the release notes; no pop-up.
- **"On your Mac" shows only with sync on.** With it off, the command bar has no such section and nothing leaves the device.
- **Loose tabs work as in Arc** (David, 2026-11-13). Arc synced what you deliberately kept (spaces, pinned tabs, favorites), never the day's unpinned tabs. In Firn, keeping a tab is putting it in a group, so groups sync and loose tabs don't, on any device (iPhone and iPad included). A loose tab on another device is found by going to it: the command bar lists it under "On your Mac" (or iPhone, or iPad), read-only; picking one opens your own copy. They never appear in the sidebar or the overview. Their addresses and titles go to iCloud, encrypted, so the command bar can show them.
- **Settings stay on each device** (Claude's call, 2026-11-13, for less to think about): the tidy-away timing, where new tabs go, and the address bar's place often differ between a Mac and a phone anyway.
- **History: the last 30 days** (David, 2026-11-13, as Safari seems to do). Each device still keeps its own full year; only the last 30 days go to iCloud, and older visits leave iCloud as they age out.
- **Handoff** works with sync on or off and stores nothing in iCloud.

This replaces the sync tables in `docs/IOS-BRIEF.md` (Basecamp and loose tabs no longer sync between iPhone and iPad).

## Apple's technology

- **CloudKit's private database,** through `CKSyncEngine` (macOS 14 and iOS 17, Firn's minimums). It keeps changes made offline, sends them later, takes pushes from other devices, retries, and reports iCloud sign-in and sign-out. One custom zone for Firn.
- **Every field in `encryptedValues`:** names, colors, addresses, titles, and times are encrypted on the device with keys kept in iCloud Keychain, so Apple can't read them. **Checked in step 1: only true with Advanced Data Protection;** see "Step 1: what the facts turned out to be". Record names are random UUIDs (already Firn's ids), so they say nothing. Record types (`Space`, `TabGroup`, `Tab`, `Visit`) are visible to Apple but hold nothing personal.
- **Saved passwords in iCloud Keychain** (`kSecAttrSynchronizable`), end-to-end encrypted. Passkeys go the same way once Apple grants their entitlement.
- **Handoff** through `NSUserActivity` (web browsing activity): the page on the iPhone shows in the Mac's Dock, and the other way around.
- **Latest change wins,** per record, by its last-changed time (every record already has one). Things that belong to one device (where a group sits in the list, whether it's folded, which tab is on screen) never go in a record.
- **iCloud signed out:** sync pauses, and everything stays on the device.

## Steps

1. **Groundwork.** Check the facts above: Developer ID Mac apps with CloudKit and push notifications, what `encryptedValues` promises, and how far back Safari syncs history. Then the iCloud container (`iCloud.com.firnbrowser.firn`), and the iCloud and push entitlements on both apps. David makes the new provisioning profiles in the developer portal. *Mac change:* two entitlements and a new profile. *Done:* both apps launch signed, and nothing is sent yet. **Done (2026-11-13):** the container and App ID were already set up; only the Mac's Developer ID profile needed saving again in the portal, and `xcodebuild -allowProvisioningUpdates` fetched it (no Xcode clicks). Both apps build signed with the entitlements, and the Mac app launches.
2. **Records in FirnCore.** Spaces, groups, tabs, and visits to and from records, with the merge rules (latest wins, per-device fields kept apart, a deleted group's tabs). Tested without iCloud. Agreed with David (2026-11-13), four parts:
   - **The seal** (`Sync/SyncSeal.swift`): each record's synced fields as a small JSON, sealed with AES-GCM (CryptoKit) by a key passed in. CloudKit sees only the record type, its random id, and sealed bytes. Keeping the key in iCloud Keychain is step 3 (it needs the signed app).
   - **The records:** a space (name, color, order, data store id; its blocking and "Never save" lists stay on each device, as settings); a group (name, space; its place in the list and folding stay per device); a tab in a group (address, title, group, its order inside the group); a visit (address, title, time, data store). Each record gets its own change time from synced fields only, so folding a group on one device can't beat a rename on another.
   - **The merge:** what changed since the last sync (saves and deletes), and applying what comes in: latest change wins per record, per-device fields never touched, a deleted space takes its groups and tabs (and its browser data once no space uses it). **Ungroup** on one device leaves those tabs loose on the others too, rather than closing them (David). **Groups a link made** sync only once kept by hand (David). **The order of tabs inside a group** syncs; where the group sits doesn't (David).
   - **History:** each visit gets a stable sync id (one new numbered step in the history file; old visits catch up), and only the last 30 days are ever offered.
   - **Done (2026-11-13),** tested without iCloud (24 tests: the seal, two devices trading records, history). What it turned out to need:
     - **Only a device's own edits go out.** `SyncState` keeps the records as iCloud has them and what this device's fields looked like at its last look; a field is sent only when it changed here since then. So a record that arrives and can't be followed (the page someone's looking at isn't pulled away) is never sent back, and two devices never answer each other forever. The app takes changes whenever it saves the session, so each is stamped close to when it was made.
     - **The order words arrive in doesn't matter.** A group deleted on another device leaves its tabs loose here until that device's word on each arrives: a delete closes a tab whose record had a group; a "left its group" record keeps it loose. Ungroup and Close group both come out right whichever arrives first. Tabs that arrive before their group (or groups before their space) are handed back to try with the next batch.
     - **Checked again on arrival:** only http and https addresses, names cleaned as typed ones are, titles capped, a space color must be a short lowercase word (else Glacier), visits only from the last 30 days with a sync id of Firn's own shape. A sealed record is bound to its kind and id, so it can't be passed off as another, and one over 64 KB isn't opened.
     - **The last space stays** if another device deleted it (Firn always has one).
     - **For step 3:** the key in iCloud Keychain; persisting `SyncState`; the engine (`CKSyncEngine`) handing sealed bytes in and out; and a first sync between two devices that each start with an untouched space of their own (likely: an untouched only space gives way to the synced ones, as Arc import does).
3. **The engine and spaces.** A sync engine in both apps, and Settings › Sync: the two switches, off until turned on. Spaces sync. *Mac change:* the new Settings section. *Done:* a space made on the Mac appears on the iPhone, and a separate one is signed out there.
   - **Waits for the iPhone's phase 4** (David, 2026-11-13): the iPhone can't switch spaces yet, so a space from the Mac couldn't be reached there. Build phase 4 (`docs/IOS-PLAN.md`) first, then this step.
   - **Decided (David, 2026-11-13):**
     - **The iPhone's switch:** a small Settings sheet with only a Sync section for now, opened from the space menu; phase 6 fills it in.
     - **Only "Sync with iCloud" in step 3.** The Passwords switch comes in step 8, since before then it would do nothing.
     - **The first sync, same name joins:** a space that never synced joins another device's space with the same name. Its tabs, groups, and Basecamp stay, but it takes that space's id and data store, so it starts signed out on this device (sign-ins can't travel). A never-synced space with no tabs, groups, or tiles simply gives way. Every other space arrives as a new one.
   - **Found while planning (2026-11-13), to handle in this step:**
     - **One CloudKit environment for both apps.** The Mac (Developer ID) must use Production; the iPhone's builds from Xcode default to Development, a separate database, so they'd never see each other. The iPhone's entitlements name Production too (`com.apple.developer.icloud-container-environment`).
     - **Production needs its schema deployed.** CloudKit only makes record types on the fly in Development. Run once against Development to create `Space`, `TabGroup`, `Tab`, and `Visit` (each one encrypted bytes field), then David deploys the schema to Production in the CloudKit Console (a few clicks; Claude writes them out).
     - **Two devices can make two keys** if both turn sync on before iCloud Keychain has carried the first key across. Each record gets a short key id (a hash of the key, which says nothing about its contents); a record sealed with a key this device doesn't have waits, the Keychain is read again, and a device whose key lost re-seals and re-sends what it has.
     - **Kept between launches:** `SyncState`, the engine's own state, and records still waiting for their space or group, in one file next to the session.
4. **Groups.** Groups and their tabs. Deleting a group or space asks "from all your devices", and a group's delete has an Undo. *Done:* a group made on the Mac appears on the iPhone, and renaming it on the iPhone renames it on the Mac.
5. **"On your Mac" and "On your iPhone":** each device shares its open loose tabs' addresses and titles (kept current, removed as they close), and the command bar lists the other devices' under their names. *Mac change:* a command bar section.
6. **History.**
7. **Handoff.**
8. **Passwords to iCloud Keychain.** Its own short plan first: it moves where people's passwords live, so never a quiet switch.
9. **A look over.** The privacy wording (David's OK; `docs/privacy-page.md` and the README), "Turn off and delete from iCloud", the welcome's "Use iCloud" step (Mac and iPhone), the security check, VoiceOver, and the two-device test. *Done:* with sync off, nothing leaves either device.

## Step 1: what the facts turned out to be (2026-11-13)

- **`encryptedValues` is not end-to-end for most people.** Apple's own pages: CloudKit encrypts the fields on the device, but under standard iCloud protection the keys are "secured in Apple data centers"; only with Advanced Data Protection (opt-in, few people use it) are CloudKit encrypted fields end-to-end. So "encrypted so only your devices can read it" would be untrue for most people. By contrast, **iCloud Keychain and Safari's own history are end-to-end under both settings.** Sources: `support.apple.com/102651` (iCloud data security overview), the Platform Security guide's Advanced Data Protection page, and `CKRecord.encryptedValues`'s documentation.
  - **Decided (David, 2026-11-13): Firn's own encryption,** as long as it stays easy (nothing to set up, nothing to see): Firn encrypts each record's fields itself (CryptoKit, AES-GCM) with one key per iCloud account, kept as a synced iCloud Keychain item (`kSecAttrSynchronizable`), which is end-to-end for everyone. CloudKit then only ever stores sealed bytes; Apple can't read them with or without Advanced Data Protection. Cost: a small amount of code in step 2, and if someone resets their iCloud Keychain, the synced copy can't be read and each device re-uploads what it has (the same thing CloudKit's own encryption does then).
  - Not chosen: `encryptedValues` alone, worded honestly ("encrypted in your iCloud; with Advanced Data Protection, only your devices can read it"). Firn's sealed bytes still go in `encryptedValues`, so people with Advanced Data Protection get both layers.
- **Safari's history sync:** Apple publishes no number. Older reports (Elcomsoft, 2017) say iCloud holds about the last two weeks to 30 days, and a new device gets only the last 30 days. So "as Safari does" points to **the last 30 days**, with Firn's full year staying on each device. Unconfirmed; Apple doesn't document it.
- **Developer ID with CloudKit and push:** Apple's capabilities table has a Developer ID column, but its marks didn't come through in text. The developer portal will show it when the profile is made; that's the real check. Known details: the Mac's push key is `com.apple.developer.aps-environment` (iOS's is `aps-environment`; never both in one file), a Developer ID app must name `com.apple.developer.icloud-container-environment` (Production), and a profile made before a capability was turned on lacks it (make new ones).
- **Entitlements to add.** Mac (`Firn/Firn.entitlements`): `com.apple.developer.icloud-container-identifiers` (`iCloud.com.firnbrowser.firn`), `com.apple.developer.icloud-services` (`CloudKit`), `com.apple.developer.icloud-container-environment` (`Production`), and `com.apple.developer.aps-environment` (`production`). iPhone: a new `Firn iOS/Firn iOS.entitlements` with the same container and service, `aps-environment`, and `remote-notification` in `UIBackgroundModes` (Info.plist), so other devices' changes arrive. None of these sends anything by itself; nothing registers for pushes until step 3.

## Open

Nothing yet. (Settled 2026-11-13: loose tabs as in Arc, no Tabs setting, Firn's own encryption, and 30 days of history.)
