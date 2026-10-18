"""Evidence-aware social population. Locations/dialogue/art assignments are AI authored."""
import re

HEROES=['mfs','wfs','mck','wck','mzs','wzs']
PEOPLE=['沈砚舟','温照雪','唐云笙','陆清和','孟长风','柳知秋','顾青岚','苏映月','陈守一','梁怀川','叶听澜','姜少衡','岳临川','洛青禾','凌青霜','宋闻笛','林望舒','谢归鸿','宁见山','秦暮云','楚怀玉','江问尘','白疏桐','方照水']
SURNAMES=list(dict.fromkeys('沈温唐陆孟柳顾苏陈梁叶姜岳洛凌宋林谢宁秦楚江白方徐赵钱孙李周吴郑王冯褚卫蒋韩杨朱尤许何吕施张孔曹严华金魏陶戚邹喻柏水窦章云葛奚范彭郎鲁韦昌马苗凤花俞任袁鲍史费廉岑薛雷贺倪汤滕殷罗毕郝安常傅齐康伍余元卜'))
GIVEN=[p[1:] for p in PEOPLE]+['思远','怀瑾','星河','景明','承霄','闻溪','映泉','松岚']

def authored_name(number,index):
    slot=((number*12+index)*197)%(len(SURNAMES)*len(GIVEN))
    return SURNAMES[slot//len(GIVEN)]+GIVEN[slot%len(GIVEN)]
PROFILES={
 'forest':['巡山修士','山间信使','采药弟子','护林散修','歇脚旅人','寻草药师'],
 'bloom':['花谷引路人','送药花使','清露观测','护花弟子','游学修士','草木药师'],
 'snow':['雪岭引路人','雪驿信使','护路符师','采冰修士','避雪旅人'],
 'lava':['镇火修士','火脉信使','炼火匠','地脉巡守','采晶弟子'],
 'cave':['探洞领队','洞口信使','寻石弟子','守灯修士'],
 'town':['驿路管事','送信旅人','药材伙计','云游匠人','行脚郎中','镇口巡守','茶摊客人','远行剑客','渡口船夫'],
 'temple':['知客弟子','山门信使','护符弟子','传功修士','静修道人','守门弟子','丹房药师','藏经弟子'],
 'ruins':['遗迹引路人','拓碑信使','考碑修士','守灯人'],
 'coast':['水路引路人','渡口信使','水脉观测','采珠修士','归舟旅人','净水道童'],
 'marsh':['避瘴苗师','送药信使','采药苗女','护路修士','辨草老人'],
 'camp':['驻营统领','军情传令','阵眼校尉','军需管事','伤药郎中','巡营弟子','营门哨兵','轮值剑修'],
}
GATHERING={'当归','茯苓','清心叶','精铁矿','珍金矿','珍铜矿'}
LINES={
 'camp':['前哨送来的军报都要核验。入营先辨旗号，出营务必留心归路。','我刚从前哨归来，驿路上的消息不能耽搁。','阵符的灵光比昨日暗了些，我正沿着营地复查阵眼。','干粮和兵械都要逐一清点，远行之前记得备齐所需。','赶路受了伤便在檐下歇歇，莫要带伤逞强。','林边有妖物出没，换岗之前我还得再巡一遍。','前面便是营门。山路夜里雾重，最好结伴而行。'],
 'forest':['林中的路看着相似，认准石标便不容易迷失。','路上见闻我已记下，正等下一班驿使带回山门。','晨露未散时药草最容易辨认，可别踩坏了幼苗。','我在此歇脚养息，也替过路的人留意林间动静。','风过树梢，倒能听见远处的水声。沿旧道走会稳妥些。'],
 'bloom':['花径绕水而行，莫把采露人的小径认作出谷的路。','山外等着这一批药材，我正整理行囊。','清露的气息变了，还要多查几处草木才能明白缘由。','花木间常有灵物栖息，经过时请放轻脚步。'],
 'town':['这里人来人往，驿道通畅，镇上才能安稳度日。','这一封家书得赶在天黑前送到，我在等同行的车马。','新收的药材怕潮，须在檐下摊开晾干。','炉火刚熄，远行的兵器还得仔细查验刃口。','赶了许久的路吧？先在树荫下歇一歇。','今日轮到我巡街，镇外有什么异状还请相告。'],
 'temple':['入山先静心，过阶莫喧哗。前殿的师兄正在等候来客。','各峰传来的消息已经送到，我还要再去下一处山门。','护山符引需日日查验，片刻也疏忽不得。','修行贵在积累，今日的功课还未做完。','炉中丹火正稳，待药香散尽再开炉不迟。'],
 'coast':['水边旧路常被潮气遮住，过桥时留心脚下。','渡口有信要送往山中，我正在等水雾散去。','水脉清浊有变，我还得沿岸多看几处。','静下心来听水声，有时比看路标更容易辨认方向。'],
}

def dialogue(row,group,service,index):
    if '商店' in service:return '远行须备好兵械和丹药。挑选物件之前，先看看自己平日惯用什么。'
    if '传送' in service:return '路口的青色回纹砖连着邻近地区。认准地名，再踏入传送处便好。'
    if '仓库' in service:return '往来行囊都得记清来处，贵重物件更要细心照看。'
    if '日常' in service:return '门中常要巡山护路，也有不少书信药材需要送达。你可向此地的任务发布人问问近况。'
    lines=LINES.get(group,['此地灵气时有异动，我留下照应往来的修士。','一路至此辛苦，辨清归路再往深处去。','旧日留下的痕迹尚在，我正在逐处查验。'])
    return lines[index%len(lines)]

def sheet_people(sheet):
    valid=[];excluded=[]
    raw=sheet.get('npc_raw') or ''
    for match in re.finditer(r'([^()（）\-]+)(?:[（(]([^()（）]+)[）)])?',raw):
        name=match[1].strip();service=(match[2] or '').strip()
        if not name:continue
        if any(v in name for v in ['未知','不详','暂无','玩家ID','什么','XX','有个','两个','NPC','？','?']) or re.match(r'^\d+级',name):
            excluded.append(dict(name=name,service=service,reason='原表占位名、未知人物或疑似怪物，不作为已知NPC补写'))
            continue
        valid.append(dict(name=name,service_label=service or ('采集点' if name in GATHERING else '驻地人物'),
            source='用户表格（待核对）',source_row=sheet.get('source_row'),source_columns='B:C',label_raw=match[0],gathering=name in GATHERING))
    return valid,excluded

def roster(row,kind,sheet):
    num=row['original_map_id'];people,excluded=sheet_people(sheet)
    camp=any(v in row['name'] for v in ['营地','基地','备战','进攻区','防守区','精华源','资源'])
    group='camp' if camp else kind
    roles=PROFILES[group]
    target=(7+num%3 if kind=='town' else 6+num%3 if kind=='temple' else 6+num%2 if camp else 3+num%2 if kind in ('cave','ruins') else 4+num%3)
    if num==1:target=3
    if num==21:
        # Preserve the four identities and quest IDs from the screenshot adaptation.
        people.sort(key=lambda p:['哈哈老祖','孔灵子','五毒天王','火修罗'].index(p['name']))
        target=4
    ordinary=[p for p in people if not p['gathering']]
    resources=[p for p in people if p['gathering']]
    result=ordinary[:3]
    while len(result)<3:result.append({})
    result.extend(ordinary[3:])
    excluded.extend(dict(p,reason='原表采集物，仅保留资源参考，不当作人形NPC') for p in resources)
    while len(result)<target:result.append({})
    for i,value in enumerate(result):
        role=['guide','courier','survey'][i] if i<3 else ('transport' if num==21 else f'npc{i:02}')
        service=value.get('service_label') or roles[i%len(roles)]
        name=value.get('name') or authored_name(num,i)
        if num==214 and not value:
            name=['澄玄子','宋闻笛','洛青禾','沈照夜','云归客'][i%5]
            service=['幻界接引','探境信使','水脉观测','采药修士','驻境剑修'][i%5]
        art='map/m9' if value.get('gathering') and '矿' in name else 'hero/'+HEROES[(num+i*5)%6]
        if num==21:art='hero/'+['mfs','wfs','wck','mzs'][i]
        value.update(role=role,name=name,service_label=service,art=art,
            source=value.get('source','AI生成'),appearance_status='原包图像临时匹配，非原NPC造型恢复',
            dialogue=dialogue(row,group,service,i),
            dialogue_source='AI生成',placement='按地形与职责安排，AI设计')
    return result,excluded
