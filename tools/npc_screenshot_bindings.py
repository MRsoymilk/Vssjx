"""Apply screenshot appearances without replacing names, positions or quest IDs."""

BY_NAME = {
    '齐霞儿': 'qi-xiaer', '五毒天王': 'wudu-tianwang', '周轻云': 'zhou-qingyun',
    '天池上人': 'tianchi-shangren', '隐名剑仙': 'yi-jing', '诸有功': 'brown-mask-full',
    '博浪沙火鹤': 'crane-daren', '杂货店老板': 'grocery-boss',
}
# Deliberate art assignments, never a claim that the two NPC identities are equal.
# Expected names protect resident IDs if a future roster changes.
OVERRIDES = {
    'ai_013_courier': ('铁匠', 'baishouxian', '商店角色适配：灰肤短衣造型借用于铁匠'),
    'ai_013_npc03': ('镇长', 'tan-chang', '仓库管理服务相符，截图姓名目读仍待核对'),
    'ai_028_npc03': ('滕松岚', 'yi-zhou', '传功修士外观适配'),
    'ai_028_npc04': ('傅长风', 'zhu-liang', '静修道人外观适配'),
    'ai_028_npc06': ('柳青霜', 'xiaoyue-chanshi', '丹房药师外观适配'),
    'ai_032_guide': ('一元祖师', 'school-daily', '昆仑同屏天池上人、隐名剑仙及门派日常服务推定；非读出姓名'),
    'ai_041_guide': ('石齐', 'jingji-envoy', '竞技活动服务外观适配'),
    'ai_041_npc03': ('曹少衡', 'fashion-vendor', '云游匠人外观适配；下半身为AI补全'),
    'ai_041_npc06': ('郎星河', 'budai-xianren', '茶摊客人采用坐姿布袋仙人外观'),
    'ai_007_courier': ('方怀川', 'zhen-gen', '送信旅人外观适配'),
    'ai_007_survey': ('周青霜', 'jiang-xier', '药材伙计采用花冠人物外观'),
    'ai_007_npc04': ('许思远', 'zhi-xian', '行脚郎中采用芝仙外观'),
}
THEMES = {
    'town': ['grocery-boss', 'fashion-vendor', 'budai-xianren', 'tan-chang', 'jiang-xier', 'qi-xiaer'],
    'temple': ['school-daily', 'jingji-envoy', 'zhu-liang', 'yi-zhou', 'xiaoyue-chanshi'],
    'forest': ['zhen-gen', 'tianchi-shangren', 'zhi-xian', 'qi-xiaer', 'zhou-qingyun'],
    'bloom': ['jiang-xier', 'zhi-xian', 'qi-xiaer', 'wudu-tianwang', 'zhou-qingyun'],
    'snow': ['yi-jing', 'tianchi-shangren', 'school-daily', 'zhen-gen', 'qi-xiaer'],
    'lava': ['yi-zhou', 'brown-mask-full', 'baishouxian', 'xiaoyue-chanshi'],
    'cave': ['brown-mask-full', 'yi-zhou', 'xiaoyue-chanshi', 'tianchi-shangren'],
    'ruins': ['tan-chang', 'zhu-liang', 'jingji-envoy', 'school-daily'],
    'coast': ['wudu-tianwang', 'zhi-xian', 'zhen-gen', 'zhou-qingyun'],
    'marsh': ['wudu-tianwang', 'zhi-xian', 'xiaoyue-chanshi', 'yi-jing'],
}

