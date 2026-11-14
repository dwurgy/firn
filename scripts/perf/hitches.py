# Dropped frames in an Animation Hitches export (rec.sh): how many, their
# total, and the median offscreen passes a frame. Usage: hitches.py <name>-hitch.xml
import sys, re, xml.etree.ElementTree as ET, statistics
root=ET.parse(sys.argv[1]).getroot(); ids={}
for e in root.iter():
    if e.get('id'): ids[e.get('id')]=e
R=lambda e: ids[e.get('ref')] if e.get('ref') is not None else e
n=0; tot=0.0; passes=[]
for row in root.iter('row'):
    ch=[R(x) for x in row]
    d=ch[1].get('fmt'); nar=ch[-1].get('fmt') or ''
    ms=float(d.split()[0])*(1000 if d.endswith(' s') else 1)
    if ms>1000: continue
    n+=1; tot+=ms
    m=re.search(r'(\d+) offscreen', nar)
    if m: passes.append(int(m.group(1)))
print(f"{sys.argv[1]}: hitches {n}, {tot:.0f}ms; offscreen passes median {statistics.median(passes) if passes else 0}, frames flagged {len(passes)}")
