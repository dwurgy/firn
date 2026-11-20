# The main thread's busy stretches around one moment, in order, each with the
# Firn and SwiftUI work seen in it (ms), from a Time Profiler export (see
# mainthread.py). Shows which turn of a gesture loses frames.
# Usage: turns.py tp.xml <time s> [before s] [after s]   (the time: from after.py)
import sys, xml.etree.ElementTree as ET, collections
root=ET.parse(sys.argv[1]).getroot(); ids={}
for e in root.iter():
    if e.get('id'): ids[e.get('id')]=e
R=lambda e: ids[e.get('ref')] if e.get('ref') else e
g=float(sys.argv[2]); lo=g-(float(sys.argv[3]) if len(sys.argv)>3 else 0.04); hi=g+(float(sys.argv[4]) if len(sys.argv)>4 else 0.17)
keys=['pullMoved','pullEnded','beginGlide','Follower.tick','land(inCardOf','land(onPage','putStandIn','showTabs','openTab',
      'ShakeToUndo','hitTest','BrowserScreen.body.getter','TabOverview.body.getter','AddressBar.body.getter','OverviewBar.body',
      'GridCards','BasecampTiles.body','displayLinkTimer','flushTransactions','CA::Transaction::commit','layoutSubviews',
      'snapshot','sendEvent','DisplayList.ViewUpdater.render','swapIntoCard']
S=[]
for row in root.iter('row'):
    th=row.find('thread'); bt=row.find('tagged-backtrace') or row.find('backtrace'); t=row.find('sample-time')
    if th is None or bt is None or 'Main Thread' not in R(th).get('fmt',''): continue
    t=int(R(t).text)/1e9
    if not lo<=t<=hi: continue
    names=[R(x).get('name','') for x in R(bt).iter('frame')]
    if names and 'mach_msg' in names[0]: continue
    S.append((t,' '.join(names)))
S.sort(); runs=[]; cur=[]
for s in S:
    if cur and s[0]-cur[-1][0]>0.0016: runs.append(cur); cur=[]
    cur.append(s)
if cur: runs.append(cur)
for r in runs:
    c=collections.Counter(k for _,names in r for k in keys if k in names)
    print(f"{(r[0][0]-g)*1000:+5.0f}ms {len(r):3d}ms  "+', '.join(f"{k} {v}" for k,v in c.most_common(9)))
