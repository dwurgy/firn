#!/bin/zsh
# Takes the website's screenshots from demo mode (docs/HISTORY.md, "Demo mode"): each shot in light and dark,
# captured window by window into ~/Pictures/Firn demo shots/<date>. Demo mode runs on its own throwaway data, so
# nothing from your own browsing shows up, and your settings come back at the next ordinary launch.
#
# Run from anywhere: scripts/demo-shots.sh                  (builds Firn first, then takes every shot)
#                    scripts/demo-shots.sh <Firn.app>       (uses that copy)
#                    scripts/demo-shots.sh <Firn.app> hero  (only the shots named after it)
# Quit Firn first. The first time, macOS asks to let the terminal record the screen (System Settings › Privacy &
# Security › Screen & System Audio Recording); allow it, then run this again. Keep the pointer off the window.
set -euo pipefail

REPO="${0:A:h:h}"
ALL=(hero work trip command lookout split tidied history empty peek)
SHOTS=("${ALL[@]}")
# Firn's sandbox lets it write only here; the file is removed after each shot.
READY="$HOME/Downloads/.firn-demo-shot"
OUT="$HOME/Pictures/Firn demo shots/$(date +%Y-%m-%d)"

pgrep -xq Firn && { print -u2 "Stopped: quit Firn first (the demo shares its settings)"; exit 1 }

if [[ -n "${1:-}" ]]; then
	APP="${1:A}"
	shift
else
	print -P "%B==> Building Firn%b"
	xcodebuild -project "$REPO/Firn.xcodeproj" -scheme Firn -destination 'platform=macOS' build 2>&1 | grep -E "error|BUILD" || true
	APP="$(xcodebuild -project "$REPO/Firn.xcodeproj" -scheme Firn -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/Firn.app"
fi
[[ -d "$APP" ]] || { print -u2 "Stopped: no Firn.app at $APP"; exit 1 }
(( $# )) && SHOTS=("$@")

mkdir -p "$OUT"
for shot in "${SHOTS[@]}"; do
	number=${ALL[(i)$shot]}
	(( number > ${#ALL} )) && { print -u2 "Stopped: no shot named $shot"; exit 1 }
	for look in light dark; do
		name="$(printf %02d $number)-$shot-$look"
		print -P "%B==> $name%b"
		rm -f "$READY"
		args=(--demo "--shot=$shot")
		[[ $look == dark ]] && args+=(--dark)
		open -n "$APP" --args "${args[@]}"

		# Firn writes the window's number once the shot's pages have loaded.
		for _ in {1..120}; do [[ -s "$READY" ]] && break; sleep 0.5; done
		[[ -s "$READY" ]] || { print -u2 "Stopped: $name never got ready"; pkill -x Firn || true; exit 1 }
		window="$(<"$READY")"
		if ! screencapture -x -l "$window" "$OUT/$name.png" || [[ ! -s "$OUT/$name.png" ]]; then
			print -u2 "Stopped: couldn't capture the window (allow screen recording for this terminal, then run again)"
			rm -f "$READY"
			exit 1
		fi

		# Removing the file tells Firn to quit; wait for it before the next launch.
		rm -f "$READY"
		for _ in {1..40}; do pgrep -xq Firn || break; sleep 0.25; done
		pgrep -xq Firn && pkill -x Firn
		sleep 1
	done
done
print -P "%B==> Done:%b $OUT"
open "$OUT"
