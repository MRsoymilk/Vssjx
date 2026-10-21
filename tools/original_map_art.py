"""Original Online tile vocabulary, applied to EVERY playable native scene.

Partial screenshots guide material/architecture only. Shared navigation and saved
positions never change. No imported artwork, color filters, or fake recovered IDs.
"""
import math
from ai_world_layouts import Layout, HOUSES
import screenshot_map_profiles as screenshots

PATH = {0:18, 1:21, 2:32, 4:41, 8:30, 9:20, 3:22, 12:40, 6:42}
SNOW = {0:474, 1:464, 2:475, 4:484, 8:473, 9:463, 3:465, 12:483, 6:485}
WATER = {0:91, 1:81, 2:92, 4:101, 8:90, 9:80, 3:82, 12:100, 6:102}


def field(x, y, seed):
    """Low-frequency patches, never independent per-cell confetti."""
    return (math.sin(x*.27 + y*.11 + seed*.73) + math.cos(y*.31 - x*.13 + seed*.37))/2


def surface_grid(m):
    if 'original_map_id' in m:
        prefix = m['map_id'] + '_'
        people = [r['id'].removeprefix(prefix) for r in m['residents'] if r['kind']=='npc']
        extra = [r['id'].removeprefix(prefix) for r in m['residents']
                 if r['kind']!='npc' and r['id'].removeprefix(prefix) not in ('mob','boss')]
        layout = Layout(m, m['biome'], extra, people)
        original = layout.compose()
        # Fail rather than subtly bake a different authoritative map revision.
        assert original['tiles'] == m['tiles'], ('Unreviewed layout drift', m['map_id'])
        return [line.copy() for line in layout.g]
    # Two older maps have no semantic generator; classify only verified families.
    road = {18,19,20,21,22,30,31,32,40,41,42}
    water = set(WATER.values())
    return [[('water' if t in water else 'path' if t in road else 'grass' if t<18
              else 'rock' if t in (258,222) else 'void' if t==219 else 'source')
             for t in m['tiles'][y*32:(y+1)*32]] for y in range(32)]