# Reviewed from the map-sized sprites. A biome may narrow a role's pool, but
# cannot turn a courier into a seated monk or a named child into an elder.
# Only explicit service wording supplies age/gender constraints; generated
# personal names are not evidence of either.
ROLE_APPEARANCES = {
    'guide': ['zhen-gen', 'tianchi-shangren', 'zhou-qingyun'],
    'courier': ['zhen-gen', 'qi-xiaer', 'zhou-qingyun'],
    'guard': ['tianchi-shangren', 'yi-zhou', 'zhou-qingyun', 'brown-mask-full'],
    'commander': ['yi-zhou', 'tianchi-shangren', 'school-daily'],
    'scholar': ['zhu-liang', 'tianchi-shangren', 'yi-jing', 'xiaoyue-chanshi'],
    'mentor': ['school-daily', 'zhu-liang', 'tianchi-shangren'],
    'herbalist': ['zhi-xian', 'zhen-gen', 'qi-xiaer'],
    'healer': ['xiaoyue-chanshi', 'zhu-liang', 'zhen-gen'],
    'artisan': ['baishouxian', 'grocery-boss'],
    'gatherer': ['baishouxian', 'grocery-boss', 'zhen-gen'],
    'steward': ['grocery-boss', 'tan-chang'],
    'traveler': ['zhen-gen', 'qi-xiaer', 'zhou-qingyun', 'fashion-vendor'],
    'resting_guest': ['budai-xianren'],
    'child': ['zhi-xian', 'jiang-xier'],
    'elder': ['tan-chang', 'school-daily', 'zhu-liang'],
    'female_herbalist': ['zhen-gen', 'qi-xiaer', 'zhou-qingyun'],
}
ROLE_SERVICES = {
    'guide': ['花谷引路人', '雪岭引路人', '探洞领队', '遗迹引路人', '水路引路人', '幻界接引', '知客弟子'],
    'courier': ['山间信使', '送药花使', '雪驿信使', '火脉信使', '洞口信使', '送信旅人', '山门信使', '拓碑信使', '渡口信使', '送药信使', '军情传令', '探境信使'],
    'guard': ['巡山修士', '护林散修', '护花弟子', '护路符师', '镇火修士', '地脉巡守', '守灯修士', '镇口巡守', '远行剑客', '护符弟子', '守门弟子', '守灯人', '护路修士', '阵眼校尉', '巡营弟子', '营门哨兵', '轮值剑修', '驻境剑修'],
    'commander': ['驻营统领'],
    'scholar': ['清露观测', '游学修士', '静修道人', '藏经弟子', '考碑修士', '水脉观测', '避瘴苗师'],
    'mentor': ['传功修士'],
    'herbalist': ['采药弟子', '药材伙计', '采药修士'],
    'healer': ['寻草药师', '草木药师', '行脚郎中', '丹房药师', '伤药郎中'],
    'artisan': ['炼火匠', '云游匠人'],
    'gatherer': ['采冰修士', '采晶弟子', '寻石弟子', '采珠修士', '渡口船夫'],
    'steward': ['驿路管事', '军需管事'],
    'traveler': ['歇脚旅人', '避雪旅人', '归舟旅人', '旅人'],
    'resting_guest': ['茶摊客人'],
    'child': ['净水道童'],
    'elder': ['辨草老人'],
    'female_herbalist': ['采药苗女'],
}
SERVICE_PROFILE = {service: role for role, services in ROLE_SERVICES.items() for service in services}


def role_choices(service, biome):
    # New generated professions require a deliberate appearance review.
    profile = SERVICE_PROFILE[service]
    choices = ROLE_APPEARANCES[profile]
    themed = [asset for asset in choices if asset in THEMES.get(biome, [])]
    return profile, themed or choices


def apply_appearance(number, index, biome, person):
    key = f"ai_{number:03}_{person['role']}"
    profile = None
    if person['name'] in BY_NAME:
        asset = BY_NAME[person['name']]
        basis, reason = 'name_match', '现有NPC与截图名称直接对应，沿用既有地图及职责'
    elif key in OVERRIDES:
        expected, asset, reason = OVERRIDES[key]
        if person['name'] != expected:
            raise ValueError('NPC appearance assignment needs review: ' + key)
        basis = 'context_or_service_adaptation'
    elif person.get('source') == 'AI生成' and number != 1:
        profile, choices = role_choices(person['service_label'], biome)
        asset = choices[(number + index) % len(choices)]
        basis = 'authored_appearance'
        reason = f"按「{person['service_label']}」职责匹配外观，地貌仅在同类候选中取舍；身份不与截图人物等同"
    else:
        return
    person['art'] = 'npc/ssjx_' + asset.replace('-', '_')
    person['appearance_status'] = '截图外观 + AI辅助抠图/修复；静态帧，非原版精灵精确恢复'
    person['appearance_reference'] = dict(asset_id=asset, basis=basis, reason=reason,
        catalog='client/assets/data/recovered-npcs-ssjx-pic.json')
    if profile:
        person['appearance_reference']['role_profile'] = profile
