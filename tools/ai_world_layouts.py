"""Scene composition from observed video grammar, not random obstacle recoloring.

Original atlas: grass shelves/shorelines, raised blue rock, volcanic cliff faces,
red-roof homes and purple-roof shrines. Geometry and placements are AI authored.
"""
import heapq
import math
import random
from collections import deque
import screenshot_map_profiles as screenshots

SIZE=32
SOLID={"water","void","lava","ice","hill","sand_hill","building","tree","terrace_rim"}
FLOOR={"grass":13,"path":18,"water":91,"void":219,"lava":685,"ice":479,
       "hill":52,"rock":258,"volcanic":687,"snow":456,"paving":149,
       "stone":258,"wood":138,"dark":544,"sand":325,"dirt":394,"sand_hill":355,"sand_steps":373}
HOUSES={
    "flower_hall":[[149,149,145,146,149,149,149],[150,141,142,142,142,143,154],[155,151,152,152,152,153,156],[165,170,171,172,173,174,166],[160,180,181,182,183,184,164]],
    "house":[[141,142,143],[151,152,153],[161,162,163]],
    "inn":[[141,142,142,142,143],[170,171,172,173,174],[180,181,182,183,184]],
    "shrine":[[190,191,192,193],[200,201,202,203],[210,211,212,213]],
    "blue_house":[[590,591,592,593,594],[600,601,603,603,604],[610,611,612,613,614],[394,621,622,623,394]],
}
NAMES=dict(zip(
    ["market_town","canal_town","hamlet","monastery","mountain_shrine","ceremonial_court","arena","warcamp","cold_plateau","glacier_pass","frozen_lake","volcanic_island","lava_chasm","canyon_trail","ridge_trail","cave_chambers","demon_labyrinth","crypt","sealed_ruins","lake_ring","river_crossing","marsh_boardwalk","flower_garden","bamboo_avenue","river_valley","woodland_glade","terraced_hills"],
    ["集市街镇","临水街镇","山间村落","山门庭院","山顶祠院","礼仪庭院","演武擂场","驻守营地","寒地石台","冰谷栈桥","环冰湖岸","火山台地","熔岩裂谷","峡谷山道","盘山岭道","连环洞室","魔界迷廊","墓室甬道","封印遗院","环湖洲渚","曲河石桥","沼泽木栈","曲径花园","竹林夹道","河谷山路","林间幽谷","草坡台阶"]))

def archetype(name,kind,num):
    if num in screenshots.PROFILES:return screenshots.PROFILES[num][0]
    if num==21:return "flower_sect_court"
    if num in (22,23):return "bamboo_waterside"
    if any(k in name for k in ["擂台","群英会"]):return "arena"
    if any(k in name for k in ["营地","备战","基地","战场","进攻区","防守区","资源","精华源"]):return "warcamp"
    if "礼堂" in name:return "ceremonial_court"
    if kind=="town":return "canal_town" if any(k in name for k in ["卧云","水","渡"]) else ["market_town","hamlet"][num%2]
    if kind=="temple":return "monastery" if any(k in name for k in ["寺","派"]) else "mountain_shrine"
    if kind=="snow":return "frozen_lake" if any(k in name for k in ["池","湖"]) else ["glacier_pass","cold_plateau"][num%2]
    if kind=="lava":return "lava_chasm" if any(k in name for k in ["峡","狱"]) else "volcanic_island"
    if kind=="cave":return "demon_labyrinth" if "魔界" in name else "cave_chambers"
    if kind=="ruins":return "crypt" if any(k in name for k in ["墓","坟","冢","宫"]) else "sealed_ruins"
    if kind=="coast":return "lake_ring" if any(k in name for k in ["湖","潭","池"]) else "river_crossing"
    if kind=="marsh":return "marsh_boardwalk"
    if kind=="bloom":return "bamboo_avenue" if any(k in name for k in ["竹","兰"]) else "flower_garden"
    if any(k in name for k in ["峡","崖"]):return "canyon_trail"
    if any(k in name for k in ["岭","山顶","神山"]):return "ridge_trail"
    return ["river_valley","woodland_glade","terraced_hills"][num%3]

