# Ad and tracker lists

Firn blocks ads and trackers with two lists from [EasyList](https://easylist.to), shipped inside the app. Firn never downloads them.

- `easylist.txt`: ads, from https://easylist.to/easylist/easylist.txt
- `easyprivacy.txt`: trackers, from https://easylist.to/easylist/easyprivacy.txt

Beside them, `firn.txt` holds Firn's own few additions: ad servers those lists don't block yet, each with whose they are and when they were found. It's Firn's own (MPL 2.0), not EasyList's. When a refreshed EasyList blocks one of them, take it out of `firn.txt`.

The EasyList authors offer the lists under either GPL-3.0 or CC BY-SA 3.0 (https://easylist.to/pages/licence.html). Firn uses them under **Creative Commons Attribution-ShareAlike 3.0 Unported** (https://creativecommons.org/licenses/by-sa/3.0/). Credit goes to the EasyList authors. Firn converts them unchanged into WebKit's rule format when it first runs; those converted rules are shared under the same license. This license covers only these two files, not Firn's code (MPL 2.0) or brand.

## Refreshing them

Replace both files with fresh copies from the addresses above, then run the FirnCore tests: `BlockListTests` checks that every rule still fits WebKit's limits and compiles. Firn notices the new lists on its next launch and compiles them again.

## Left alone on purpose

- **Ad-Shield** (`html-load.com` and addresses that change on their own): when a site's ads are blocked, it serves them again through its own servers, and if those are blocked too, the site replaces the page with "An ad blocker is preventing this page from loading". Content blockers can't get past it, since they can't change a page's own scripts. So Firn leaves it alone: a few ads get through on those sites, but the page works (David, 2026-11-28; seen on chelseasmessyapron.com).
