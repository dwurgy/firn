#!/bin/zsh
# Builds Firn for release: archive, export, check the signature, notarize and staple the app, then wrap it in a
# DMG that's signed, notarized, and stapled too (so both open without warnings, even offline).
#
# Needs, once: xcrun notarytool store-credentials firn-notary --apple-id <you> --team-id 72LHR8K4P5
# Run from anywhere: scripts/release.sh   (another saved name: NOTARY_PROFILE=name scripts/release.sh)
# scripts/release.sh --check builds and checks the signature only; nothing is sent to Apple.
set -euo pipefail

CHECK_ONLY=false
[[ "${1:-}" == --check ]] && CHECK_ONLY=true
NOTARY_PROFILE="${NOTARY_PROFILE:-firn-notary}"
TEAM_ID=72LHR8K4P5
REPO="${0:A:h:h}"
# Outside ~/Documents: Finder metadata there breaks code signing.
WORK="$HOME/Library/Caches/Firn-release"

step() { print -P "%B==> $1%b" }
fail() { print -u2 "Stopped: $1"; exit 1 }
# Runs a loud command quietly; on failure shows the end of its log.
quiet() {
	local log="$WORK/$1.log"; shift
	"$@" >"$log" 2>&1 || { tail -30 "$log"; fail "$(basename "$1") failed (full log: $log)" }
}

# Notarizes one file and waits for Apple's answer; on a refusal, shows Apple's reasons.
notarize() {
	local file=$1 name=$2
	step "Sending $name to Apple for notarization (usually a few minutes)"
	xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json \
		>"$WORK/notary-$name.json" 2>"$WORK/notary-$name.err" || true
	local notary_status id
	notary_status=$(plutil -extract status raw "$WORK/notary-$name.json" 2>/dev/null || echo "no answer")
	id=$(plutil -extract id raw "$WORK/notary-$name.json" 2>/dev/null || echo "")
	if [[ "$notary_status" != Accepted ]]; then
		cat "$WORK/notary-$name.err" >&2
		if [[ -n "$id" ]]; then
			xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$WORK/notary-$name-log.json" >/dev/null 2>&1 &&
				print -u2 "Apple's reasons: $WORK/notary-$name-log.json"
		fi
		fail "notarization of $name: $notary_status"
	fi
	xcrun stapler staple "$file" >/dev/null || fail "stapling $name"
}

cd "$REPO"
$CHECK_ONLY || [[ -z "$(git status --porcelain)" ]] || fail "uncommitted changes; a release is built from committed code only."
$CHECK_ONLY || xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
	fail "no saved notary password named \"$NOTARY_PROFILE\" (see the top of this script)."

rm -rf "$WORK"; mkdir -p "$WORK"

step "Building the Release archive"
quiet archive xcodebuild archive -scheme Firn -configuration Release -destination 'generic/platform=macOS' \
	-archivePath "$WORK/Firn.xcarchive" -derivedDataPath "$WORK/DerivedData"
quiet export xcodebuild -exportArchive -archivePath "$WORK/Firn.xcarchive" -exportPath "$WORK/export" \
	-exportOptionsPlist "$REPO/scripts/ExportOptions.plist"
APP="$WORK/export/Firn.app"
INFO="$APP/Contents/Info.plist"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO")
BUILD=$(plutil -extract CFBundleVersion raw "$INFO")

step "Checking the signature and entitlements (Firn $VERSION, build $BUILD)"
codesign --verify --deep --strict "$APP" 2>"$WORK/verify.log" || { cat "$WORK/verify.log"; fail "signature doesn't verify" }
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
IDENTITY=$(print -r -- "$SIGNATURE" | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p')
[[ -n "$IDENTITY" ]] || fail "not signed with a Developer ID"
print -r -- "$SIGNATURE" | grep -q "^TeamIdentifier=$TEAM_ID$" || fail "signed by another team"
print -r -- "$SIGNATURE" | grep -q "flags=.*(runtime)" || fail "Hardened Runtime is off"
print -r -- "$SIGNATURE" | grep -q "^Timestamp=" || fail "no secure timestamp"
[[ -f "$APP/Contents/embedded.provisionprofile" ]] || fail "the provisioning profile isn't inside (saved passwords need it)"
codesign -d --entitlements - --xml "$APP" >"$WORK/entitlements.plist" 2>/dev/null
ent() { /usr/libexec/PlistBuddy -c "Print :$1" "$WORK/entitlements.plist" 2>/dev/null || echo missing }
[[ "$(ent com.apple.security.app-sandbox)" == true ]] || fail "App Sandbox is off"
[[ "$(ent com.apple.security.get-task-allow)" != true ]] || fail "a debugging entitlement is still on"
if $CHECK_ONLY; then step "Checks pass; nothing was sent to Apple: $APP"; exit 0; fi

# The app first, so a copy dragged out of the DMG carries its own ticket.
quiet zip-app ditto -c -k --keepParent "$APP" "$WORK/Firn-app.zip"
notarize "$WORK/Firn-app.zip" app
rm "$WORK/Firn-app.zip"

step "Making the DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Firn.app"
ln -s /Applications "$STAGE/Applications"
DMG="$WORK/Firn-$VERSION.dmg"
quiet dmg hdiutil create -volname Firn -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG" || fail "signing the DMG"
notarize "$DMG" dmg

step "Checking it the way Gatekeeper will"
spctl -a -t exec -vv "$APP" 2>&1 | grep -q "source=Notarized Developer ID" || fail "Gatekeeper doesn't accept the app"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | grep -q "source=Notarized Developer ID" ||
	fail "Gatekeeper doesn't accept the DMG"
xcrun stapler validate "$DMG" >/dev/null || fail "the DMG's ticket doesn't validate"

step "Done: $DMG"
open -R "$DMG"
