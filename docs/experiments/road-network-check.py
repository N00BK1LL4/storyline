import json,struct,heapq,math,array
import os; D=os.environ["MAP3D_DATA"]  # op77_map3d/web/data/
m=json.load(open(D+"manifest.json"))["roads"]["arrays"]; b=open(D+"roads.bin","rb").read()
T={"<f4":"f","|u1":"B","<u4":"I","<u2":"H"}
A={k:struct.unpack_from("<%d%s"%(v["length"],T[v["type"]]),b,v["offset"]) for k,v in m.items()}
P=A["points"]; N=len(A["laneOffset"])
def pts(l):
    o,c=A["laneOffset"][l],A["laneCount"][l]; return [P[3*(o+i):3*(o+i)+3] for i in range(c)]
L=[pts(l) for l in range(N)]
def near(x,y,z=None,k=4,maxd=40):
    r=[]
    for l in range(N):
        best=min(((p[0]-x)**2+(p[1]-y)**2 + (0 if z is None else (p[2]-z)**2) for p in L[l]),default=9e9)
        # segment distance
        for a,c in zip(L[l],L[l][1:]):
            dx,dy=c[0]-a[0],c[1]-a[1]; n=dx*dx+dy*dy
            t=0 if n==0 else max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/n))
            q=(a[0]+t*dx,a[1]+t*dy,a[2]+t*(c[2]-a[2])); best=min(best,(q[0]-x)**2+(q[1]-y)**2+(0 if z is None else (q[2]-z)**2))
        if best<maxd*maxd: r.append((math.sqrt(best),l))
    return sorted(r)[:k]
out=lambda l:A["outLanes"][A["outStart"][l]:A["outStart"][l+1]]
def reach(s,goals):
    d={s:0};h=[(0,s)]
    while h:
        c,l=heapq.heappop(h)
        if l in goals: return c
        if c>d[l]: continue
        for n in out(l):
            w=c+A["laneLength"][n]
            if w<d.get(n,9e9): d[n]=w; heapq.heappush(h,(w,n))
for name,p in {"run1 start":(597.5,-1354.6,28.5),"run1 goal":(2157.3,-668,60.8),"run2 goal":(1668.1,-711.4,50.5),"run3 goal":(1669.7,-708.9,50.5),"rec stop":(-500,-193,8.6),"rec next":(-341.3,-289.7,8),"run5 goal":(-511.4,-1500.7,7.6)}.items():
    print(name,[(round(d,1),l,"main" if A["laneMain"][l] else "side","flags",A["laneFlags"][l]) for d,l in near(*p)])
for a,c in (((597.5,-1354.6,28.5),(2157.3,-668,60.8)),((-500,-193,8.6),(-341.3,-289.7,8))):
    g={l for _,l in near(*c,k=2)}; print("route",[ (l,reach(l,g)) for _,l in near(*a,k=3)])
