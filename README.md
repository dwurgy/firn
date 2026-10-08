# firn
A calm, minimal browser that's easy for everyone: vertical tabs, spaces, split view, and link previews, without the learning curve. No telemetry; your data stays on your device. Built on Chromium. firnbrowser.com

## Running Firn on your computer

You need [Node.js](https://nodejs.org) (the LTS version) and Git installed once.

```
git clone https://github.com/dwurgy/firn.git
cd firn
npm install      # first time only, and whenever package.json changes
npm start        # opens Firn
```

**Windows: if PowerShell says "running scripts is disabled on this system"**, run this once and answer `Y`:

```
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

(Or use `npm.cmd install` / `npm.cmd start` instead.)

`npm start` runs Firn in development mode: if you change a file in `src/ui/`, the window updates by itself. For changes to `src/main.ts` or `src/preload.ts`, type `rs` in the terminal and press Enter to restart.

### The fast version, for everyday browsing

Development mode is slower than the real thing: Firn's own panels are served piece by piece, and React runs its extra-checking version. For everyday use, build the packaged app:

```
npm run package
```

Then open `out\Firn-win32-x64\Firn.exe` (on macOS, `out/Firn-darwin-*/Firn.app`). It starts several times faster and animates more smoothly. It keeps the same tabs, spaces, and history as `npm start`, but only one Firn can run at a time, so close the other first. After pulling new changes, run `npm run package` again.

### Downloads built by GitHub (Windows and Mac)

GitHub builds Firn by itself, on its own Windows and Mac computers, every time changes are pushed (see `.github/workflows/build.yml`). Nothing to run on your computer:

- **To try a change:** open the repository's **Actions** tab, click the latest **Build** run, and scroll to **Artifacts**: "Firn for Windows" holds `Firn Setup.exe`, and "Firn for macOS" holds a `.zip` with `Firn.app` (one app for every Mac, Apple chip or Intel). You need to be signed in to GitHub to download them; they're kept for 30 days.
- **To share a version:** on GitHub, open **Releases > Draft a new release**, create a tag named `v` plus the version in `package.json` (for example `v0.1.0`), use that version's headline from `CHANGELOG.md` as the title and paste the rest of its section as the description, and click **Publish release**. In about 15 minutes, GitHub attaches the Windows installer and the Mac zip to that release's page: the link to send to friends (anyone can download, no account needed). To publish the next version, raise `version` in `package.json` and add its notes at the top of `CHANGELOG.md` first.
- **Mac signing:** the Mac build reads six repository secrets: `MAC_CERTIFICATE_P12`, `MAC_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, and `APPLE_TEAM_ID` (see the top of `build.yml`). Without them, a push still builds a Mac app, but macOS won't vouch for it, and a release refuses to build.
- **The Safe Browsing key:** add it once as a repository secret named `FIRN_SAFE_BROWSING_KEY` (**Settings > Secrets and variables > Actions > New repository secret**), so GitHub's builds warn about scam sites too.

**Opening Firn on a Mac.** GitHub's Mac build signs Firn with Firn's Apple "Developer ID" and has Apple notarize it (check it for malware), so it opens like any app from the web: unzip the download, drag **Firn** into **Applications**, and open it. The first time, macOS asks once whether to open an app downloaded from the internet: click **Open**.

### Making the installer (to share Firn)

To give Firn to someone on Windows, build its installer:

```
npm run make
```

It takes a few minutes. The installer appears as `out\make\squirrel.windows\x64\Firn Setup.exe`: that one file is all you send. (Make sure `safe-browsing-key.txt` is in place first, so their copy warns about scam sites too.)

What happens when they open it: no wizard and no questions. A small window shows the Firn mark for a few seconds while it installs, then Firn opens with its welcome. It's added to the Start menu and the desktop, and can be removed like any app in Windows' **Settings > Apps**. Firn installs just for that person (in `%LOCALAPPDATA%\firn`), so it doesn't need administrator rights. Uninstalling keeps their tabs, history, and passwords (in `%APPDATA%\Firn`), so reinstalling brings everything back.

**Until Firn is code-signed**, Windows will say "Windows protected your PC" the first time: click **More info**, then **Run anyway**. Signing (a paid certificate) removes that; it's a later step.

### Updates

On Windows, an installed Firn keeps itself up to date. About a minute after it opens, and every 4 hours after that, it asks whether there's a newer version on Firn's GitHub **Releases** page. If there is, it downloads it quietly in the background, and the next time Firn is opened it's the new version. Nothing pops up and there's nothing to click.

- **Publishing an update** is the same as sharing a version (see "Downloads built by GitHub" above): raise `version` in `package.json`, then publish a release tagged `v` plus that version. Drafts and pre-releases are skipped. The release needs all the files GitHub attaches (`RELEASES` and the `.nupkg`, not just `Firn Setup.exe`), so wait until they're there.
- **From the first release on:** 0.1.0 already has this, so everyone who installs Firn gets later versions by themselves.
- **What it sends:** the question goes to update.electronjs.org, a free service the Electron project runs for open-source apps. It carries only Firn's version and the kind of computer (for example "win32-x64"), nothing about you or what you browse.
- **Mac and Linux** don't update themselves yet. Mac updates come next, now that Firn is notarized; Linux packages are updated by the system.

### Shortcuts (so far)

| Action | Windows / Linux | macOS |
| --- | --- | --- |
| Focus address bar | Ctrl+L | Cmd+L |
| Hide / show sidebar | Ctrl+S | Cmd+S |
| Command bar (new tab, find tabs and history, actions) | Ctrl+T | Cmd+T |
| Close tab (a pinned or Basecamp tab is unloaded instead) | Ctrl+W (or middle-click a tab) | Cmd+W |
| Pin / unpin tab | Ctrl+D | Cmd+D |
| Preview a link in Lookout | Shift+click | Shift+click |
| History | Ctrl+H | Cmd+Y |
| Settings | Ctrl+, | Cmd+, |
| Find in page (Enter / Shift+Enter: next / previous, Esc: close) | Ctrl+F (then F3 or Ctrl+G for next) | Cmd+F (then Cmd+G) |
| Zoom in / out / back to 100% (each site remembers its zoom) | Ctrl+= / Ctrl+- / Ctrl+0, or Ctrl+mouse wheel | Cmd+= / Cmd+- / Cmd+0 |
| Switch to space 1–9 | Ctrl+Shift+1…9 | Cmd+Shift+1…9 |
| Reopen closed tab | Ctrl+Shift+T | Cmd+Shift+T |
| Last-used tab (hold Ctrl and keep tapping Tab for the switcher) | Ctrl+Tab / Ctrl+Shift+Tab | Ctrl+Tab / Ctrl+Shift+Tab |
| Jump to tab 1–8 / last tab | Ctrl+1…8 / Ctrl+9 | Cmd+1…8 / Cmd+9 |
| Back / Forward | Alt+← / Alt+→ | Cmd+[ / Cmd+] |
| Reload | F5 or Ctrl+R | Cmd+R |
| Hard reload | Ctrl+Shift+R | Cmd+Shift+R |
| Developer tools for the page | F12 or Ctrl+Shift+I | Cmd+Option+I |

On a Mac, the menu bar has short, plain **Firn, File, Edit, View, Window, and Help** menus with the main ones (Firn > **Settings…** is Cmd+,). Shortcuts follow the Mac's habits: Cmd+H hides Firn and Cmd+Y opens History, like Safari and Chrome.

### Where things live

- `src/main.ts` — the main process: creates the window, handles shortcuts and messages from the UI.
- `src/tabs.ts` — the tab manager: tabs, spaces, Basecamp, pins, and their order. It doesn't depend on Electron.
- `src/engine/` — the browser engine: `engine.ts` describes what a web page can do, and `electron.ts` is Electron's version of it (the one place web pages are created).
- `src/types.ts` — the data model (spaces, tabs, window) shared by every part of the app.
- `src/preload.ts` — the narrow, safe bridge between Firn's UI and the main process.
- `src/ui/` — Firn's own interface (React): the window frame (`App.tsx`), the sidebar and tabs (`Sidebar.tsx`, `TabList.tsx`, `Basecamp.tsx`, `Spaces.tsx`), the sidebar peeking over the page while collapsed (`Peek.tsx`), the command bar, tab switcher, and find bar that float over the page (`Floating.tsx`), and the bar with the window buttons (`TopBar.tsx`).
- `tests/e2e/` — checks that start Firn and click through it (see `tests/e2e/README.md`).
- `brand/` — Firn's logo, wordmark, and app icons (see `brand/README.md`); `assets/` holds the app icon Firn itself uses.
- `src/url.ts` — decides whether what you typed is an address or a search.
- `src/ui/Welcome.tsx` and `src/welcome.ts` — the welcome shown the first time Firn opens.
- `src/safebrowsing.ts` — scam and malware warnings (Google Safe Browsing, checked on this computer).
- `src/passwords.ts` — saved passwords, encrypted on disk; `src/page-preload.ts` is the small helper inside web pages that spots sign-ins and fills saved ones.

### Welcome

The first time Firn opens, a short welcome fills the window with a calm sunrise over the snow ("First light") and sets things up, one card at a time. Every choice applies right away; from the space step on, the snow takes your space's color. You can skip it at any point (Esc or "Skip setup", bottom left). At the end, "Welcome in." appears and the browser rises into place from behind the snow (with "reduce motion" on, it simply fades).

1. **Where the address bar goes:** in the sidebar, or at the top.
2. **Your first space:** its name, color, and icon.
3. **Your everyday sites:** tick a few (Gmail, Calendar, Drive, YouTube…) to start Basecamp. Each shows its own icon, the same one Basecamp will show: Firn reads the site's front page while the welcome is open (without cookies, and nothing on it runs) and picks its best icon. If a site can't be reached, it shows a simple letter.
4. **Three tips:** Ctrl+T, right-click, and hiding the sidebar.

With no tabs open, the page shows the same sky and sunrise, with the snow and Firn's mark in the space's color, under "No open tabs". A new space starts out Glacier, Firn's own blue.

Type "welcome" in the command bar to see it again. (Someone who used Firn before the welcome existed doesn't get it on their next start.) Its headlines are set in Fraunces with its soft (rounded) corners on and its quirky "wonky" letters off, the same as Firn's wordmark, built into Firn (`src/ui/fonts/`, under the SIL Open Font License) so nothing is downloaded.

### Command bar

**Ctrl+T** opens the command bar. Type an address or a search; it also finds your open tabs in every space (tabs in another space say which, and picking one takes you there) and pages from your history. Type a couple of letters of an action to run it: **pin**, **basecamp**, **copy** link, **close**, **reopen**, **clear**, **sidebar**, **new space**, or a space's name to go there.

### Your session

Firn saves your tabs (with their back/forward history and scroll position), the sidebar's width and collapsed state, and the window's size and position, and brings them back next time. Only the tab you were on loads right away; the others load when you click them. The file lives in `%APPDATA%\Firn\session.json` on Windows; deleting it starts Firn fresh. Your browsing history (for the command bar) is kept next to it in `history.json`, and your recent downloads in `downloads.json`, both on your computer only.

### Basecamp and pinned tabs

**Basecamp** is the grid of favorite sites at the top of the sidebar: the same in every space, up to 12. Right-click any tab and choose **Add to Basecamp**. Drag a tile to move it; the others glide aside to make room. The site you're on glows softly in its own color.

**Pinned tabs** belong to one space and sit as rows under its name. Pin a tab with **Ctrl+D**, by right-clicking it, or by dragging it above the divider line (drag it back below to unpin). Click the space's name to fold its pins away (the pin you're on stays in view).

Both remember the address they were added at as their *home*: right-click for **Go back to home**. Closing one doesn't remove it; it unloads the page and resets it to home, and it rests a little dimmed until you click it again. The line below the pins has **Clear**, which closes the space's everyday tabs.

### Spaces

Spaces keep separate sets of pinned and everyday tabs, like Work and Personal. Switch with the icons at the bottom of the sidebar or **Ctrl+Shift+1…9**; **+** makes a new space and lets you name it right away. Each space has its own color, which softly tints the frame and glass (switching spaces cross-fades between them), and its own icon: one of 16 simple line icons drawn for Firn, shown in the space's color so it never looks like a website's icon. "Change icon…" opens a small grid of them under the space's name. Right-click a space's icon (or use the ⋯ next to its name) to rename it, change its icon or color, or delete it. Right-clicking any empty spot in the sidebar offers the same color, icon, and name options for the space you're in. Right-click a tab to move it to another space. Each space remembers the tab you were last on, and everything is saved with your session.

### History and settings

The **Firn mark** button at the bottom-left of the sidebar (beside the space icons) opens the Firn menu: New tab, New space, History, Passwords, Downloads, and Settings.

- **History** (Ctrl+H, or Cmd+Y on a Mac) shows the pages you've visited, newest first, grouped by day. Type to search, click a page to open it in a new tab, hover for ✕ to forget one, or use "Clear history…" (the last hour, today, or all time). It's kept on your computer only.
- **Settings** (Ctrl+,) has just a few things: the **search engine** (DuckDuckGo by default; Google, Bing, Ecosia, or Startpage), the **theme** (match the system, light, or dark), **where the address bar sits** (in the sidebar, or at the top in a bar across the window that's always there, with the window buttons, back, forward, and reload), **where downloads are saved**, and **privacy**: saved passwords, scam and malware warnings (on or off), clear history, clear cookies and site data (signs you out of websites; it asks first), and reset every site's permissions. Changes apply right away and are kept in `settings.json` next to your session.

### Saved passwords

After you sign in to a site, a small card asks **Save password for example.com?** with **Not now** and **Save**. Firn only asks once the sign-in worked (the page moved on), so a mistyped password isn't offered. If you sign in with a new password for a login Firn already has, it offers to **Update** it instead.

Next time, click into the site's sign-in form and Firn fills in your username and password. Nothing is filled until you click, and only on the very same site (and only over a secure https connection), so a look-alike site gets nothing.

**Passwords** in the Firn menu (or Settings → Privacy → Manage…, or "saved passwords" in the command bar) lists them: search, **Show**, **Copy**, or **Delete** each one. They're encrypted with your computer's own protection (on Windows, the same lock your Windows account uses) and kept in `passwords.json` next to your session, on this computer only. If the computer has no such protection available, Firn doesn't save passwords at all rather than keep them unprotected.

To do this, Firn adds a tiny helper to each web page that notices sign-in forms. It's walled off from the page: the site can't see it or talk to it, and it only reports a sign-in from the page's own main frame.

### Scam and malware warnings

Before any page opens, Firn checks its address against **Google Safe Browsing**, the same list of scam (phishing) and malware sites that Chrome, Firefox, and Safari use. A dangerous page is stopped before it loads, and a calm warning covers the tab ("This site may be a scam", "This site may harm your computer" or "This site may install unwanted software") with **Go back** (or close the tab, if there's nothing to go back to) and a quiet **Visit anyway**, which lets that address through until Firn closes. A dangerous link previewed in Lookout closes the preview and shows the same warning.

It's done the private way. Firn downloads Google's lists about every half hour; they hold only the first few bytes of a code made from each dangerous address, not the addresses. Every page is checked against them on this computer. Only when the start of a code matches, which is rare, does Firn ask Google for the full codes that start that way. It sends just those 4 bytes, which many addresses share, never the address. The lists live in a `safe-browsing` folder next to your session. To turn it off: Settings → Privacy → Scam and malware warnings → Off.

**Setting it up (once).** Google's service needs a free key, which gets built into your copy of Firn:

1. Go to [console.cloud.google.com](https://console.cloud.google.com), sign in, and create a project (call it "Firn").
2. In **APIs & Services → Library**, search for **Safe Browsing API** and click **Enable**.
3. In **APIs & Services → Credentials**, click **Create credentials → API key**. Then open the key and, under **API restrictions**, choose **Restrict key → Safe Browsing API**, and save.
4. Copy the key into a file named `safe-browsing-key.txt` in the `firn` folder (just the key, on one line). It's never uploaded to GitHub (`.gitignore` skips it).
5. Run `npm start` or `npm run package` again.

Without a key, Firn works the same but doesn't warn, and Settings says "Not set up in this copy of Firn". Google's free key is for non-commercial use; if Firn is ever sold, it should move to Google's paid version (Web Risk).

### Downloads

Downloads save straight to your Downloads folder, like Chrome (a name that's already taken gets " (1)"). While a file downloads, it shows at the bottom of the sidebar with a ring that fills as it arrives; hover it to cancel. Click a finished download to open it, or hover it to show it in its folder or take it off the list (the file stays). A download that was cancelled or didn't finish can be clicked to try again. PDFs open right in the tab, in Chromium's PDF viewer (its download button saves them like any other download). Finished downloads leave the sidebar on their own after half an hour; "Open downloads folder" in the command bar finds them later.

### Site permissions

Websites have to ask before using your **camera, microphone, location, notifications, or clipboard**, or before opening another app from a link (like a Zoom link). A small card at the top-left of the page asks, in plain words ("meet.google.com wants to use your camera and microphone"), with **Block** and **Allow**; Firn remembers the answer for that site. Pressing Esc closes it without answering, so the site can ask again later. A site that isn't on screen waits until you're looking at it. Harmless things (fullscreen, protected video like Netflix) are allowed without asking, and unusual hardware access (USB, serial ports) is refused.

Once a site has answers saved, a small button appears at the left of the address bar: click it to change an answer or choose "Ask again next time". Answers are kept in `permissions.json` next to your session, on your computer only.

(One limit of Electron, the base Firn is built on: before a site has been answered, a site that quietly checks first sees "blocked" rather than "not asked yet". Sites that simply ask, which is most of them, get the prompt as expected.)

### Right-click menu

Right-clicking a page shows a short menu with only what fits what you clicked:

- **A link:** open it in a new tab (in the background), open it in Lookout, or copy it. Email links offer "Copy email address".
- **An image:** save it or copy it.
- **Selected text:** copy it, or search for it.
- **A text box:** cut, copy, paste, select all, plus spelling suggestions for a misspelled word.
- **Anywhere else:** back, forward, reload.

### Lookout

**Shift+click** a link to preview it in Lookout: a rounded panel floating over the page, with the page dimmed behind it. Press **Esc** or click outside to close it, or use the button beside it to **open it as a tab** (the panel grows into the page and keeps everything, scroll position included). Links that open real popup windows, like "Sign in with Google", still open as windows.

Lookout also opens by itself in one case: in a **Basecamp or pinned tab**, a link that would open a new tab and goes to **another site** (say, a link in an email) opens in Lookout instead. Your pinned tab stays where it was and no stray tabs pile up; if you want to keep the page, use "open as tab". Middle-click or Ctrl+click such a link to open it as a background tab instead. Everyday tabs open links as usual.

### Split view

Right-click the tab you're on and choose **Split view with** to pick another tab to show beside it (or **New tab…** to open something new beside it), or right-click any other tab and choose **Split view with current tab**. The two sit side by side, each with its own address and back/forward. Click into a side to work in it (the address bar follows, and a soft ring shows which side it is). Drag the gap between them to resize, or double-click it to even them out. In the sidebar the pair is one row: click either half, or drag the row to move both. Hover it and use the button on the right (or right-click → **Separate split view**) to make them ordinary tabs again; closing one side leaves the other on its own. Split views are saved with your session.

### Frosted glass

On Windows 11 (22H2 or later) and macOS, the frame around the page is frosted glass while Firn is in focus: the colors behind the window softly show through. When you switch to another app it turns solid. To turn it off, start Firn with `FIRN_NO_GLASS=1` (in PowerShell: `$env:FIRN_NO_GLASS=1; npm start`).

### If something misbehaves

- **Ctrl+Shift+D** prints a snapshot of the window's layers, the cursor, and the screen to the terminal.
- If the window ever shows black or flickers behind the sidebar, try turning frosted glass off (above) and tell Claude.
- To log what the layers do as you use Firn, start it with debug logging. In PowerShell: `$env:FIRN_DEBUG=1; npm start` (close and reopen PowerShell to turn it off again).

## License

Firn's code is open source under the [Mozilla Public License 2.0](LICENSE), the license Firefox uses. Anyone can read it, check what Firn does with their data, and build on it; changes to Firn's own files have to stay open under the same license.

**The Firn name, logo, and app icons are not covered by the license.** They identify Firn itself, so please don't use them for your own version or anything that could be mistaken for Firn; give a version you share its own name and look. (That covers `brand/`, `assets/`, and `src/ui/firn-mark.svg`.)

Fraunces, the typeface in `src/ui/fonts/`, has its own license: the SIL Open Font License (`src/ui/fonts/Fraunces-OFL.txt`).
