<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/svg/firn-lockup-on-dark.svg">
    <img src="brand/svg/firn-lockup.svg" alt="Firn" width="220">
  </picture>
</p>

<p align="center"><strong>A calm browser, made for Mac.</strong><br>
Privacy, simplicity, calm, and beauty.<br>
<a href="https://firnbrowser.com">firnbrowser.com</a></p>

---

Firn is a quiet, minimalist web browser built natively for the Mac in Swift, SwiftUI, and WebKit. It takes the best ideas from browsers like Arc, Dia, and Zen and brings them to everyone, not just power users, without the clutter.

The name comes from firn: the settled, compacted snow high on alpine glaciers. Quiet, clean, and still.

## What makes it different

- **Every space is its own browser.** Work and Personal each have their own tabs, sign-ins, cookies, and history. Signing into Gmail in one doesn't sign you in to the other. You can choose to share sign-ins between two spaces when you create one.
- **Basecamp.** A grid of your everyday sites at the top of each space, different in every space.
- **Groups.** Keep tabs together in soft frosted cards. Drag one tab onto another to make a group.
- **Tidied away.** Tabs you haven't looked at for a while drift quietly into a small button, so the sidebar stays clear. Nothing disappears without you seeing where it went.
- **Lookout.** Preview a link in a floating panel before deciding to keep it.
- **Split view.** Two pages side by side. Drag a tab onto the page to make one.
- **Command bar.** Press ⌘T to type an address, search, jump to a tab, or run an action by name.
- **Ad and tracker blocking.** Built in and on by default, and you can turn it off for a single site.

## Privacy

- **No telemetry.** Firn has no accounts, doesn't track you, and doesn't report how you use it. Your tabs and spaces stay on your Mac.
- **Spaces stay separate.** Each separate space keeps its own sign-ins, cookies, and site data, and nothing from one space shows up in another.
- **Ads and trackers are blocked** with the public EasyList and EasyPrivacy lists, built into the app. If a site breaks, open it and choose **Stop Blocking on** the site in the View menu.

**What Firn sends, and to whom.** Besides the websites you visit, Firn makes only these requests on its own:

- **Site icons**, fetched from the site you're on, without its cookies or your sign-ins. The welcome fetches the suggested sites' icons the same way.
- **Search suggestions**, only if you turn them on (they're off by default). Then your search engine sees what you type as you type it.
- **Scam checks**, by macOS's own Safe Browsing service (the same one Safari uses). It keeps a list of known scam sites on your Mac, and when a page might be on it, asks Apple using a short code calculated from the address, never the address itself. If the site is a known scam, you'll see a warning instead of the page.

Nothing else: no analytics, no update checks yet, and no Firn server.

## Requirements

macOS 14 Sonoma or later. Firn looks its best on macOS 26, with Liquid Glass.

## Building from source

You'll need Xcode.

```bash
xcodebuild -scheme Firn -destination 'platform=macOS' build
```

Most of Firn's logic lives in the `FirnCore` Swift package and can be tested from the command line:

```bash
cd FirnCore && swift test --scratch-path ~/Library/Caches/FirnCore-build
```

### Where things live

- `Firn/`: the app itself: the window, sidebar, Basecamp, command bar, Lookout, settings, the welcome, and `Theme.swift` (every color in one place).
- `FirnCore/Sources/FirnCore/Model/`: tabs, spaces, groups, split view, and saving your session. It doesn't depend on WebKit.
- `FirnCore/Sources/FirnCore/Engine/`: the browser engine. `PageController.swift` describes what a web page can do, and `WebKitPageController.swift` is WebKit's version of it. Views never touch WebKit directly.
- `FirnCore/Sources/FirnCore/Address/`: turning what you type into an address or a search.
- `FirnCore/Sources/FirnCore/Blocking/`: the ad and tracker lists, and the converter that turns them into WebKit's rules.
- `FirnCore/Tests/`: the tests.
- `brand/`: Firn's logo, wordmark, and app icons.
- `docs/`: design drafts and `HISTORY.md`, the story of how each part was built and why.

Your data lives in Firn's sandbox container, `~/Library/Containers/` on your Mac.

## License

Firn's code is open source under the [Mozilla Public License 2.0](LICENSE), the license Firefox uses. Anyone can read it, check what Firn does with their data, and build on it; changes to Firn's own files have to stay open under the same license.

**The Firn name, logo, and app icons are not covered by the license.** They identify Firn itself, so please don't use them for your own version or anything that could be mistaken for Firn; give a version you share its own name and look. (That covers `brand/` and the app icon.)

Firn includes the Fraunces typeface, under the [SIL Open Font License](Firn/Fonts/Fraunces-OFL.txt).
