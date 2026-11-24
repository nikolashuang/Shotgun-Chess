import sys
from PIL import Image
SCALE=float(sys.argv[1])
base=Image.open('mnt_tmp/Ruined_base.png').convert('RGB')
cur=Image.open('art/skins/boards/Ruined.png').convert('RGB')
W=160
diff=[[max(abs(a-b) for a,b in zip(base.getpixel((x,y)),cur.getpixel((x,y))))>24 for x in range(W)] for y in range(W)]
seen=set(); comps=[]
for y in range(W):
  for x in range(W):
    if diff[y][x] and (x,y) not in seen:
      st=[(x,y)]; seen.add((x,y)); c=[]
      while st:
        p=st.pop(); c.append(p)
        for dx in (-1,0,1):
          for dy in (-1,0,1):
            q=(p[0]+dx,p[1]+dy)
            if 0<=q[0]<W and 0<=q[1]<W and diff[q[1]][q[0]] and q not in seen: seen.add(q); st.append(q)
      comps.append(c)
out=cur.copy()
for c in comps:
  if len(c)<=3: continue
  members=set(c)
  for p in c: out.putpixel(p, base.getpixel(p))
  cx=sum(p[0] for p in c)/len(c)+0.5; cy=sum(p[1] for p in c)/len(c)+0.5
  xs=[p[0] for p in c]; ys=[p[1] for p in c]
  for y in range(min(ys),max(ys)+1):
    for x in range(min(xs),max(xs)+1):
      hits={}
      for i in range(3):
        for j in range(3):
          sx=int((x+(i+0.5)/3-cx)/SCALE+cx); sy=int((y+(j+0.5)/3-cy)/SCALE+cy)
          if (sx,sy) in members:
            col=cur.getpixel((sx,sy)); hits[col]=hits.get(col,0)+1
      if sum(hits.values())>=4: out.putpixel((x,y), max(hits,key=hits.get))
out.save('mnt_tmp/Ruined_small.png')
side=Image.new('RGB',(970,480),(255,255,255))
side.paste(cur.resize((480,480),Image.NEAREST),(0,0)); side.paste(out.resize((480,480),Image.NEAREST),(490,0))
side.save('mnt_tmp/Ruined_small_compare.png')
