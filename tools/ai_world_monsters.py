"""Player-sheet placements plus explicitly authored visual/stat assignments.

Never turns the player's sheet or a visual resemblance into recovered server IDs.
"""
import json,re
from functools import lru_cache
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# Reviewed native idle composites. Names are inferred presentation assignments,
# not an original monster-ID-to-animation table.
NAMES={
 '野猪王':'xt4','瘟疫野猪':'xt1','血魔之眼':'fq3','魔人':'ls1',
 '吸血花妖':'srh2','石头巨人':'sr2','石头巨人头领(精英)':'ysg4',
 '妖道xx':'smr','有个马面怪物':'mm1','瘟疫僵尸':'zb3','魔教丧尸':'zb2','丧尸王':'zbjl1',
 '叛徒':'dz1','铸剑弟子':'dsn','魔教死士':'dz8','还有个拿枪的魔教XX':'zb5',
 '变异僵尸':'zb4','长枪鬼士':'zb5','雪葬僵尸':'zb6','空气之魂':'yuanling1',
 '鲜血之魂':'yuanling3','血眼蛮士':'ls1','鬼府马面':'mm2','无面者':'wmrn4',
 '熊':'x1','厉鬼':'youling4','未知级食人花':'srh','未知级刽子手':'nt2',
 '云滴泪':'njs3','鬼府枪兵':'zb5','苦行僧':'hs2','绿棕熊':'x4',
 '蛮荒野人':'sr','雨林巨人':'ysg1','雨林巨人首领(精英)':'ysg2',
 'XX级深渊软泥':'wx3','恐怖行尸':'zb3','千年毒妖':'xrz1','三目童子':'tw1',
 '霸天大将(精英)':'nt3','恐怖食人花':'srh','森林幽狼':'efw1','血染熊王boss':'x3',
 '焱精':'hg1','岩浆巨人boss':'ysg3','森林之王boss':'slzw',
 '慈云寺淫僧':'hs1','黑魁罗汉':'hs3','狂傲武僧':'hs2','酒肉方丈悟信':'hs4',
 '震棺僵尸':'zb1','殉葬怨灵':'youling1','地宫骷髅':'klb3','冥府将军boss':'nt1',
 '兵俑大帝':'bmy','勾魂姹女':'njs2','拜蛇教魔女':'njs1','千年蛇妖boss':'slzw',
 '血魔魂媒':'njs4','赤火神倪':'xn4','冥府三头犬boss':'dyq3',
 '麻头鬼王':'ls2','炽焰冷魂':'yuanling4','血魔化身boss':'hg2',
 '吞噬怪(魔)':'fq1','血眼战士(魔)':'ls1','血之怨灵(魔)':'youling2',
 '剧毒吞噬怪(魔)':'fq4','沥血元魂(魔)':'yuanling3',
}
REGIONS={
 'forest':[('山狼','langw'),('棕熊','x1'),('山地野猪','xt2'),('食人花','srh'),('山林巨人','sr2')],
 'bloom':[('采露花妖','srh3'),('谷地花灵','tm2'),('花谷异兽','fq2')],
 'snow':[('雪原幽狼','efw3'),('雪岭白熊','x5'),('寒冰之魂','yuanling1'),('寒谷怨灵','youling3')],
 'lava':[('焱精','hg1'),('熔岩巨人','ysg3'),('炎域恶狼','efw2'),('火脉元魂','yuanling3')],
 'cave':[('洞穴吞噬怪','fq1'),('地穴软泥','wx3'),('地宫骷髅','klb3'),('洞窟行尸','zb2')],
 'town':[('叛逃弟子','dz1'),('拦路魔徒','dz5'),('山地野猪','xt2'),('劫道枪卫','zb5')],
 'temple':[('叛门剑徒','dsn1'),('失心武僧','hs2'),('阵隙魔女','njs1'),('守阵灵将','nt1')],
 'ruins':[('殉葬怨灵','youling1'),('地宫骷髅','klb3'),('震棺僵尸','zb1'),('古墓软泥','wx2')],
 'coast':[('泽地软泥','wx1'),('水脉元魂','yuanling4'),('寒潭怨灵','youling3'),('渡口魔卫','zb4')],
 'marsh':[('瘴泽软泥','wx3'),('沼泽食人花','srh2'),('毒泽异兽','fq4'),('染瘴行尸','zb3')],
}
BOSSES={
 'forest':[('森林之王','slzw'),('山林熊王','x3'),('三首妖犬','dyq2')],
 'bloom':[('噬香花妖','srh2'),('花谷毒妖','xrz2')],
 'snow':[('寒岭熊王','x5'),('封雪妖将','mm3')],
 'lava':[('熔岩巨人首领','ysg3'),('焚脉妖王','hg2')],
 'cave':[('冥府三头犬','dyq3'),('洞府马面','mm2'),('吞噬妖王','fq3')],
 'town':[('劫道妖首','nt2'),('叛军统领','zbjl2')],
 'temple':[('入魔方丈','hs4'),('破阵魔将','nt3')],
 'ruins':[('兵俑大帝','bmy'),('冥府将军','nt1'),('镇墓妖王','mm3')],
 'coast':[('锁水蛇妖','slzw'),('水府马面','mm1')],
 'marsh':[('毒泽巨人','ysg1'),('千年瘴妖','xrz1')],
}
ART_KEYS={v for v in NAMES.values()}|{art for pool in [*REGIONS.values(),*BOSSES.values()] for _,art in pool}

