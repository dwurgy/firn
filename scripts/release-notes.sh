#!/bin/zsh
# Prints one version's notes from CHANGELOG.md as the small HTML page Sparkle's update window shows.
# The format is the one Firn's notes have always used: "## Firn 1.0.0", a bold one-line summary, a short
# paragraph, then "### New" / "### Better" / "### Fixed" lists. The "## Firn" heading itself is left out:
# the update window already names the version.
#
# Preview one: scripts/release-notes.sh 1.0.0 > ~/Desktop/notes.html && open ~/Desktop/notes.html
set -euo pipefail

VERSION=${1:?usage: scripts/release-notes.sh <version>}
CHANGELOG="${0:A:h:h}/CHANGELOG.md"
[[ -f "$CHANGELOG" ]] || { print -u2 "No CHANGELOG.md"; exit 1 }

# Firn's own colors and type (Theme.swift), so the notes read like Firn in light and dark.
cat <<'EOF'
<style>
:root { color-scheme: light dark; }
body { font: 13px/1.5 -apple-system, system-ui, sans-serif; color: #241F1B; margin: 4px 2px; }
h3 { font-size: 12px; font-weight: 600; color: #5E564E; margin: 16px 0 4px; }
p { margin: 0 0 10px; }
ul { margin: 0; padding-left: 18px; }
li { margin: 0 0 6px; }
@media (prefers-color-scheme: dark) {
  body { color: #F5F1EC; }
  h3 { color: #D4CDC5; }
}
</style>
EOF

awk -v want="## Firn $VERSION" '
	function inline(s,   out) {
		gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s)
		out = ""
		while (match(s, /\*\*[^*]+\*\*/)) {
			out = out substr(s, 1, RSTART - 1) "<strong>" substr(s, RSTART + 2, RLENGTH - 4) "</strong>"
			s = substr(s, RSTART + RLENGTH)
		}
		return out s
	}
	function close_block() {
		if (inpara) { print "<p>" para "</p>"; inpara = 0; para = "" }
		if (inlist) { print "</ul>"; inlist = 0 }
	}
	$0 == want { found = 1; on = 1; next }
	on && /^## / { on = 0 }
	!on { next }
	/^[[:space:]]*$/ { close_block(); next }
	/^### / { close_block(); print "<h3>" inline(substr($0, 5)) "</h3>"; next }
	/^- / {
		if (inpara) { print "<p>" para "</p>"; inpara = 0; para = "" }
		if (!inlist) { print "<ul>"; inlist = 1 }
		print "<li>" inline(substr($0, 3)) "</li>"; next
	}
	{
		if (inlist) { print "</ul>"; inlist = 0 }
		para = inpara ? para " " inline($0) : inline($0); inpara = 1
	}
	END { close_block(); if (!found) exit 2 }
' "$CHANGELOG" || { print -u2 "CHANGELOG.md has no \"## Firn $VERSION\" section."; exit 1 }
