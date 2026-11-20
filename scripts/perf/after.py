# The frames after each time a Firn function shows up on the main thread: when
# each began after the first, and how long it took (ms), from one Animation
# Hitches recording (rec.sh), which holds a time profile too. Export both first:
#   for s in hitches-updates time-profile; do xcrun xctrace export --input X.trace \
#     --xpath "/trace-toc/run[1]/data/table[@schema=\"$s\"]" > x-$s.xml; done
# Usage: after.py x BrowserScreen.openTab   (also: BrowserScreen.showTabs, pullMoved)
import sys, xml.etree.ElementTree as ET
def load(p):
    root=ET.parse(p).getroot(); ids={}
    for e in root.iter():
        if e.get('id'): ids[e.get('id')]=e
    return root,(lambda e: ids[e.get('ref')] if e.get('ref') is not None else e)
root,R=load(sys.argv[1]+'-time-profile.xml'); key=sys.argv[2]; T=[]
for row in root.iter('row'):
    th=row.find('thread'); bt=row.find('tagged-backtrace') or row.find('backtrace'); t=row.find('sample-time')
    if th is None or bt is None or 'Main Thread' not in R(th).get('fmt',''): continue
    if any(key in R(x).get('name','') for x in R(bt).iter('frame')): T.append(int(R(t).text)/1e9)
starts=[]
for t in sorted(T):
    if not starts or t-starts[-1]>0.5: starts.append(t)
root,R=load(sys.argv[1]+'-hitches-updates.xml'); U=sorted(set((int(R(r[0]).text)/1e9,int(R(r[1]).text)/1e6) for r in root.iter('row')))
for s in starts:
    seq=[(t,d) for t,d in U if s-0.03<=t<=s+0.16]
    print(f"{key} at {s:.3f}: "+' '.join(f"+{(t-seq[0][0])*1000:.0f}({d:.0f})" for t,d in seq))