def rebuild(m):
    g = surface_grid(m)
    ground = m['tiles'].copy()
    seed = m.get('original_map_id', 301 if m['map_id']=='qingyun_trail' else 302)
    biome = m.get('biome', 'forest' if m['map_id']=='qingyun_trail' else 'ruins')
    buildings = []
    # Roofs/walls sort at the foundation, not permanently underneath characters.
    for landmark in m.get('landmarks', []):
        if landmark['kind'] not in HOUSES:
            continue
        x, y = landmark['cell']; w, h = landmark['size']
        tiles = []
        for dy in range(h):
            for dx in range(w):
                i = (y+dy)*32+x+dx
                tiles.append(m['tiles'][i])
                ground[i] = 394 if m.get('layout_archetype','').startswith('earth_') else 149
        buildings.append(dict(cell=[x,y],size=[w,h],tiles=tiles,kind=landmark['kind']))

    def at(x,y):
        return g[y][x] if 0<=x<32 and 0<=y<32 else 'void'

    def mask(x,y,valid):
        return sum(bit for bit,dx,dy in ((1,0,-1),(2,1,0),(4,0,1),(8,-1,0))
                   if at(x+dx,y+dy) not in valid)

    # Protect all points of interest (including the separately injected guardian).
    protected = [m['spawn'],*[r['cell'] for r in m.get('residents',[])]]
    protected += [p for gate in m.get('exits',[]) for p in gate.get('cells',[gate['cell']])]
    if 'original_map_id' not in m:protected += [[3,16],[28,16],[12,16],[10,13]]
    if m['map_id']=='ai_001': protected.append([12,15])
    for y in range(32):
        for x in range(32):
            s = g[y][x]; i=y*32+x; patch=field(x,y,seed)
            near = any(abs(x-p[0])+abs(y-p[1])<3 for p in protected)
            if s=='grass':
                # A coherent meadow replaces independently randomized flower tiles.
                # 88 is the native unmarked turf. 13/14 are tuft decals, not
                # base fill: repeating those every cell made the old grass a grid.
                detail=((x*73856093)^(y*19349663)^(seed*83492791))%17
                ground[i] = (14 if patch>.3 else 13) if patch>-.1 and detail<3 else 88
                if not near and patch>.62 and (x*7+y*11+seed)%13==0:
                    ground[i] = [2,3,7,8,10,11,12][(x+y+seed)%7] if biome=='bloom' else 16
                # Keep original visible cliff borders; do not paint them as grass.
                if m['tiles'][i] in (52,78,62,70,64,77,79,69,68,72): ground[i]=m['tiles'][i]
            elif s=='path':
                edge=mask(x,y,{'path','wood','paving'})
                ground[i]=PATH.get(edge,18)
                if edge==0 and patch>.4:ground[i]=31
                if edge==0 and not near and (x*13+y*7+seed)%71==0:ground[i]=19
            elif s=='water':
                ground[i]=WATER.get(mask(x,y,{'water','wood'}),91)
            elif s=='rock' and biome=='snow':
                ground[i]=SNOW.get(mask(x,y,{'rock','snow','wood','stone'}),474)
                detail=((x*73856093)^(y*19349663)^(seed*83492791))%17
                if ground[i]==474 and patch>-.1 and detail<3:ground[i]=457 if patch>.4 else 456
            elif s=='void' and biome=='snow':
                ground[i]=514
                if at(x,y-1)=='rock':ground[i]=494
                elif at(x,y-2)=='rock' and at(x,y-1)=='void':ground[i]=531
            elif s=='ice' and biome=='snow':
                ground[i]=479
            elif s=='lava':
                if all(at(x+dx,y+dy)=='lava' for dx,dy in ((0,1),(1,0),(-1,0),(0,-1))):
                    ground[i]=718 if patch>.15 else 715
            elif s in ('rock','stone') and biome in ('cave','ruins'):
                # Keep audited cliff boundaries; texture changes only in the floor.
                if m['tiles'][i] in (258,222):
                    detail=((x*73856093)^(y*19349663)^(seed*83492791))%17
                    ground[i]=222 if patch>-.3 and detail<2 else 258
            elif s=='dirt' and not near:
                # Keep yellow-earth courts broad and uncluttered, as in screenshots.
                ground[i]=394
                if patch>.58 and (x*3+y*7+seed)%47==0:ground[i]=440
            elif s=='sand' and not near:
                ground[i]=325
                if patch>.6 and (x*3+y*7+seed)%41==0:ground[i]=333
            if m['tiles'][i]==72:ground[i]=72  # Authored grass stairs override path masks too.

    props=[dict(p) for p in m['scenery']]
    kinds={'forest':['m2','m10'],'bloom':['m10','m11'],'town':['m2'],
           'temple':['m10'],'coast':['m12'],'marsh':['m13'],'snow':['m8','m7']}
    # A designed perimeter reads as a boundary instead of walkable empty grass.
    # Never add a trunk on a walkable cell, doorway or any resident/exit canopy.
    if biome in kinds:
        candidates=[(x,y) for x in (0,31) for y in range(5,32,4)]
        candidates += [(x,31) for x in range(4,29,4)]
        for x,y in candidates:
            if not m['blocked'][y*32+x] or (x+y+seed)%3==0:continue
            if g[y][x] in ('water','lava','ice','void'):continue
            if any(abs(x-p[0])<=4 and -1<=y-p[1]<=7 for p in protected):continue
            if any(abs(x-p['x']//16)+abs(y-p['y']//16)<4 for p in props):continue
            palette=screenshots.prop_kinds(seed) or kinds[biome]
            if seed in (22,23):palette=['m10']
            elif seed==21:palette=['m12']
            art=palette[(x+y+seed)%len(palette)]
            props.append(dict(art='map/'+art,x=x*16+8,y=y*16+8))
    # Composite used by native minimap/preview, matching the world from above.
    composite=ground.copy()
    for b in buildings:
        x,y=b['cell'];w,h=b['size']
        for dy in range(h):
            for dx in range(w):composite[(y+dy)*32+x+dx]=b['tiles'][dy*w+dx]
    return dict(ground=ground,buildings=buildings,scenery=props,composite=composite)
