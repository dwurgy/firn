#!/usr/bin/env python3
# Firn's view updates from a SwiftUI-template trace, read as a stream (the table can be gigabytes).
# Usage: python3 -I scripts/perf/swiftui.py <swiftui-updates.xml> [module]
#   Export the table with:
#   xcrun xctrace export --input X.trace --xpath '/trace-toc/run[1]/data/table[@schema="swiftui-updates"]'
# Prints, for views in `module` (default Firn), how many times each ran and for how long,
# their root causes, and a timeline of 50ms buckets where many Firn views ran at once
# (a gesture's turns, where the whole screen runs again).
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

path = sys.argv[1]
module = sys.argv[2] if len(sys.argv) > 2 else "Firn"
COLS = ["start", "duration", "id", "update-type", "allocations", "description", "category",
        "view-hierarchy", "module", "view-name", "process", "thread", "root-causes", "severity",
        "downstream-cost"]
KEEP = {"string", "swiftui-update", "description-set", "event-concept"}

def split_causes(text):
    """The cause list is one comma-joined string; split it outside <…>."""
    out, depth, cur = [], 0, ""
    for ch in text:
        depth += (ch == "<") - (ch == ">")
        if ch == "," and depth == 0:
            out.append(cur.strip()); cur = ""
        else:
            cur += ch
    out.append(cur.strip())
    return set(out)

fmt = {}  # id -> fmt, for the tags whose values repeat
times = {}  # id -> raw value, for start times and durations
count, total = Counter(), Counter()
causes = defaultdict(Counter)
types = Counter()
buckets = defaultdict(Counter)  # 50ms bucket -> view -> runs
depth = 0
row = None
for ev, el in ET.iterparse(path, events=("start", "end")):
    if ev == "start":
        depth += 1
        if el.tag == "row":
            row, depth = [], 0
        continue
    depth -= 1
    if el.tag == "row":
        r = dict(zip(COLS, row))
        if r.get("module") == module:
            name = r.get("view-name") or r.get("description")
            dur = int(r.get("duration") or 0)
            count[name] += 1
            total[name] += dur
            types[r.get("update-type")] += 1
            for c in split_causes(r.get("root-causes") or "?"):
                causes[name][c] += 1
            buckets[int(r["start"]) // 50_000_000][name] += 1
        row = None
        el.clear()
        continue
    i, ref = el.get("id"), el.get("ref")
    if i and el.tag in KEEP:
        fmt[i] = el.get("fmt")
    if row is not None and depth == 0:  # a direct child of the row
        if el.tag in ("start-time", "duration"):
            if i:
                times[i] = el.text
            row.append(times.get(ref) if ref else el.text)
        elif ref:
            row.append(fmt.get(ref))
        elif el.tag == "sentinel":
            row.append(None)
        else:
            row.append(el.get("fmt"))
        if el.tag not in KEEP:
            el.clear()

print(f"Update types in {module}: {dict(types)}\n")
print(f"{'runs':>6} {'ms':>8}  view (top 40 by time)")
for name, t in total.most_common(40):
    print(f"{count[name]:>6} {t/1e6:>8.1f}  {name}")
print("\nRoot causes, the 15 busiest views:")
for name, _ in total.most_common(12):
    print(f"  {name} ({count[name]} runs):")
    for c, n in causes[name].most_common(8):
        print(f"      {n:>5}  {c[:110]}")
print("\nBusy moments (50ms buckets with 30+ Firn view runs):")
for b in sorted(buckets):
    c = buckets[b]
    if sum(c.values()) >= 30:
        top = ", ".join(f"{v} {n}" for v, n in c.most_common(6))
        print(f"  {b*0.05:6.2f}s  {sum(c.values()):4}  {top}")
