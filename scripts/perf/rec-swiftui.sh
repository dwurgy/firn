#!/bin/zsh
# A 30s SwiftUI-template recording of Firn on an iPhone (view body updates and their causes),
# then the trace's table of contents, to find the tables to export.
# Usage: scripts/perf/rec-swiftui.sh <device id> <name>
#   device id: from `xcrun devicectl list devices`; name: the .trace's name.
# Writes <name>.trace and <name>-toc.xml in the current folder (use a scratch folder).
set -e
device=$1; name=$2
rm -rf $name.trace
xcrun xctrace record --template "SwiftUI" --device $device --time-limit 30s --no-prompt \
  --output $name.trace --launch -- com.firnbrowser.firn 2>&1 | tail -1
xcrun xctrace export --input $name.trace --toc > $name-toc.xml
grep -o 'schema="[^"]*"' $name-toc.xml | sort -u