class Layout:
    def __init__(self,row,kind,extra_roles=(),npc_roles=()):
        self.num=row["original_map_id"];self.kind=kind;self.rng=random.Random(730921+self.num*917)
        self.type=archetype(row["name"],kind,self.num)
        base="grass"
        if kind in ("cave","ruins","snow"):base="void"
        if kind=="lava":base="lava"
        self.g=[[base for _ in range(32)] for _ in range(32)]
        self.override={};self.landmarks=[];self.scenery=[]
        self.spawn=[5,16];self.portal=[4,16]
        self.sites={};self.buildings=set()
        self.extra_roles=extra_roles
        self.npc_roles=npc_roles

    def paint(self,x,y,material):
        if 0<x<31 and 0<y<31 and (x,y) not in self.buildings:self.g[y][x]=material

    def rect(self,x,y,w,h,material):
        for yy in range(y,y+h):
            for xx in range(x,x+w):self.paint(xx,yy,material)

    def ellipse(self,cx,cy,rx,ry,material):
        for y in range(max(1,int(cy-ry)-1),min(31,int(cy+ry)+2)):
            for x in range(max(1,int(cx-rx)-1),min(31,int(cx+rx)+2)):
                a=math.atan2((y-cy)/ry,(x-cx)/rx)
                phase=self.num*.47+cx*.21+cy*.13
                edge=1+.085*math.sin(a*3+phase)+.045*math.cos(a*5-phase)
                if ((x-cx)/rx)**2+((y-cy)/ry)**2<=edge*edge:self.paint(x,y,material)

    def path(self,points,material="path",radius=1):
        if material=="path" and len(points)>2:
            curve=[]
            for i in range(len(points)-1):
                a,b,c,d=points[max(0,i-1)],points[i],points[i+1],points[min(len(points)-1,i+2)]
                for j in range(12):
                    t=j/12
                    curve.append([.5*(2*b[k]+(-a[k]+c[k])*t+(2*a[k]-5*b[k]+4*c[k]-d[k])*t*t+(-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t) for k in (0,1)])
            points=[*curve,points[-1]]
        for a,b in zip(points,points[1:]):
            steps=max(abs(b[0]-a[0]),abs(b[1]-a[1]))
            for t in range(math.ceil(steps)+1):
                f=min(1,t/max(1,steps));x=round(a[0]+(b[0]-a[0])*f);y=round(a[1]+(b[1]-a[1])*f)
                for dy in range(-radius,radius+1):
                    for dx in range(-radius,radius+1):self.paint(x+dx,y+dy,material)

    def building(self,x,y,kind="house"):
        prefab=HOUSES[kind];w=len(prefab[0]);h=len(prefab)
        for yy,line in enumerate(prefab):
            for xx,tile in enumerate(line):
                p=(x+xx,y+yy)
                if not (1<=p[0]<31 and 1<=p[1]<31):continue
                self.g[p[1]][p[0]]="building";self.buildings.add(p);self.override[p]=tile
        self.landmarks.append({"kind":kind,"cell":[x,y],"size":[w,h]})

    def landmark(self,kind,cell,size):self.landmarks.append({"kind":kind,"cell":list(cell),"size":list(size)})

    def compose(self):
        r=self.rng;n=self.num;t=self.type
        shift=r.randint(-2,2)
        if n in screenshots.PROFILES:
            screenshots.compose(self)
        elif n in (213,214):
            self.showcase_scene()
        elif t in ("flower_sect_court","bamboo_waterside"):
            self.reference_scene()
        elif t in ("market_town","canal_town","hamlet"):
            self.portal=[2,18+shift];self.spawn=[3,18+shift]
            street=16+shift
            self.path([[2,self.spawn[1]],[11,self.spawn[1]],[street,16],[street,28]],"paving",1)
            self.path([[street,4],[street,16],[28,16]],"paving",1)
            self.rect(12,12,10,9,"paving")
            homes=([(5,5),(11,4),(22,5),(5,24),(23,24)] if t!="hamlet" else [(7,5),(21,8),(9,24)])
            for i,(x,y) in enumerate(homes):
                x+=r.randint(-1,1);y+=r.randint(-1,1)
                self.rect(x-1,y+2,7,4,"paving");self.building(x,y,"inn" if i%2==0 else "house")
                self.path([[x+2,y+3],[street,y+3]],"path",0)
            if t=="canal_town":
                for y in range(1,31):self.rect(8+round(math.sin(y/6+n)),y,3,1,"water")
                self.path([[6,self.spawn[1]],[13,self.spawn[1]]],"wood",1)
                self.landmark("canal",[8,1],[4,30])
            else:
                self.ellipse(24,24,3,3,"water");self.landmark("village_pond",[21,21],[7,7])
            self.sites=dict(guide=[16,14],courier=[7,10],survey=[24,11],mob=[24,19],boss=[19,27])
        elif t in ("monastery","mountain_shrine","ceremonial_court"):
            self.portal=[16+shift,28];self.spawn=[16+shift,27]
            self.rect(6,5,21,21,"paving")
            self.rect(8,8,17,15,"stone")
            self.path([[self.spawn[0],29],[self.spawn[0],12]],"paving",1)
            self.building(14+shift,5,"shrine")
            self.building(6,13,"shrine");self.building(23,13,"shrine")
            self.ellipse(9,23,2,2,"water");self.ellipse(24,23,2,2,"water")
            if t=="mountain_shrine":
                self.rect(1,1,4,30,"hill");self.rect(28,1,3,30,"hill")
                self.building(14,18,"shrine")
            self.landmark("main_court",[8,8],[17,15])
            self.sites=dict(guide=[16+shift,10],courier=[10,18],survey=[22,18],mob=[6,26],boss=[25,6])
        elif t in ("arena","warcamp"):
            self.portal=[3,25-shift];self.spawn=[4,25-shift]
            left=6+r.randint(0,3);top=5+r.randint(0,3);extent=16+r.randint(0,4)
            self.rect(left,top,extent,extent,"paving" if t=="arena" else "path")
            if t=="arena":
                if n%2:self.ellipse(16+shift,16,8,7,"stone");self.ellipse(16+shift,16,5,4,"paving")
                else:self.rect(left+2,top+2,extent-4,extent-4,"stone");self.rect(left+5,top+5,extent-10,extent-10,"paving")
                for x,y in [(5,4),(24,4),(5,26),(24,26)]:self.building(x+r.randint(-1,1),y+r.randint(-1,1),"shrine")
            else:
                for x,y in [(6,6),(23,6),(6,22),(23,22)]:self.building(x+r.randint(-2,2),y+r.randint(-2,2),"inn" if r.random()<.5 else "house")
                self.path([[4,self.spawn[1]],[16,16],[27,16]],"path",1)
                self.path([[16,5],[16,27]],"path",1)
                self.ellipse(16,16,5,5,"path")
                self.ellipse(26 if n%2 else 5,15,2,4,"water")
            self.landmark("training_ground",[9,9],[15,15])
            self.sites=dict(guide=[8,24],courier=[10,9],survey=[24,24],mob=[15,18],boss=[21,12])
        elif t in ("cold_plateau","glacier_pass","frozen_lake","volcanic_island","lava_chasm","canyon_trail","ridge_trail"):
            floor="volcanic" if self.kind=="lava" else ("rock" if self.kind=="snow" else "grass")
            if self.kind not in ("snow","lava"):
                self.g=[["void" for _ in range(32)] for _ in range(32)]
            self.ellipse(15+shift,15,13+r.random()*2,11+r.random()*2,floor)
            self.ellipse(10+r.randint(-2,2),23,6+r.random()*2,5+r.random()*2,floor);self.ellipse(23,8+r.randint(-2,2),5+r.random()*2,4+r.random()*2,floor)
            self.portal=[4,19];self.spawn=[5,19]
            self.rect(2,17,6,5,floor)
            if t in ("glacier_pass","canyon_trail","lava_chasm"):
                cut="lava" if self.kind=="lava" else "void"
                for y in range(2,30):
                    x=15+round(math.sin(y/4+n)*3);self.rect(x,y,3,1,cut)
                self.path([[9,16+shift],[23,16+shift]],"wood" if self.kind!="lava" else "stone",0)
                self.landmark("bridged_chasm",[13,3],[6,27])
            else:
                pool="lava" if self.kind=="lava" else "ice"
                self.ellipse(20,18,4+r.randint(0,1),3,pool)
                self.landmark("lava_crater" if self.kind=="lava" else "ice_basin",[16,14],[9,8])
            if t=="ridge_trail":self.path([[4,19],[9,22],[14,19],[20,9],[26,7]],"path",0)
            if t=="frozen_lake":
                self.ellipse(16,16,9,7,"ice");self.path([[6,18],[13,24],[25,19]],"rock",1)
            self.sites=dict(guide=[9,20],courier=[10,8],survey=[25,12],mob=[19,8],boss=[23,24])
        elif t in ("cave_chambers","demon_labyrinth","crypt","sealed_ruins"):
            self.g=[["void" for _ in range(32)] for _ in range(32)]
            centers=[(7,18),(11+r.randint(-2,2),7),(24,9+r.randint(-2,2)),(23+r.randint(-2,2),24)]
            for i,(x,y) in enumerate(centers):
                if t in ("crypt","demon_labyrinth"):self.rect(x-4,y-4,8+r.randint(0,2),8+r.randint(0,2),"rock")
                else:self.ellipse(x,y,r.randint(5,7),r.randint(4,6),"rock")
            self.path([[7,18],[9,15],[11,7],[21,7],[24,9],[24,24]],"rock",1)
            self.path([[7,18],[8,24],[23,24]],"rock",0)
            if n%3==0:self.path([[11,7],[12,24]],"rock",0)
            self.portal=[3,18];self.spawn=[4,18]
            if t=="sealed_ruins":
                self.rect(17,20,11,8,"paving");self.building(20,20,"shrine")
            if t=="crypt":
                if len(self.extra_roles)>=2:
                    # Several table-recorded species need a battle chamber wide
                    # enough to circle patrols; don't pack them into the doorway.
                    self.rect(17,17,13,13,"rock")
                    self.landmark("deep_combat_chamber",[17,17],[13,13])
                for x,y in [(9,6),(22,7),(21,22)]:self.building(x,y,"shrine")
            self.landmark("chamber_network",[3,3],[26,26])
            self.sites=dict(guide=[7,20],courier=[9,9],survey=[26,11],mob=[16,7],boss=[24,26])
        elif t in ("lake_ring","river_crossing","marsh_boardwalk"):
            if t=="lake_ring":
                self.ellipse(17,15,10+r.randint(-1,1),8,"water")
                self.ellipse(17,15,3,3,"grass")
                self.path([[4,20],[8,25],[25,25],[28,17],[25,5],[12,4]],"path",0)
                self.path([[17,15],[17,25]],"wood",0)
                self.landmark("central_lake",[6,5],[23,20])
                self.sites=dict(guide=[7,22],courier=[25,7],survey=[17,14],mob=[26,20],boss=[11,5])
            else:
                for y in range(1,31):
                    x=13+round(math.sin(y/6+n)*4);self.rect(x,y,4 if t=="river_crossing" else 8,1,"water")
                self.path([[2,18],[9,18],[13,14],[24,14],[29,8]],"path",0)
                self.path([[8,15],[25,15]],"wood",0)
                if t=="marsh_boardwalk":
                    for x,y in [(5,6),(23,24),(7,27)]:self.ellipse(x,y,4,3,"water")
                    self.path([[10,15],[10,25],[27,25]],"wood",0)
                self.landmark("river_bridge",[10,14],[14,3])
                self.sites=dict(guide=[6,18],courier=[25,9],survey=[25,25],mob=[7,6],boss=[28,27])
            self.portal=[3,19];self.spawn=[4,19]
        elif t in ("flower_garden","bamboo_avenue"):
            self.portal=[4,26];self.spawn=[5,26]
            self.path([[4,26],[10,24],[12,15],[20,11],[26,4]],"path",0)
            self.ellipse(21,23,6,4,"water")
            self.building(6,6,"shrine")
            if t=="flower_garden":
                self.path([[9,12],[9,19],[17,19],[17,12],[9,12]],"path",0)
                self.ellipse(13,15,2,2,"water")
            else:
                self.path([[5,16],[25,16]],"path",0)
                self.landmark("bamboo_walk",[6,14],[21,5])
            self.landmark("garden_pool",[15,19],[13,9])
            self.sites=dict(guide=[10,10],courier=[25,6],survey=[13,22],mob=[23,16],boss=[27,28])
        else:
            self.portal=[3,16+shift];self.spawn=[4,16+shift]
            self.path([[2,self.spawn[1]],[8,19],[14,17],[19,11],[28,9]],"path",0)
            if t=="river_valley":
                for y in range(1,31):self.rect(16+round(math.sin(y/5+n)*4),y,3,1,"water")
                self.path([[10,18],[24,18]],"wood",0)
                self.landmark("meandering_river",[13,1],[8,30])
            elif t=="terraced_hills":
                for cx,cy,rx,ry in [(8,6,7,3),(24,20,7,4),(10,28,9,2)]:self.ellipse(cx+shift,cy,rx,ry,"hill")
                self.landmark("grass_terraces",[2,3],[28,27])
            else:
                self.ellipse(23,7,5,4,"water");self.ellipse(11,24,4,3,"hill")
                self.landmark("woodland_pond",[18,3],[11,9])
            self.sites=dict(guide=[9,15],courier=[26,7],survey=[7,26],mob=[21,22],boss=[27,27])
        # Preserve the first map's already tested tutorial-compatible NPC sites.
        # The other 213 maps place residents in their own authored districts.
        if self.num==1:
            self.spawn=[5,16];self.portal=[4,16]
            self.sites=dict(guide=[10,13],courier=[23,9],survey=[22,24],mob=[20,13],boss=[25,23])
        elif n!=213 and t in ("arena","warcamp","cave_chambers","demon_labyrinth","crypt"):
            side=n%4
            self.portal=[[3,16+shift],[16+shift,3],[28,16+shift],[16+shift,28]][side]
            self.spawn=[[4,16+shift],[16+shift,4],[27,16+shift],[16+shift,27]][side]
        for i,role in enumerate(self.extra_roles):
            self.sites[role]=([[13,24],[22,18],[16,13]] if n in (21,22,23) else [[13,22],[23,16],[15,10]])[i%3]
        self.social_sites()
        self.paint(*self.spawn,"rock" if self.kind in ("snow","cave","ruins") else ("volcanic" if self.kind=="lava" else "path"))
        self.paint(*self.portal,self.g[self.spawn[1]][self.spawn[0]])
        self.place_sites()
        self.connect()
        self.props()
        if self.num==1:self.lingkong_south_terrace()
        return self.finish()

    def lingkong_south_terrace(self):
        # The southern mound used a cliff corner as its interior, creating a
        # scalloped carpet that looked passable but blocked the player's route.
        # Edit after prop generation to keep the rest of this tutorial intact.
        removed=[];retained=[]
        for prop in self.scenery:
            x,y=prop['x']//16,prop['y']//16
            (removed if 6<=x<=16 and 21<=y<=29 else retained).append(prop)
        self.scenery=retained
        cleared={(p['x']//16,p['y']//16) for p in removed}
        cleared.update((x,y) for y in range(20,28) for x in range(7,16) if self.g[y][x]=='hill')
        cleared.update((x,y) for y in range(22,30) for x in range(10,13))
        for x,y in cleared:
            self.g[y][x]='terrace';self.override[x,y]=88
        # A grass deck with a rim and a visible stone foundation gives the
        # stairs an actual upper landing. Vertical cliff faces cannot be crossed.
        for y in range(21,27):
            for x in range(8,15):
                self.g[y][x]='terrace';self.override[x,y]=88
                if y==21:
                    self.g[y][x]='terrace_rim';self.override[x,y]=238 if x==8 else 239 if x==14 else 248
                elif y<=24 and x in (8,14):
                    self.g[y][x]='terrace_rim';self.override[x,y]=257 if x==8 else 259
                elif y==24:
                    self.g[y][x]='terrace_rim';self.override[x,y]=268
                elif y==25:
                    self.g[y][x]='terrace_rim';self.override[x,y]=273 if x==8 else 274 if x==14 else 270
        steps=[[50,51,52],[60,61,62],[70,71,72]]
        for dy,row in enumerate(steps):
            for dx,tile in enumerate(row):
                x,y=10+dx,24+dy
                self.g[y][x]='terrace';self.override[x,y]=tile
        self.landmark('lingkong_raised_terrace',[8,21],[7,5])
        self.landmark('lingkong_south_steps',[10,24],[3,3])
        self.landmark('lingkong_south_landing',[10,27],[3,3])

    def showcase_scene(self):
        if self.num==213:
            self.portal=[15,28];self.spawn=[15,26]
            self.ellipse(27,17,5,9,"water")
            self.ellipse(23,23,4,4,"water")
            self.path([[15,28],[13,22],[14,16],[20,12],[23,9]],radius=1)
            self.path([[6,12],[10,14],[14,16],[20,22]],radius=0)
            self.rect(19,8,8,4,"paving")
            self.building(20,4,"flower_hall")
            self.building(5,7,"shrine")
            self.building(5,19,"inn")
            self.building(18,20,"house")
            self.sites=dict(guide=[23,11],courier=[13,17],survey=[8,12],mob=[5,27],boss=[28,6])
            self.landmark("command_hall",[19,4],[8,8])
            self.landmark("supply_lane",[5,17],[16,8])
            self.landmark("curved_riverbank",[24,10],[7,18])
        else:
            self.portal=[3,21];self.spawn=[4,21]
            self.ellipse(25,8,8,6,"water")
            self.ellipse(29,14,4,8,"water")
            self.path([[3,21],[9,20],[15,17],[18,13],[19,8]],radius=1)
            self.path([[10,20],[13,25],[22,26],[25,23]],radius=0)
            self.ellipse(8,7,5,3,"hill")
            self.ellipse(27,28,5,3,"hill")
            self.sites=dict(guide=[9,18],courier=[16,24],survey=[20,15],mob=[11,9],boss=[24,25])
            self.landmark("spring_glade",[18,2],[13,15])
            self.landmark("woodland_walk",[4,16],[19,12])

    def social_sites(self):
        # Services gather near doorways, route junctions, water and camp edges.
        # Extra NPCs are reserved BEFORE collision/scenery so none spawn in trees.
        doors=[[p['cell'][0]+p['size'][0]//2,p['cell'][1]+p['size'][1]+2] for p in self.landmarks if p['kind'] in HOUSES]
        hints=[[8,22],[22,22],[12,27],[19,13],[7,8],[25,9],[18,25]]
        if self.num==213:hints=[[8,24],[21,24],[16,23],[10,8]]
        if self.num==214:hints=[[12,27],[6,13],[18,21]]
        if self.num==213:doors=[]
        extra=[role for role in self.npc_roles if role not in self.sites]
        for i,role in enumerate(extra):
            self.sites[role]=list(doors[i] if i<len(doors) else hints[(i-len(doors))%len(hints)])

    def reference_scene(self):
        # Screenshots are partial evidence, not recovered tile/collision files.
        # Keep these overrides local: all unrelated generated maps stay identical.
        if self.num==21:
            self.g=[["water" for _ in range(32)] for _ in range(32)]
            self.ellipse(16,20,15,13,"grass")
            self.rect(5,1,23,12,"grass")
            self.rect(7,1,19,11,"paving")
            self.rect(14,11,5,5,"grass")
            for y in range(12,16):
                for x in range(14,19):self.override[x,y]=72
            self.building(13,2,"flower_hall")
            self.path([[16,16],[16,27]],radius=1)
            self.path([[3,27],[16,27],[29,27]],radius=1)
            self.ellipse(16,22,4,5,"path")
            self.portal=[16,29];self.spawn=[16,26]
            self.sites=dict(guide=[9,22],courier=[23,22],survey=[16,9],transport=[10,9],mob=[12,29],boss=[24,29])
            self.landmark("courtyard",[7,1],[19,11])
            self.landmark("grass_steps",[14,12],[5,4])
            self.landmark("palm_avenue",[5,17],[23,10])
        else:
            self.g=[["grass" for _ in range(32)] for _ in range(32)]
            self.rect(1,27,30,4,"water")
            self.rect(1,1,2,26,"water")
            if self.num==23:
                self.ellipse(26,23,7,7,"water")
                self.ellipse(25,10,5,4,"water")
            self.ellipse(16,20,12,5,"path")
            self.path([[4,21],[14,21],[25,18],[29,17]],radius=1)
            self.path([[16,21],[16,26]],radius=1)
            self.portal=[16,26];self.spawn=[16,23]
            self.sites=dict(guide=[9,20],courier=[24,18],survey=[16,13],mob=[10,10],boss=[25,6])
            self.landmark("bamboo_clearing",[4,9],[25,17])
            self.landmark("southern_waterfront",[1,27],[30,4])
            # Original atlas stump, visible in the bamboo reference.
            self.override[6,21]=120;self.override[7,21]=121
            self.g[21][6]=self.g[21][7]="tree"

    def reference_props(self):
        if self.num==21:
            points=[(7,18,"m12"),(25,18,"m12"),(4,25,"m12"),(27,25,"m12")]
        else:
            points=[(x,y,"m10") for x,y in [*[(x,6) for x in range(4,30,2)],*[(x,9) for x in range(4,30,2)],(4,12),(4,15),(4,18),(29,15)]]
        for x,y,art in points:
            if self.g[y][x] in SOLID:continue
            if any(abs(x-p[0])<=3 and 0<=y-p[1]<=6 for p in [self.spawn,self.portal,*self.sites.values()]):continue
            self.override[x,y]=FLOOR.get(self.g[y][x],13)
            self.g[y][x]="tree"
            self.scenery.append(dict(art="map/"+art,x=x*16+8,y=y*16+8))

    def place_sites(self):
        occupied={tuple(self.spawn),tuple(self.portal)}
        people=[]
        # Settle NPCs first; hostile seeds must not displace service residents.
        for role,want in list(self.sites.items()):
            if role not in self.npc_roles:continue
            if self.num==1:
                self.paint(*want,"grass");occupied.add(tuple(want));continue
            candidates=[]
            for y in range(3,29):
                for x in range(3,29):
                    if self.g[y][x] in SOLID or any(abs(x-p[0])+abs(y-p[1])<3 for p in occupied):continue
                    if role in self.npc_roles and any(abs(x-p[0])<5 and abs(y-p[1])<4 for p in people):continue
                    score=(x-want[0])**2+(y-want[1])**2+self.rng.random()*5
                    candidates.append((score,[x,y]))
            point=min(candidates)[1];self.sites[role]=point;occupied.add(tuple(point))
            if role in self.npc_roles:people.append(point)
        if self.num==1:return  # Preserve the already playable tutorial positions.
        arrivals=[self.spawn,self.portal]
        if self.num==21:arrivals += [[3,27],[29,27]]
        monsters=[role for role in self.sites if role not in self.npc_roles]
        monsters.sort(key=lambda role:role=="boss")
        for role in monsters:
            want=self.sites[role];candidates=[]
            for y in range(3,30):
                for x in range(3,30):
                    if self.g[y][x] in SOLID:continue
                    if any(abs(x-p[0])+abs(y-p[1])<7 for p in people):continue
                    if any(abs(x-p[0])+abs(y-p[1])<9 for p in arrivals):continue
                    if any(abs(x-p[0])+abs(y-p[1])<5 for p in occupied if list(p) not in people):continue
                    open_area=sum(self.g[yy][xx] not in SOLID for yy in range(max(1,y-2),min(31,y+3)) for xx in range(max(1,x-2),min(31,x+3)))
                    road=self.g[y][x] in ("path","paving","wood","sand_steps")
                    score=(x-want[0])**2+(y-want[1])**2+road*45+(25-open_area)*3
                    candidates.append((score,[x,y]))
            if not candidates:raise ValueError((self.num,role,"no safe combat clearing"))
            point=min(candidates)[1];self.sites[role]=point;occupied.add(tuple(point))

    def connect(self):
        # Minimal repairs only when terrain separates a quest district. No common
        # road is painted between all NPCs; lakes, courtyards and ridges stay intact.
        for target in [self.portal,*self.sites.values()]:
            start=tuple(self.spawn);goal=tuple(target)
            heap=[(0,start)];cost={start:0};prev={}
            while heap:
                c,p=heapq.heappop(heap)
                if p==goal:break
                if c!=cost[p]:continue
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                    q=(p[0]+dx,p[1]+dy)
                    if not(1<=q[0]<31 and 1<=q[1]<31) or q in self.buildings:continue
                    surface=self.g[q[1]][q[0]]
                    nc=c+(1 if surface not in SOLID else 22)
                    if nc<cost.get(q,10**9):cost[q]=nc;prev[q]=p;heapq.heappush(heap,(nc,q))
            if goal not in cost:raise ValueError((self.num,target,"unreachable district"))
            p=goal
            while p!=start:
                if self.g[p[1]][p[0]] in SOLID:
                    surface=self.g[p[1]][p[0]]
                    self.g[p[1]][p[0]]="wood" if surface in ("water","ice") else ("volcanic" if self.kind=="lava" else "rock")
                p=prev[p]

    def props(self):
        if self.num in (21,22,23):
            self.reference_props()
            return
        kinds={"forest":["m2","m2","m10"],"bloom":["m10","m11","m2"],"snow":["m8","m7"],"lava":["m9","m13"],
               "cave":["m9"],"town":["m2","m2","m10"],"temple":["m10","m14"],"ruins":["m13","m9"],"coast":["m12","m2"],"marsh":["m13","m10"]}
        points=[];sites=[self.spawn,self.portal,*self.sites.values()]
        def reachable():
            seen={tuple(self.spawn)};queue=deque(seen)
            while queue:
                x,y=queue.popleft()
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                    nx,ny=x+dx,y+dy
                    if 0<nx<31 and 0<ny<31 and self.g[ny][nx] not in SOLID and (nx,ny) not in seen:seen.add((nx,ny));queue.append((nx,ny))
            return seen
        free=reachable()
        limit=28 if self.type in ("woodland_glade","bamboo_avenue","flower_garden") else (8 if self.type=="terraced_hills" else 15)
        limit=screenshots.prop_limit(self.num) or limit
        clusters=[(self.rng.randint(3,28),self.rng.randint(5,29)) for _ in range(5)]
        for attempt in range(700):
            if len(points)>=limit:break
            if attempt%4:
                cx,cy=self.rng.choice(clusters)
                x,y=round(self.rng.gauss(cx,2.4)),round(self.rng.gauss(cy,2.0))
            else:x,y=self.rng.randint(2,29),self.rng.randint(4,29)
            if not (2<=x<=29 and 4<=y<=29):continue
            if (x,y) not in free:continue
            if self.g[y][x] not in ("grass","snow","rock","volcanic","dark","sand","dirt"):continue
            if any(abs(x-p[0])+abs(y-p[1])<4 for p in sites):continue
            # A solid trunk can be several cells below a resident while its
            # tall canopy still covers the character and arrival marker.
            if any(abs(x-p[0])<=3 and 0<=y-p[1]<=6 for p in sites):continue
            if any(abs(x-bx)<=2 and 0<=y-by<=4 for bx,by in self.buildings):continue
            if any(abs(x-p[0])+abs(y-p[1])<2 for p in points):continue
            if any(self.g[yy][xx] in ("path","paving","wood") for yy in range(max(1,y-1),min(31,y+2)) for xx in range(max(1,x-1),min(31,x+2))):continue
            previous=self.g[y][x];self.g[y][x]="tree"
            remaining=reachable()
            if len(remaining)!=len(free)-1:self.g[y][x]=previous;continue
            free=remaining
            art=self.rng.choice(screenshots.prop_kinds(self.num) or kinds[self.kind]);points.append((x,y))
            self.scenery.append({"art":"map/"+art,"x":x*16+8,"y":y*16+8})
            self.override[x,y]=FLOOR.get(previous,13)
        # Original canopies overhang naturally; only the foot cell collides.

    def finish(self):
        g=self.g;tiles=[];blocked=[]
        def at(x,y):return g[y][x] if 0<=x<32 and 0<=y<32 else "void"
        def mask(x,y,equal):return sum(bit for bit,dx,dy in [(1,0,-1),(2,1,0),(4,0,1),(8,-1,0)] if not equal(at(x+dx,y+dy)))
        roads={0:18,1:21,2:32,4:41,8:30,9:20,3:22,12:40,6:42}
        cliffs={0:258,1:248,2:259,4:268,8:257,9:238,3:239,12:267,6:269}
        lava_edges={0:544,1:692,2:688,4:697,8:686,9:694,3:695,12:704,6:705}
        # Original atlas 80/81/82, 90/91/92, 100/101/102 is the water set.
        # 123 is a diagonal grass-bank corner, never a repeating water center.
        shores={0:91,1:81,2:92,4:101,8:90,9:80,3:82,12:100,6:102}
        hills={0:52,1:78,2:62,4:70,8:64,9:77,3:79,12:69,6:68}
        sand_hills={0:355,1:345,2:356,4:365,8:354,9:344,3:346,12:364,6:366}
        for y in range(32):
            for x in range(32):
                s=g[y][x];tile=FLOOR.get(s,13)
                if s=="path":tile=roads.get(mask(x,y,lambda v:v in ("path","wood","paving")),18)
                elif s=="water":tile=shores.get(mask(x,y,lambda v:v in ("water","wood")),91)
                elif s=="hill":tile=hills.get(mask(x,y,lambda v:v=="hill"),52)
                elif s=="sand_hill":tile=sand_hills.get(mask(x,y,lambda v:v=="sand_hill"),355)
                elif s in ("sand","dirt") and self.rng.random()<.055:
                    tile=self.rng.choice([333,334,329] if s=="sand" else [440,441,442,443,444,445])
                elif s in ("rock","stone") and self.kind in ("cave","ruins","snow"):
                    tile=cliffs.get(mask(x,y,lambda v:v not in ("void","lava")),258)
                elif s=="volcanic":tile=lava_edges.get(mask(x,y,lambda v:v not in ("void","lava")),687)
                elif s=="grass":
                    p=self.rng.random()
                    patch=(math.sin(x*.39+y*.19+self.num)+math.cos(y*.52-x*.13+self.num*.7)+2)/4
                    density=(.21 if self.kind=="bloom" else .065)*max(0,(patch-.3)/.7)
                    tile=self.rng.choice([2,3,7,8,10,11,12]) if p<density else self.rng.choice([13,14])
                    if tile in (13,14) and p>.986:tile=15
                    edge=mask(x,y,lambda v:v!="void") if 0<x<31 and 0<y<31 else 0
                    if edge:tile=hills.get(edge,52)
                elif s=="rock" and self.rng.random()<.055:tile=222
                if (x,y) in self.override:tile=self.override[x,y]
                tiles.append(tile);blocked.append(s in SOLID or x in (0,31) or y in (0,31))
        # Front-facing cliff depth follows the ledge silhouette seen in video.
        for y in range(1,31):
            for x in range(1,31):
                if g[y][x] in ("void","lava") and g[y-1][x] in ("rock","volcanic"):
                    tiles[y*32+x]=721 if g[y][x]=="lava" else 270
                    if y<30 and g[y+1][x]==g[y][x]:tiles[(y+1)*32+x]=731 if g[y][x]=="lava" else 288
        seen={tuple(self.spawn)};queue=deque(seen)
        while queue:
            x,y=queue.popleft()
            for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                nx,ny=x+dx,y+dy
                if 0<=nx<32 and 0<=ny<32 and not blocked[ny*32+nx] and (nx,ny) not in seen:seen.add((nx,ny));queue.append((nx,ny))
        for y in range(32):
            for x in range(32):
                if (x,y) not in seen:blocked[y*32+x]=True
        return dict(tiles=tiles,blocked=blocked,scenery=self.scenery,spawn=self.spawn,portal_cell=self.portal,
                    sites=self.sites,layout_archetype=self.type,landmarks=self.landmarks,
                    layout_name=NAMES[self.type],
                    terrain_reference=(screenshots.reference(self.num) or {}).get("evidence") or ("用户截图局部参考：花涧派庭院/台阶/棕榈夹道；竹林清场/南侧水岸。未显示区域为AI补全，非原版全图恢复。" if self.num in (21,22,23) else "用户视频：01:40/03:40草地台阶、07:30石台崖壁、08:00/17:00熔岩岸线、27:40建筑庭院"))

def build_layout(row,kind,extra_roles=(),npc_roles=()):return Layout(row,kind,extra_roles,npc_roles).compose()

NAMES.update(flower_sect_court="花涧派·临水庭院",bamboo_waterside="竹林清场与水岸")
NAMES.update(screenshots.NAMES)
