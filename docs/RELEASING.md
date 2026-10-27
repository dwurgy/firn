# Releasing Firn

How a new version of Firn gets from this repo to people's Macs. The reasoning behind each piece is in
`docs/HISTORY.md` ("Notarization" and "Plan: updates with Sparkle"); this page is the checklist.

## The pieces

- **The version and build number.** The version (`MARKETING_VERSION`, like 1.0.0) is what people see. The build
  number (`CURRENT_PROJECT_VERSION`, a whole number) is what Sparkle compares, so every release needs a higher one
  than the last. 1.0.0 is build 3 (builds 1 and 2 were the test update's 0.99.0 and 0.99.1).
- **`CHANGELOG.md`.** One section per version, in the notes' usual format: `## Firn x.y.z`, a bold one-line
  summary, a short paragraph, then `### New`, `### Better`, and `### Fixed`. The update window shows it, and so
  does the GitHub release.
- **`scripts/release.sh`.** Builds, checks, notarizes, and staples the app and a DMG, signs the DMG for Sparkle,
  and adds the release to `appcast.xml`. It publishes nothing.
- **A GitHub release** in `dwurgy/firn`, named `v<version>`, with the DMG attached. Updates and the website's
  download both point there.
- **`appcast.xml`**, the update feed. The repo keeps the master copy; installed copies of Firn read the one at
  `https://firnbrowser.com/appcast.xml`, which the website's own session puts in place.

## Once per Mac

A release can only be built on a Mac that has all of these. `release.sh` checks each one and says which is
missing.

1. **Xcode**, signed in with the Apple account on team 72LHR8K4P5.
2. **The Developer ID Application certificate** in the login Keychain.
3. **The "Firn Developer ID" provisioning profile** (saved passwords need it). Xcode › Settings › Accounts ›
   Download Manual Profiles fetches it.
4. **The notary password**, saved in the Keychain as `firn-notary`, from the App Store Connect API key (a .p8
   file kept out of the repo):

   ```bash
   xcrun notarytool store-credentials firn-notary --key <AuthKey.p8> --key-id <key id> --issuer <issuer id>
   ```

5. **Firn's private update key** in the login Keychain. On a new Mac, bring it back from the offline backup with
   Sparkle's `generate_keys -f <backup file>` (the tool is in Sparkle's `bin` folder inside the build's
   `DerivedData`). Without this key no update can ever reach people who already have Firn, so the backup matters
   more than anything else on this list.

## Before a release

1. **The code is ready.** Everything for this version is committed on `main`, and the tests pass:

   ```bash
   cd FirnCore && swift test --scratch-path ~/Library/Caches/FirnCore-build
   ```

2. **Raise the version and build number** in Xcode (the Firn target › General › Identity: Version and Build),
   which sets both the Debug and Release values. The build number goes up by one each release.
3. **Write the notes** in `CHANGELOG.md`, newest at the top, in plain words. Preview how the update window shows
   them:

   ```bash
   scripts/release-notes.sh 1.0.1 > ~/Desktop/notes.html && open ~/Desktop/notes.html
   ```

4. **Commit** the version and the notes. `release.sh` refuses to build from uncommitted code.
5. **A dry run** (optional, a few minutes, nothing sent to Apple) catches signing, key, and notes problems early:

   ```bash
   scripts/release.sh --check
   ```

## Building

```bash
scripts/release.sh
```

It takes about 10 minutes, most of it waiting for Apple. In order, it:

1. builds the Release archive and exports it, signed with the Developer ID;
2. checks the signature, team, Hardened Runtime, timestamp, provisioning profile, App Sandbox, and the update feed's
   address;
3. checks that the version has notes, that its build number is higher than any in `appcast.xml`, and that the
   Keychain's update key matches the one built into Firn;
4. notarizes and staples the app, then makes the DMG (Firn and an Applications shortcut), signs, notarizes, and
   staples it;
5. checks both the way Gatekeeper will;
6. signs the DMG for Sparkle and adds the release to the top of `appcast.xml`.

The DMG lands in `~/Library/Caches/Firn-release/Firn-<version>.dmg`, and Finder opens to it. Logs for every step
are in the same folder.

## Publishing

The order matters: the download has to exist before the feed points to it, or people would be offered an update
that can't download.

1. **Tag the code that was built**, before committing anything else, then commit the feed:

   ```bash
   git tag v1.0.1
   ```

   ```bash
   git commit -am "Firn 1.0.1: appcast"
   ```

   ```bash
   git push origin main v1.0.1
   ```

2. **Make the GitHub release** from that tag, with the DMG attached and the version's notes from `CHANGELOG.md`
   (the GitHub release page, or `gh release create v1.0.1 <the DMG> --title "Firn 1.0.1" --notes-file <notes>`).
   Download the DMG from the release page once to be sure it works.
3. **Publish the feed.** In the website's session (`dwurgy/firn-site`), ask for the repo's new `appcast.xml` to
   go to `https://firnbrowser.com/appcast.xml`, and for the website's download link to point to the new DMG if
   it names a version.

## After

- **Check the update.** On a Mac with the previous version, Firn › Check for Updates… should offer the new one,
  show its notes, install it, and relaunch with spaces, tabs, and passwords as they were.
- **Check a fresh download.** Open the DMG from the website, drag Firn to Applications, and open it: no warnings.
- Update "Where we are" in `CLAUDE.md` in a line.

## When something goes wrong

- **"uncommitted changes"**: commit or put aside what's changed; releases build from committed code only.
- **"no saved notary password"**: step 4 of "Once per Mac".
- **"write Firn x.y.z's notes"**: `CHANGELOG.md` has no `## Firn x.y.z` section, or the heading is spelled
  differently.
- **"build N isn't higher"**: raise the build number (Before a release, step 2).
- **"the Keychain's update key doesn't match"** or **"isn't in this Mac's Keychain"**: the private key is missing
  or wrong (step 5 of "Once per Mac"). Never make a new key pair to get past this: installed copies would refuse
  every update signed with it.
- **Notarization refused**: the script prints where Apple's reasons are saved (`notary-app-log.json` or
  `notary-dmg-log.json` in `~/Library/Caches/Firn-release`).
- **A bad release is out.** Take its entry out of `appcast.xml` (in the repo and on the website) so no one else
  is offered it, then fix and release a new version with a higher build number. An update can't be taken back
  from people who already installed it; only a newer one replaces it.
- **The .p8 is lost**: revoke the key in App Store Connect › Users and Access › Integrations, make a new one, and
  save it again (step 4). Nothing already released is affected.

## Trying an update without publishing

`scripts/test-update.sh` builds Firn 0.99.0 and 0.99.1 (notarized, signed with the update key) and serves a test
feed on this Mac only. Install 0.99.0 from its DMG, choose Firn › Check for Updates…, and it should update itself
to 0.99.1. `appcast.xml`, GitHub, and the website are never touched. Afterwards, put the usual Firn back in
Applications. It takes about 20 minutes; `scripts/test-update.sh --serve` serves copies already built.
