"""Partial screenshot observations adapted to 32x32 scenes, never native map data."""

PROFILES = {
    7: ("waterfront_village", ["87.jpg"], "齐霞儿同名NPC；草地、水岸与疏林可见"),
    12: ("wetland_glade", ["63.jpg", "96.jpg"], "同类湿地参考；花妖名称有差异，不能唯一确认地图"),
    13: ("earth_gate_town", ["39.jpg", "66.jpg", "70.jpg"], "同类青瓦镇街参考；未唯一确认地图"),
    28: ("earth_gate_temple", ["53.jpg", "54.jpg"], "博浪沙火鹤、诸有功与红发老祖同名NPC；黄土、门楼与崖阶可见"),
    29: ("earth_gate_temple", ["53.jpg", "54.jpg"], "参照相邻慈云寺北的门院地貌；相邻区域为推定"),
    30: ("earth_gate_temple", ["53.jpg", "54.jpg"], "参照相邻慈云寺北的黄土崖阶；相邻区域为推定"),
    32: ("earth_gate_sect", ["97.webp", "100.webp"], "天池上人、隐名剑仙与门派日常；黄土青瓦庭院可见"),
    41: ("market_waterfront", ["61.jpg", "79.jpg", "83.jpg"], "杂货店老板、车夫与集市铺地参考；不能仅凭通用服务NPC唯一确认地图"),
    43: ("sand_terraces", ["57.jpg", "58.jpg", "88.jpg"], "同类沙地、秋树和崖阶参考；未唯一确认地图"),
    45: ("sand_terraces", ["62.jpg", "72.jpg", "89.jpg"], "同类沙地与岩壁参考；未唯一确认地图"),
    46: ("sand_terraces", ["57.jpg", "77.jpg", "88.jpg"], "同类沙地与岩壁参考；未唯一确认地图"),
}

NAMES = {
    "waterfront_village": "天化村·临水草地",
    "wetland_glade": "湿地·花妖水岸",
    "earth_gate_town": "黄土青瓦街镇",
    "earth_gate_temple": "慈云寺·黄土门院",
    "earth_gate_sect": "昆仑派·青瓦门院",
    "market_waterfront": "集市·草岸街巷",
    "sand_terraces": "沙地·崖阶缓坡",
}


def reference(num):
    if num not in PROFILES:
        return None
    kind, files, evidence = PROFILES[num]
    return dict(directory="analysis/references/ssjx-pic", files=files,
                profile=kind, evidence=evidence,
                scope="截图局部地貌参考；全图尺寸、道路衔接、碰撞和怪物坐标均为设计补全，非原版恢复")


def compose(s):
    """Author local layouts with existing atlas tiles; keep identities/combat data."""
    kind = PROFILES[s.num][0]
    s.g = [["sand" if kind == "sand_terraces" else "dirt" if kind.startswith("earth_") else "grass"
            for _ in range(32)] for _ in range(32)]
    s.spawn = [4, 18]; s.portal = [3, 18]
    if kind in ("waterfront_village", "market_waterfront", "wetland_glade"):
        s.ellipse(30, 15, 5, 13, "water")
        s.ellipse(26, 2, 5, 4, "water")
        s.landmark("curved_waterfront", [25, 1], [6, 29])
        s.path([[3, 18], [11, 18], [17, 15], [23, 18], [23, 27]], radius=0)
        if kind == "waterfront_village":
            s.building(5, 5, "house"); s.building(14, 4, "inn")
            s.landmark("grass_service_glade", [5, 10], [18, 15])
        elif kind == "market_waterfront":
            s.rect(6, 9, 16, 15, "paving")
            s.rect(14, 18, 5, 5, "grass")
            for x, y in [(5, 5), (15, 5), (5, 24)]: s.building(x, y, "house")
            s.landmark("market_lanes", [6, 9], [16, 15])
        else:
            s.ellipse(4, 4, 4, 4, "water")
            s.ellipse(6, 29, 5, 3, "water")
            s.landmark("flower_bank", [19, 3], [6, 23])
    elif kind.startswith("earth_"):
        # The blue-roof buildings flank a broad earth lane, not a blue ice slab.
        s.rect(1, 1, 30, 3, "sand_hill")
        s.rect(13, 2, 6, 2, "dirt")
        s.rect(13, 3, 6, 1, "sand_steps")
        house = "blue_house" if kind in ("earth_gate_sect", "earth_gate_town") else "shrine"
        s.building(5, 6, house); s.building(20, 6, house)
        s.building(6, 22, "blue_house")
        s.path([[3, 18], [14, 18], [16, 13], [16, 4]], "dirt", 1)
        s.landmark("earth_service_court", [5, 10], [20, 12])
        s.landmark("northern_rock_steps", [13, 2], [6, 2])
        s.landmark("outer_patrol", [23, 24], [7, 6])
    else:
        # Native tan rock edges and autumn trees echo the desert screenshots.
        for x, y, w, h in [(1, 2, 11, 3), (19, 13, 12, 3), (2, 27, 12, 3)]:
            s.rect(x, y, w, h, "sand_hill")
        s.rect(23, 14, 4, 2, "sand_steps")
        s.path([[3, 18], [10, 18], [15, 13], [20, 10], [28, 8]], "sand", 1)
        s.landmark("sandstone_terraces", [1, 2], [29, 28])
    # Keep services in a readable settlement district, with outer clearings for
    # existing quest monsters. Extra residents get separate rows, not a doorway pile.
    hints = [[9, 12], [16, 12], [9, 18], [16, 18], [9, 25], [16, 25], [22, 12], [22, 19], [3, 10]]
    if kind == "wetland_glade": hints = [[8, 13], [15, 13], [8, 20], [15, 20]]
    for i, role in enumerate(s.npc_roles): s.sites[role] = hints[i % len(hints)].copy()
    s.sites.update(mob=[26, 7], boss=[27, 28])


def prop_kinds(num):
    kind = PROFILES.get(num, (None,))[0]
    if kind == "sand_terraces": return ["m1", "m6", "m13"]
    if kind and kind.startswith("earth_"): return ["m1", "m6"]
    if kind == "wetland_glade": return ["m13", "m2"]
    if kind: return ["m2", "m2", "m10"]
    return None


def prop_limit(num):
    kind = PROFILES.get(num, (None,))[0]
    if kind and kind.startswith("earth_"): return 3
    if kind == "sand_terraces": return 8
    if kind in ("market_waterfront", "wetland_glade"): return 10
    if kind: return 12
    return None
