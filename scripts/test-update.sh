#!/bin/zsh
# Tries a real update on this Mac without publishing anything: builds Firn 0.99.0 and 0.99.1 (notarized, signed
# with the update key, their feed on this Mac), then serves a test feed offering 0.99.1 at http://127.0.0.1:8123,
# reachable from this Mac only. appcast.xml, GitHub, and the website are never touched.
#
# Run from anywhere: scripts/test-update.sh            (builds both, about 20 minutes, then serves)
#                    scripts/test-update.sh --serve    (serves the copies already built)
# Then: install Firn 0.99.0 from its DMG, choose Firn › Check for Updates…, and it should update itself to 0.99.1.
# Afterwards, put your usual Firn back in Applications; your spaces, tabs, and passwords stay either way.
set -euo pipefail

REPO="${0:A:h:h}"
TEST_DIR="$HOME/Library/Caches/Firn-test-update"
FEED_DIR="$TEST_DIR/feed"

if [[ "${1:-}" != --serve ]]; then
	rm -rf "$TEST_DIR"
	# Build numbers 1 and 2; the real 1.0.0 gets 3 or higher, so it can update a test copy too.
	"$REPO/scripts/release.sh" --test 0.99.0 1
	"$REPO/scripts/release.sh" --test 0.99.1 2
fi
[[ -f "$FEED_DIR/appcast.xml" && -f "$FEED_DIR/Firn-0.99.0.dmg" ]] || { print -u2 "Stopped: nothing built yet; run without --serve"; exit 1 }

# 0.99.0 stays in the feed too, as a real feed keeps old versions; Sparkle offers only the newest.
print -P "%B==> Serving the test feed at http://127.0.0.1:8123 (Control-C stops it)%b"
open -R "$FEED_DIR/Firn-0.99.0.dmg"
exec python3 -I -m http.server 8123 --bind 127.0.0.1 --directory "$FEED_DIR"
