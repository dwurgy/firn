# Main-thread time by function (inclusive ms, idle waiting left out), from a
# Time Profiler export: xcrun xctrace export --input X.trace --xpath
# '/trace-toc/run[1]/data/table[@schema="time-profile"]' > tp.xml; mainthread.py tp.xml
import sys, xml.etree.ElementTree as ET, collections
root=ET.parse(sys.argv[1]).getroot(); ids={}
for e in root.iter():
    if e.get('id'): ids[e.get('id')]=e
R=lambda e: ids[e.get('ref')] if e.get('ref') else e
c=collections.Counter(); tot=0
for row in root.iter('row'):
    th=row.find('thread'); bt=row.find('tagged-backtrace') or row.find('backtrace')
    if th is None or bt is None or 'Main Thread' not in R(th).get('fmt',''): continue
    names=[R(x).get('name','') for x in R(bt).iter('frame')]
    if names and 'mach_msg' in names[0]: continue
    tot+=1
    for n in set(names): c[n]+=1
print('busy ms',tot)
skip=('start','main','UIApplicationMain','GSEventRunModal','__CFRunLoopRun','_CFRunLoopRunSpecificWithOptions','static App.main()','runApp','KitRendererCommon')
for k,v in c.most_common(4000):
    if any(k.startswith(s) for s in skip): continue
    print(v,k[:120])
