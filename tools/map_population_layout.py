"""Place existing monsters in clearings without sealing services behind patrols."""
from collections import deque
import hashlib
import json

NPC_BUFFER = 7
ARRIVAL_BUFFER = 9
MONSTER_SPACING = 5
PATROL_RADIUS = 2


def distance(a, b):
    return abs(a[0]-b[0]) + abs(a[1]-b[1])


def service_routes(m, forbidden):
    start = tuple(m['spawn']); seen = {start}; queue = deque(seen)
    while queue:
        x, y = queue.popleft()
        for p in ((x+1,y), (x-1,y), (x,y+1), (x,y-1)):
            xx, yy = p
            if 0 < xx < 31 and 0 < yy < 31 and p not in seen and p not in forbidden and not m['blocked'][yy*32+xx]:
                seen.add(p); queue.append(p)
    return seen


def arrange(m):
    if m['original_map_id'] == 1:
        return  # Existing tutorial interaction coordinates are part of its flow.
    people = [r['cell'] for r in m['residents'] if r['kind']=='npc']
    arrivals = [m['spawn'], m['portal']['cell'],
                *[p for gate in m['exits'] for p in gate.get('cells', [gate['cell']])]]
    required = {tuple(p) for p in people + arrivals}
    monsters = sorted((r for r in m['residents'] if r['kind']!='npc'), key=lambda r:r['kind']=='boss')
    choices = []
    for monster in monsters:
        want = monster['cell']; candidates = []
        for y in range(3,30):
            for x in range(3,30):
                p = [x,y]
                if m['blocked'][y*32+x]: continue
                if any(distance(p,v)<NPC_BUFFER for v in people): continue
                if any(distance(p,v)<ARRIVAL_BUFFER for v in arrivals): continue
                if any(abs(x-prop['x']//16)<=3 and 0<=prop['y']//16-y<=6 for prop in m['scenery']): continue
                patrol = {(xx,yy) for yy in range(y-PATROL_RADIUS,y+PATROL_RADIUS+1)
                          for xx in range(x-PATROL_RADIUS,x+PATROL_RADIUS+1)}
                open_area = sum(not m['blocked'][yy*32+xx] for xx,yy in patrol if 0<xx<31 and 0<yy<31)
                road = m['tiles'][y*32+x] in (18,20,21,22,30,32,40,41,42,72,138,149,373)
                score = distance(p,want)**2 + road*45 + (25-open_area)*3
                candidates.append((score,p,patrol))
        choices.append(sorted(candidates, key=lambda v:(v[0],v[1])))
    # Four distinct enemy types can share a small crypt. Backtrack when an early
    # otherwise valid clearing would leave no safe room for the last type.
    def search(index, placed, forbidden):
        if index == len(monsters): return placed
        for _, p, patrol in choices[index]:
            if any(distance(p,v)<MONSTER_SPACING for v in placed): continue
            if required <= service_routes(m, forbidden | patrol):
                result = search(index+1, placed+[p], forbidden | patrol)
                if result is not None: return result
        return None
    placed = search(0, [], set())
    if placed is None:
        raise ValueError((m['map_id'],'no combat clearings with safe service routes'))
    for monster, point in zip(monsters, placed): monster['cell'] = point
    m['population_layout'] = dict(source='截图地貌参考 + 设计补全',npc_buffer_cells=NPC_BUFFER,
        arrival_buffer_cells=ARRIVAL_BUFFER,monster_spacing_cells=MONSTER_SPACING,patrol_radius_cells=PATROL_RADIUS,
        distance_metric='Manhattan',service_routes_avoid_patrols=True,
        notice='缓冲距离针对刷新点；巡游范围为原有切比雪夫半径2格。怪物身份、数量、等级和任务目标保持不变。')


def write_review(root, data):
    """Small reproducible audit: evidence, coordinates and unchanged-definition hash."""
    definitions = {r['id']:{k:v for k,v in r.items() if k!='cell'} for m in data['maps'] for r in m['residents']}
    refs = []
    for m in data['maps']:
        ref = m.get('ssjx_pic_reference',m.get('screenshot_reference',{}))
        if ref.get('directory') != 'analysis/references/ssjx-pic': continue
        refs.append(dict(map_id=m['map_id'],name=m['name'],**ref,
            file_hashes={name:hashlib.sha256((root/ref['directory']/name).read_bytes()).hexdigest() for name in ref['files']}))
    report = dict(layout_revision=data['layout_revision'],monster_revision=data['monster_revision'],
        map_count=len(data['maps']),rearranged_map_count=sum('population_layout' in m for m in data['maps']),
        monster_count=sum(r['kind']!='npc' for m in data['maps'] for r in m['residents']),
        resident_definition_sha256_excluding_cell=hashlib.sha256(json.dumps(definitions,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
        scope='仅局部截图地貌参考；怪物坐标为设计补全，无原始全图或精确刷新点数据。教程任务和坐标保留；灵空台南侧为独立局部地形优化。',
        screenshot_profiles=refs,
        placements=[dict(map_id=m['map_id'],name=m['name'],policy=m['population_layout'],
            monsters=[dict(id=r['id'],name=r['name'],level=r['level'],art=r['art'],cell=r['cell']) for r in m['residents'] if r['kind']!='npc'])
            for m in data['maps'] if 'population_layout' in m])
    (root/'analysis/recovery/ssjx-pic/map-optimization.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
