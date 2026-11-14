#!/bin/zsh
# A 30s Animation Hitches recording of Firn on an iPhone, then a summary.
# Usage: scripts/perf/rec.sh <device id> <name> [trial]
#   device id: from `xcrun devicectl list devices`; name: the .trace's name;
#   trial: optional, passed as `-FirnPerfTrial <trial>` (see docs/IOS-PLAN.md, 2i).
# Writes <name>.trace and <name>-hitch.xml in the current folder (use a scratch folder).
set -e
device=$1; name=$2; trial=$3
here=${0:A:h}
rm -rf $name.trace
xcrun xctrace record --template "Animation Hitches" --device $device --time-limit 30s --no-prompt \
  --output $name.trace --launch -- com.firnbrowser.firn ${trial:+-FirnPerfTrial} $trial 2>&1 | tail -1
xcrun xctrace export --input $name.trace --xpath '/trace-toc/run[1]/data/table[@schema="hitches"]' > $name-hitch.xml
python3 -I $here/hitches.py $name-hitch.xml