@lru_cache(maxsize=1)
def sheet_records():
 return json.loads((ROOT/'analysis/references/player-sheet/monsters.json').read_text(encoding='utf8'))

def clean_name(row):
 raw=row['name_after_level'] or row['label_raw']
 return {'妖道xx':'妖道（待核名）','有个马面怪物':'马面怪（暂名）','还有个拿枪的魔教XX':'魔教枪卫（暂名）'}.get(raw,
  re.sub(r'(?i)boss|未知级|XX级|\(精英\)','',raw))[:12]

def roster(row,biome):
 num=row['original_map_id'];level=row['level_min'];entries=[]
 for r in sheet_records():
  if r['map_csv_index']+1!=num:continue
  raw=r['name_after_level'] or r['label_raw']
  art=NAMES[raw] # An unmapped reference is an error, never silently a wolf.
  entries.append(dict(name=clean_name(r),art='monster/'+art,level=r['reported_level'] or level,
   reference=dict(source='用户表格（待核对）',source_row=r['source_row'],source_columns=r['source_columns'],
    label_raw=r['label_raw'],reported_level=r['reported_level'],appearance='AI按原包外形推定，非原始ID映射',stats='AI临时战斗数值'),
   elite=bool(re.search(r'(?i)boss|精英|首领|方丈|大帝|丧尸王|野猪王',raw))))
 # Keep stable quest target IDs. Every sheet entry appears exactly once; use
 # authored regional counterparts only for a missing ordinary/boss role.
 boss=next((v for v in reversed(entries) if v['elite']),None)
 if boss is None and len(entries)>1:boss=entries[-1]
 normal=next((v for v in entries if v is not boss),None)
 def fallback(pool,role):
  name,art=pool[(num-1)%len(pool)]
  return dict(name=name,art='monster/'+art,level=min(60,level+(2 if role=='boss' else 0)),
   reference=dict(source='AI补足',appearance='AI按地貌选择原包外形',stats='AI临时战斗数值'))
 normal=normal or fallback(REGIONS[biome],'mob');boss=boss or fallback(BOSSES[biome],'boss')
 values=[dict(normal,role='mob'),dict(boss,role='boss')]
 values.extend(dict(v,role=f'mob{i+2}') for i,v in enumerate(v for v in entries if v is not normal and v is not boss))
 return values

def stats(art,level,elite):
 # Distinct combat profiles; all formulas are authored, no sheet HP is implied.
 name=art.split('/')[-1]
 tank=name.startswith(('x','ysg','sr','nt')) and not name.startswith(('xrz','xn','xt'))
 spirit=name.startswith(('yuanling','youling','hm','hg','fq','njs','ls'))
 hp=45+level*20;attack=8+level*3;defense=1+level
 return dict(hp=round(hp*(1.25 if tank else .85 if spirit else 1)),
  attack=round(attack*(1.13 if spirit else .95 if tank else 1)),
  defense=round(defense*(1.25 if tank else .8 if spirit else 1)),
  gold=(4+level*2)*(2 if elite else 1),xp=(6+level*3)*(2 if elite else 1))
