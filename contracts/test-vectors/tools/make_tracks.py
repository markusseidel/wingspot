#!/usr/bin/env python3
"""Writes contracts/test-vectors/tracks.json with an independent reference implementation (standard library only).
Run from the repository root: python3 contracts/test-vectors/tools/make_tracks.py"""
import json, math
R=6371.0088
def hav(a,b):
    la1,la2=math.radians(a[1]),math.radians(b[1]); dl=math.radians(b[0]-a[0]); dp=la2-la1
    h=math.sin(dp/2)**2+math.cos(la1)*math.cos(la2)*math.sin(dl/2)**2
    return 2*R*math.asin(min(1,math.sqrt(h)))
def length(p): return sum(hav(p[i],p[i+1]) for i in range(len(p)-1))
def unwrap(p):
    out=[list(p[0])]
    for lon,lat in p[1:]:
        prev=out[-1][0]; lon=lon+round((prev-lon)/360)*360; out.append([lon,lat])
    return out
def proj(pt):
    lat=max(-85.05,min(85.05,pt[1])); r=6371008.8
    return (r*math.radians(pt[0]), r*math.log(math.tan(math.pi/4+math.radians(lat)/2)))
def seg_dist(p,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]; l2=dx*dx+dy*dy
    if l2==0: return math.hypot(p[0]-a[0],p[1]-a[1])
    t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/l2)); return math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
def simplify(p,eps):
    u=unwrap(p)
    if len(u)<3: return u
    pr=[proj(x) for x in u]; keep=[False]*len(u); keep[0]=keep[-1]=True; stack=[(0,len(u)-1)]
    while stack:
        a,b=stack.pop(); best=-1; bi=-1
        for i in range(a+1,b):
            d=seg_dist(pr[i],pr[a],pr[b])*math.cos(math.radians(max(-85.05,min(85.05,u[i][1]))))
            if d>best: best=d; bi=i
        if bi>=0 and best>eps: keep[bi]=True; stack.append((a,bi)); stack.append((bi,b))
    return [u[i] for i in range(len(u)) if keep[i]]
cases=[]
def add(name,pts,eps=100):
    s=simplify(pts,eps); u=unwrap(pts)
    cases.append({"name":name,"points":[[round(a,6),round(b,6)] for a,b in pts],"lengthKm":round(length(pts),3),
      "crossesAntimeridian":any(abs(pts[i+1][0]-pts[i][0])>180 for i in range(len(pts)-1)),
      "unwrappedLongitudes":[round(x[0],6) for x in u],"toleranceMeters":eps,
      "simplifiedCount":len(s),"simplifiedLongitudes":[round(x[0],6) for x in s],"simplifiedLatitudes":[round(x[1],6) for x in s]})
add("along the equator",[[float(i),0.0] for i in range(5)])
add("along a meridian",[[10.0,float(i)] for i in range(5)])
add("Tokyo to Los Angeles, made up, across the date line",[[139.78,35.55],[150,38],[165,42],[179,45],[-175,46],[-160,44],[-140,40],[-120,36],[-118.41,33.94]])
add("Los Angeles to Tokyo, made up, across the date line",[[-118.41,33.94],[-120,36],[-140,40],[-160,44],[-175,46],[179,45],[165,42],[150,38],[139.78,35.55]])
add("detour around a closed airspace, made up",[[8.5,50.0],[20,58],[45,62],[75,58],[100,48],[116.6,40.1]])
add("noise below the tolerance",[[round(-10+i*0.2,4),round(45+0.0002*math.sin(i*1.7),6)] for i in range(100)])
add("zig-zag above the tolerance",[[float(i)*0.1,0.01 if i%2 else 0.0] for i in range(6)])
add("two points",[[0.0,0.0],[1.0,1.0]])
add("one point",[[5.0,5.0]])
json.dump({"description":"Made-up flight tracks, no real flight data. lengthKm is the sum of haversine distances (mean Earth radius 6371.0088 km). unwrappedLongitudes are continuous (no jump over 180 degrees). The simplified result keeps the first and last point and uses Ramer-Douglas-Peucker on Web Mercator metres with the tolerance scaled by cos(latitude), so toleranceMeters is metres on the ground. Compare lengths with toleranceKm and coordinates with toleranceDegrees. Written by an independent reference implementation, see tools/make_tracks.py.","toleranceKm":0.05,"toleranceDegrees":0.00001,"cases":cases},open("contracts/test-vectors/tracks.json","w"),indent=2)
for c in cases: print(c["name"],c["lengthKm"],c["crossesAntimeridian"],c["simplifiedCount"],c["simplifiedLongitudes"][:6])
