# Main-thread stretches longer than one 120Hz frame (8.3ms), each a likely
# dropped frame, with the Firn code under each, from a Time Profiler export
# (see mainthread.py). Usage: longruns.py tp.xml [from s] [to s]
import sys, re, xml.etree.ElementTree as ET, collections
root=ET.parse(sys.argv[1]).getroot(); ids={}
lo=float(sys.argv[2])*1000 if len(sys.argv)>2 else 0; hi=float(sys.argv[3])*1000 if len(sys.argv)>3 else 1e9
for e in root.iter():
    if e.get('id'): ids[e.get('id')]=e
R=lambda e: ids[e.get('ref')] if e.get('ref') else e
S=[]
for row in root.iter('row'):
    th=row.find('thread'); bt=row.find('tagged-backtrace') or row.find('backtrace'); t=row.find('sample-time')
    if th is None or bt is None or 'Main Thread' not in R(th).get('fmt',''): continue
    names=[R(x).get('name','') for x in R(bt).iter('frame')]
    if names and 'mach_msg' in names[0]: continue
    S.append((int(R(t).text)/1e6,names))
S.sort(key=lambda x:x[0]); runs=[]; cur=[S[0]]
for s in S[1:]:
    if s[0]-cur[-1][0]<1.6: cur.append(s)
    else: runs.append(cur); cur=[s]
runs.append(cur)
firn=re.compile(r'^(?!.*(closure|partial|thunk))(\w+)\.[\w.]+(getter|\()')
long=[r for r in runs if len(r)>8 and lo<r[0][0]<hi]
print(f'stretches over 8.3ms: {len(long)}, {sum(len(r) for r in long)}ms in all')
agg=collections.Counter()
for r in long:
    c=collections.Counter(n[:60] for _,names in r for n in set(names) if firn.search(n) and 'Swift' not in n[:6])
    agg+=c; print(f"{r[0][0]/1000:6.2f}s {len(r):3d}ms ", '; '.join(f"{k} {v}" for k,v in c.most_common(3)))
print('--- functions under them (ms)')
for k,v in agg.most_common(25): print(v,k)
