# Firn's end-to-end checks

These start the real Firn and click through it like a person would, then
say PASS or FAIL for each thing they check (about 200 in all). Run them
after every change, before committing.

```
bash tests/e2e/run.sh              # every check (about 10 minutes)
bash tests/e2e/run.sh settings     # just one, or a few: run.sh perm lookout
```

## Where they run

In Claude's cloud workspace (Linux). They need what it already has: a
virtual screen (`Xvfb`), ImageMagick's `import` for screenshots, Python 3,
and Playwright installed globally. They also assume Firn keeps its data in
`/root/.config/Firn`, as it does there. They won't run on Windows or a Mac
as they are.

Each check starts from a clean slate (no saved tabs, the welcome already
done), so they never touch anyone's real Firn data, only the workspace's.
Screenshots and logs land in `tests/e2e/out/` (not saved in Git).

## What's here

| Check          | What it covers                                                        |
| -------------- | --------------------------------------------------------------------- |
| `all`          | The basics: tabs, the sidebar, hiding and peeking, the top bar        |
| `settings`     | Settings: every option, saved and applied                             |
| `perm`         | Site permissions (camera, location…): the question and the answer     |
| `ctxmenu`      | Right-click menus on pages, links, images and text                    |
| `lookout`      | Lookout: opening, closing, promoting to a tab                         |
| `addrtop`      | The address bar "At the top"                                          |
| `downloads`    | Downloads: saving, progress, opening, the list                        |
| `passwords`    | Saved passwords: offering to save, filling in, the list               |
| `safebrowsing` | Scam and malware warnings (against a pretend Google list)             |
| `welcome`      | The welcome, the first time Firn opens                                |
| `brand`        | The Fraunces headings                                                 |
| `bottom`       | The bottom row of the sidebar (the Firn button, spaces)               |
| `updates`      | Automatic updates stay off on a copy that isn't installed on Windows  |
| `macmenu`      | The Mac menu bar (shown on Linux for the check): menus and choices    |
| `basecamp`     | Basecamp: dragging tiles to reorder them                              |
| `whatsnew`     | What's new: after an update, from the menus, never on a fresh install |

`site/` is a tiny test website the checks visit (served on this computer
only). `cdp.cjs`, `playwright.cjs` and `warp.py` are small helpers.

## Known flaky checks

These sometimes fail without anything being wrong; run them again before
worrying:

- `ctxmenu`: "Search opens a search for it in a new tab" needs the real
  internet, which the workspace may block.
- `all`: "on the way up, bar is covered in step with the page" and "bar
  edge matches page edge while gliding" are timing-sensitive by a frame.
