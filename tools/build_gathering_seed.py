"""Deterministic gathering points on the existing reachable navigation grid.

New gameplay placements, not recovered original resource positions.
"""
import json
from collections import deque
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def catalog():
    maps=[json.loads((ROOT/'shared/data'/name).read_text()) for name in ('qingyun-v1.json','ancient-ruins-v1.json')]
    maps+=json.loads((ROOT/'shared/data/ai-world-v1.json').read_text())['maps']
    materials=[dict(id='iron',name='铁矿',kind='ore'),dict(id='copper',name='铜矿',kind='ore'),dict(id='gancao',name='甘草',kind='herb'),dict(id='danggui',name='当归',kind='herb')]
    nodes=[]
    for m in maps:
        w,h=m['width'],m['height'];start=tuple(m['spawn'])
        exits={tuple(e['cell']) for e in m.get('exits',[])}
        if not exits: exits={(3,16),(28,16)}
        residents=m.get('residents',[])
        if m['map_id'] in ('qingyun_trail','ancient_ruins'):
            file='qingyun-population-v1.json' if m['map_id']=='qingyun_trail' else 'ruins-population-v1.json'
            residents=json.loads((ROOT/'shared/data'/file).read_text())
        seen={start};queue=deque([start])
        while queue:
            x,y=queue.popleft()
            for dx,dy in ((0,-1),(1,0),(0,1),(-1,0)):
                p=(x+dx,y+dy)
                if 0<=p[0]<w and 0<=p[1]<h and not m['blocked'][p[1]*w+p[0]] and p not in seen and p not in exits:
                    seen.add(p);queue.append(p)
        used=[]
        staged=[]
        for kind,delta in [('ore',(5,3)),('herb',(-4,4))]:
            ideal=(start[0]+delta[0],start[1]+delta[1])
            def distance(a,b):return abs(a[0]-b[0])+abs(a[1]-b[1])
            choices=[p for p in seen if distance(p,start)>=4 and all(distance(p,e)>=3 for e in exits) and all(distance(p,tuple(r['cell']))>=3 for r in residents) and all(distance(p,u)>=5 for u in used)]
            if not choices:
                choices=[p for p in seen if distance(p,start)>=2 and all(distance(p,e)>=2 for e in exits) and all(distance(p,tuple(r['cell']))>=1 for r in residents) and all(distance(p,u)>=3 for u in used)]
            if not choices:
                print('SKIP: no safe reachable gathering pair without crossing a portal:',m['map_id'])
                staged=[];break
            point=min(choices,key=lambda p:(distance(p,ideal),p[1],p[0]));used.append(point)
            high=int(m.get('level_min',1))>=25 or m['map_id']=='ancient_ruins'
            material=('copper' if high else 'iron') if kind=='ore' else ('danggui' if high else 'gancao')
            staged.append(dict(id=m['map_id']+'_'+kind,map_id=m['map_id'],cell=list(point),material=material,duration_ms=3000,respawn_ms=60000,min_quantity=1,max_quantity=3))
        nodes+=staged
    return dict(version='gathering-v1',stack_limit=999,materials=materials,nodes=nodes)

def migration(data):
    schema='''-- Personal resource nodes. Geometry stays in the existing map assets.
CREATE TABLE gathering_nodes (
    id TEXT PRIMARY KEY CHECK(length(id)<=32), map_id TEXT NOT NULL,
    cell_x INTEGER NOT NULL CHECK(cell_x BETWEEN 0 AND 31),
    cell_y INTEGER NOT NULL CHECK(cell_y BETWEEN 0 AND 31),
    material TEXT NOT NULL CHECK(material IN ('iron','copper','gancao','danggui')),
    duration_ms BIGINT NOT NULL CHECK(duration_ms BETWEEN 1000 AND 60000),
    respawn_ms BIGINT NOT NULL CHECK(respawn_ms BETWEEN 1000 AND 86400000),
    min_quantity INTEGER NOT NULL CHECK(min_quantity BETWEEN 1 AND 10),
    max_quantity INTEGER NOT NULL CHECK(max_quantity BETWEEN min_quantity AND 10),
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX gathering_nodes_map ON gathering_nodes(map_id);
CREATE TABLE gathering_materials (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    material TEXT NOT NULL CHECK(material IN ('iron','copper','gancao','danggui')),
    quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 999),
    PRIMARY KEY(character_id,material)
);
CREATE TABLE gathering_cooldowns (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    node_id TEXT NOT NULL REFERENCES gathering_nodes(id),
    available_at_ms BIGINT NOT NULL CHECK(available_at_ms>=0),
    PRIMARY KEY(character_id,node_id)
);
CREATE TABLE gathering_active (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    token UUID NOT NULL UNIQUE, node_id TEXT NOT NULL REFERENCES gathering_nodes(id),
    snapshot JSONB NOT NULL CHECK(jsonb_typeof(snapshot)='object'),
    ready_at_ms BIGINT NOT NULL, expires_at_ms BIGINT NOT NULL,
    owner_epoch BIGINT NOT NULL, connection_epoch BIGINT NOT NULL,
    position_revision BIGINT NOT NULL, character_revision BIGINT NOT NULL,
    cell_x INTEGER NOT NULL, cell_y INTEGER NOT NULL,
    CHECK(expires_at_ms>ready_at_ms)
);
'''
    values=[]
    for n in data['nodes']:
        values.append("('%s','%s',%d,%d,'%s',%d,%d,%d,%d)"%(n['id'],n['map_id'],*n['cell'],n['material'],n['duration_ms'],n['respawn_ms'],n['min_quantity'],n['max_quantity']))
    return schema+'INSERT INTO gathering_nodes(id,map_id,cell_x,cell_y,material,duration_ms,respawn_ms,min_quantity,max_quantity) VALUES\n'+',\n'.join(values)+';\n'

if __name__=='__main__':
    data=catalog()
    (ROOT/'shared/data/gathering-v1.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'server/migrations/0035_gathering.sql').write_text(migration(data))
    print(f"GATHERING: {len(data['nodes'])} reachable points on {len(data['nodes'])//2} maps")
