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

# Notarizes one file, waits for Apple's answer, and staples the ticket (onto the third argument if given: a zip
# can't hold one, so the app inside gets it); on a refusal, shows Apple's reasons.
notarize() {
	local file=$1 name=$2 target=${3:-$1}
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
	xcrun stapler staple "$target" >/dev/null || fail "stapling $name"
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

# Sparkle compares build numbers, not versions, so each release needs a higher one (CURRENT_PROJECT_VERSION).
step "Checking the release notes, build number, and update key"
NOTES=$("$REPO/scripts/release-notes.sh" "$VERSION") || fail "write Firn $VERSION's notes in CHANGELOG.md first"
[[ "$NOTES" != *']]>'* ]] || fail "the notes can't contain ]]>"
APPCAST="$REPO/appcast.xml"
[[ "$BUILD" == <-> ]] || fail "build number \"$BUILD\" isn't a whole number"
LATEST=$(sed -n 's|.*<sparkle:version>\([0-9]*\)</sparkle:version>.*|\1|p' "$APPCAST" | sort -n | tail -1)
(( BUILD > ${LATEST:-0} )) || fail "build $BUILD isn't higher than build $LATEST, already in appcast.xml"
! grep -q "<sparkle:shortVersionString>$VERSION</" "$APPCAST" || fail "Firn $VERSION is already in appcast.xml"
SPARKLE_BIN="$WORK/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
# A DMG signed with the wrong key would be refused by every installed Firn.
KEYCHAIN_KEY=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null) || fail "Firn's private update key isn't in this Mac's Keychain"
[[ "$KEYCHAIN_KEY" == "$(plutil -extract SUPublicEDKey raw "$INFO")" ]] ||
	fail "the Keychain's update key doesn't match SUPublicEDKey in Info.plist"
if $CHECK_ONLY; then step "Checks pass; nothing was sent to Apple: $APP"; exit 0; fi

# The app first, so a copy dragged out of the DMG carries its own ticket.
quiet zip-app ditto -c -k --keepParent "$APP" "$WORK/Firn-app.zip"
notarize "$WORK/Firn-app.zip" app "$APP"
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

# Last, since stapling changes the DMG and the signature covers every byte.
step "Signing the DMG for updates and adding it to appcast.xml"
SPARKLE_SIG=$("$SPARKLE_BIN/sign_update" "$DMG") || fail "Sparkle couldn't sign the DMG"
[[ "$SPARKLE_SIG" == sparkle:edSignature=\"*\"\ length=\"<->\" ]] || fail "unexpected answer from sign_update: $SPARKLE_SIG"
DOWNLOAD="https://github.com/dwurgy/firn/releases/download/v$VERSION/Firn-$VERSION.dmg"
cat >"$WORK/item.xml" <<EOF
		<item>
			<title>Firn $VERSION</title>
			<pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
			<sparkle:version>$BUILD</sparkle:version>
			<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
			<sparkle:minimumSystemVersion>$(plutil -extract LSMinimumSystemVersion raw "$INFO")</sparkle:minimumSystemVersion>
			<description><![CDATA[
$NOTES
			]]></description>
			<enclosure url="$DOWNLOAD" type="application/octet-stream" $SPARKLE_SIG/>
		</item>
EOF
awk 'FNR == NR { item = item $0 "\n"; next } { print } /New releases go below this line/ { printf "%s", item }' \
	"$WORK/item.xml" "$APPCAST" >"$WORK/appcast.xml"
xmllint --noout "$WORK/appcast.xml" 2>/dev/null || fail "the new appcast.xml isn't valid XML ($WORK/appcast.xml)"
mv "$WORK/appcast.xml" "$APPCAST"

step "Done: $DMG"
print "Nothing is published yet. To release Firn $VERSION:"
print "  1. Commit appcast.xml."
print "  2. On GitHub, make release v$VERSION and attach $(basename "$DMG") (its notes: Firn $VERSION's section of CHANGELOG.md)."
print "  3. Once the DMG downloads, have the website session put appcast.xml at https://firnbrowser.com/appcast.xml."
open -R "$DMG"
