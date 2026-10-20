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


def apply_appearance(number, index, biome, person):
    key = f"ai_{number:03}_{person['role']}"
    if person['name'] in BY_NAME:
        asset = BY_NAME[person['name']]
        basis, reason = 'name_match', '现有NPC与截图名称直接对应，沿用既有地图及职责'
    elif key in OVERRIDES:
        expected, asset, reason = OVERRIDES[key]
        if person['name'] != expected:
            raise ValueError('NPC appearance assignment needs review: ' + key)
        basis = 'context_or_service_adaptation'
    elif person.get('source') == 'AI生成' and number != 1:
        choices = THEMES[biome]
        asset = choices[(number + index) % len(choices)]
        basis, reason = 'authored_appearance', '现有AI人物按地域用途借用截图修复外观，身份不与截图人物等同'
    else:
        return
    person['art'] = 'npc/ssjx_' + asset.replace('-', '_')
    person['appearance_status'] = '截图外观 + AI辅助抠图/修复；静态帧，非原版精灵精确恢复'
    person['appearance_reference'] = dict(asset_id=asset, basis=basis, reason=reason,
        catalog='client/assets/data/recovered-npcs-ssjx-pic.json')
