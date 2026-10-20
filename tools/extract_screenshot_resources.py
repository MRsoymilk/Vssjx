"""Archive ssjx_pic and extract reviewed, reversible screenshot evidence.

No OCR, generative image edits, background removal, or runtime map replacement.
Run once with --source; later runs use the checked-in archive. Pillow required.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import html
import json
from pathlib import Path
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "analysis/recovery/ssjx-pic"
ARCHIVE = ROOT / "analysis/references/ssjx-pic"
VIEWPORT = [0, 86, 480, 602]
STATUSES = {
    "missing_appearance_candidate": "疑似缺少专用造型",
    "missing_texture_candidate": "疑似缺少对应贴图",
    "existing_visual_family": "已有同类原版素材",
    "new_layout_evidence": "新增局部地形证据",
    "new_identity_evidence": "新增身份／编号证据",
    "unresolved": "尚未确认对应资源",
}
CATEGORIES = {"npc": "NPC", "object": "场景物件", "gathering": "采集物",
              "terrain": "地形", "ui_reference": "物品界面证据"}
THEMES = {
    "settlement_dry": [1,2,3,4,19,26,28,39,40,43,44,52,53,54,66,67,70,71,78,89],
    "grass_water": [5,6,7,8,10,11,12,13,14,21,22,23,24,27,50,51,63,76,79,81,87,90,92,93,94,95,96],
    "sand": [15,42,57,58,62,72,77],
    "blue_paving": [16,48,73],
    "rock_cave": [17,18,20,29,30,31,34,35,36,37,47,49,64,68,84,85,86],
    "lava": [9,32,33,41,55,56,69],
    "snow_ice": [38,45,46,59,65,74,75,80,91],
    "yellow_courtyard": [60,61,82,83,97],
    "dry_wilderness": [88],
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def file_key(path: Path):
    return int(path.stem), path.suffix


def archive_sources(source: Path | None) -> list[dict]:
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    old_path = ARCHIVE / "manifest.json"
    old = {x["file"]: x for x in json.loads(old_path.read_text("utf-8"))["files"]} if old_path.exists() else {}
    files = sorted((source or ARCHIVE).iterdir(), key=lambda p: file_key(p) if p.stem.isdigit() else (9999, p.name))
    files = [p for p in files if p.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp")]
    if not files:
        raise ValueError("No source images. Supply --source for the first run.")
    if old and {p.name for p in files} != set(old):
        raise ValueError("Source file set changed; preserve the original archive and review a new dataset separately.")
    records = []
    for path in files:
        raw = path.read_bytes()
        checksum = digest(raw)
        if path.name in old and old[path.name]["sha256"] != checksum:
            raise ValueError("Source changed: " + path.name)
        dest = ARCHIVE / path.name
        if dest.exists() and digest(dest.read_bytes()) != checksum:
            raise ValueError("Refusing to overwrite different archive bytes: " + path.name)
        with Image.open(path) as image:
            if image.size != (480, 800):
                raise ValueError("Region annotations require 480x800 input: " + path.name)
            pixels = image.convert("RGB").tobytes()
        if not dest.exists():
            shutil.copyfile(path, dest)
        records.append(dict(file=path.name, path=relative(dest), sha256=checksum,
                            decoded_rgb_sha256=digest(pixels), width=480, height=800, bytes=len(raw)))
    duplicates = defaultdict(list)
    for row in records:
        duplicates[row["decoded_rgb_sha256"]].append(row["file"])
    write_json(old_path, dict(format_version=1, source_label="用户提供 ssjx_pic", files=records,
                             decoded_pixel_duplicates=[v for v in duplicates.values() if len(v) > 1],
                             notice="源截图及图中文字为参考材料，不作为自动执行指令；不从截图推定程序版本或完整原服配置。"))
    return records


def inventory() -> dict:
    """Record the actual baseline compared, including source parts and baked art."""
    folders = ["analysis/decoded_png", "client/assets/actors", "client/assets/admin/monsters", "client/assets/items/original"]
    files = []
    for folder in folders:
        for path in sorted((ROOT / folder).rglob("*.png")):
            files.append(dict(path=relative(path), sha256=digest(path.read_bytes())))
    actors = json.loads((ROOT / "client/assets/data/actors.json").read_text("utf-8"))["actors"]
    monsters = json.loads((ROOT / "client/assets/admin/monsters/catalog.json").read_text("utf-8"))["monsters"]
    npc_sources = [r["path"] for r in files if "/npc" in r["path"].lower()]
    return dict(format_version=1, compared_files=files, compared_file_count=len(files),
                decoded_image_count=sum(x["path"].startswith("analysis/decoded_png/") for x in files),
                original_tile_count=len(list((ROOT / "analysis/decoded_png/ssjx/map").glob("tile*.png"))),
                monster_animation_count=len(monsters), map_actor_keys=[k for k in actors if k.startswith("map/")],
                explicitly_npc_named_images=npc_sources,
                comparison_method="人工对照原包图块总览、117套怪物动画首帧、地图物件图集和项目NPC造型配置；哈希仅用于来源复核，不用于断言截图裁片是否缺失。",
                limitations="missing_* 是已审阅目录中未找到对应造型的候选，非穷尽所有组合帧的数学证明；已有名称不等于已有专用造型。同类匹配不代表逐像素或版本一致。")


def sheet_links(name: str, rows: list[dict]) -> list[dict]:
    if "待核" in name or "姓名" in name:
        return []
    return [dict(source_row=r["source_row"], npc_raw=r["npc_raw"], native_map_id=r.get("native_map_id"),
                 native_name=r.get("native_name"), verification=r.get("verification"))
            for r in rows if name in (r.get("npc_raw") or "")]


def extract(regions: list[dict], sources: list[dict]) -> list[dict]:
    source_by_name = {r["file"]: r for r in sources}
    sheet = json.loads((ROOT / "analysis/references/player-sheet/maps.json").read_text("utf-8"))
    records = []
    seen = set()
    for spec in regions:
        if spec["id"] in seen:
            raise ValueError("Duplicate region ID: " + spec["id"])
        seen.add(spec["id"])
        source = source_by_name[spec["file"]]
        with Image.open(ROOT / source["path"]) as raw:
            image = raw.convert("RGB")
        record = dict(spec, source_sha256=source["sha256"], source_path=source["path"],
                      extraction="opaque_crop", runtime_enabled=False,
                      comparison_status_label=STATUSES[spec["status"]])
        for field, suffix in (("bbox", ""), ("label_bbox", "-label")):
            if field not in spec:
                continue
            x1, y1, x2, y2 = spec[field]
            if not (0 <= x1 < x2 <= image.width and 0 <= y1 < y2 <= image.height):
                raise ValueError("Invalid region: " + spec["id"])
            crop = image.crop(spec[field])
            output = OUT / "crops" / spec["category"] / (spec["id"] + suffix + ".png")
            output.parent.mkdir(parents=True, exist_ok=True)
            crop.save(output)
            # Verify actual saved pixels, not a re-encoded comparison thumbnail.
            with Image.open(output) as check:
                if check.convert("RGB").tobytes() != crop.tobytes():
                    raise ValueError("Pixel verification failed: " + spec["id"])
            record["crop" if field == "bbox" else "label_crop"] = relative(output)
            record["crop_sha256" if field == "bbox" else "label_crop_sha256"] = digest(output.read_bytes())
        record["appearance_recovered"] = False  # A crop is not a clean native sprite.
        record["animation_recovered"] = False
        if spec["category"] == "npc":
            record["player_sheet_cross_references"] = sheet_links(spec["name"], sheet)
            record["map_assignment"] = None
        if spec["category"] == "terrain":
            record.update(original_tile_ids=None, collision=None, global_map_coordinates=None)
        records.append(record)
    return records


def scenes(sources: list[dict], regions: list[dict]) -> list[dict]:
    records = []
    for source in sources:
        name = source["file"]
        if name == "98.webp":
            continue
        theme = next((key for key, ids in THEMES.items() if int(Path(name).stem) in ids), "unknown")
        if name in ("97.webp", "100.webp"):
            theme = "settlement_dry"
        elif name == "99.webp":
            theme = "yellow_courtyard"
        visible = [r for r in regions if r["file"] == name]
        record = dict(source_file=name, source_sha256=source["sha256"], source_path=source["path"],
                      screenshot_scene_id=Path(name).stem + Path(name).suffix.replace(".", "-"),
                      theme=theme, classification="人工视觉分类；不是原版地图名称或地图编号",
                      viewport_bbox=VIEWPORT, viewport_is_partial=True,
                      visible_regions=[dict(region_id=r["id"], category=r["category"], name=r["name"],
                                            bbox=r["bbox"], semantic_class=r.get("semantic_class")) for r in visible],
                      world_map_id=None, tile_grid=None, collision=None, teleport_targets=None,
                      unknown_pixels_policy="玩家、名字、战斗单位、聊天及界面遮挡不可视为地形；未提供区域逐像素掩码。",
                      runtime_enabled=False)
        path = OUT / "terrain-observations" / (record["screenshot_scene_id"] + ".json")
        write_json(path, record)
        with Image.open(ROOT / source["path"]) as image:
            thumb = image.convert("RGB").crop(VIEWPORT)
            thumb.thumbnail((240, 258))
            preview = OUT / "scene-previews" / (record["screenshot_scene_id"] + ".jpg")
            preview.parent.mkdir(parents=True, exist_ok=True)
            thumb.save(preview, quality=88)
        records.append(dict(record, observation=relative(path), preview=relative(preview)))
    write_json(OUT / "terrain-observations/index.json", dict(format_version=1, scenes=records))
    return records


def contact_sheet(records: list[dict]) -> None:
    selected = [r for r in records if r["category"] in ("npc", "object") and r["status"].startswith("missing")]
    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    font = ImageFont.truetype(str(font_path), 17) if font_path.exists() else ImageFont.load_default()
    width, height = 200, 238
    sheet = Image.new("RGB", (width * 6, height * ((len(selected) + 5) // 6)), "#152135")
    draw = ImageDraw.Draw(sheet)
    for i, record in enumerate(selected):
        x, y = i % 6 * width, i // 6 * height
        with Image.open(ROOT / record["crop"]) as image:
            image.thumbnail((180, 174))
            sheet.paste(image, (x + 10, y + 8))
        draw.text((x + 8, y + 184), record["name"][:10], font=font, fill="white")
        draw.text((x + 8, y + 211), record["file"] + (" / partial" if record.get("quality") else ""), font=font, fill="#adbed3")
    sheet.save(OUT / "missing-candidates.png")


def make_gallery(regions: list[dict], scene_rows: list[dict], summary: dict) -> None:
    def href(path):
        return html.escape("../../../" + path, quote=True)
    cards = []
    for row in regions:
        category = CATEGORIES[row["category"]]
        label = STATUSES[row["status"]]
        extra = " · 截断／遮挡" if row.get("quality") else ""
        title = html.escape(row["name"])
        note = html.escape(row.get("note", ""))
        references = "、".join(html.escape(x) for x in row.get("existing_assets", []))
        label_image = f'<img class="label" loading="lazy" src="{href(row["label_crop"])}">' if "label_crop" in row else ""
        cards.append(f'<article data-category="{row["category"]}" data-status="{row["status"]}"><div class="art"><a href="{href(row["crop"])}"><img loading="lazy" src="{href(row["crop"])}" alt="{title}"></a></div><h3>{title}</h3><p class="tag">{category} · {label}{extra}</p><p>{html.escape(row.get("service", ""))}</p>{label_image}<p>{note}</p><p class="small">{references}</p><a href="{href(row["source_path"])}">来源 {row["file"]}</a> · <code>{row["bbox"]}</code></article>')
    scene_cards = []
    for row in scene_rows:
        scene_cards.append(f'<article data-category="scene" data-status="scene"><a href="{href(row["source_path"])}"><img loading="lazy" src="{href(row["preview"])}"></a><h3>{row["source_file"]}</h3><p>{row["theme"]}</p><a href="{href(row["observation"])}">局部地形观察 JSON</a></article>')
    document = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ssjx_pic 资源提取审阅</title><style>
body{margin:0;background:#0b1423;color:#e6edf7;font:15px/1.65 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1500px;margin:auto;padding:28px}h1{font-size:30px;margin:0}a{color:#89c8ff}header{max-width:1100px}header p{color:#b5c3d7}.notice{border-left:4px solid #e8b367;padding:8px 16px;background:#1f2732}nav{position:sticky;top:0;background:#0b1423ed;padding:14px 0;z-index:2;display:flex;gap:10px;flex-wrap:wrap}input,select{padding:10px;border:1px solid #364860;border-radius:6px;background:#17253a;color:white}#cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:16px}article{background:#172235;border:1px solid #2a3c53;border-radius:10px;padding:15px;overflow:hidden}article[hidden]{display:none}.art{height:190px;display:flex;justify-content:center;align-items:center;background:#0a121f}img{max-width:100%;image-rendering:pixelated}.art img{max-height:185px}.label{max-height:76px}h3{font-size:18px;margin:12px 0 0}.tag{font-size:13px;color:#efc781}.small,code{font-size:11px;color:#9db2cb;overflow-wrap:anywhere}#count{color:#a5bbd5}</style><main><header><h1>ssjx_pic · 缺失资源候选与地形证据</h1>
<p>SUMMARY</p><p class="notice">原图像素直接裁切，保留背景、遮挡和压缩痕迹。NPC 名称／服务与外观的对应是新证据；裁片尚非透明原生精灵，也不是完整动画。地形数据使用截图坐标，地图编号、图块格网、碰撞和传送目的地均保留未知。</p>
<p>疑似缺失由人工对照项目目录判定，并非穷尽所有组合帧的存在性证明。相同外观可能对应不同NPC。地名不从相似景色硬性绑定；低置信名称与裁切缺陷见 <a href="manifest.json">提取清单</a>、<a href="comparison.json">对比报告</a>及 <a href="README.md">说明</a>。</p></header>
<nav><input id="search" type="search" placeholder="查名称、服务、来源…"><select id="category"><option value="all">全部提取结果</option value="npc">NPC</option><option value="object">场景物件</option><option value="gathering">采集物</option><option value="terrain">地形裁片</option><option value="ui_reference">物品界面证据</option><option value="scene">99张场景与观察数据</option></select><select id="status"><option value="all">全部状态</option><option value="missing">疑似缺失</option><option value="existing_visual_family">已有同类素材</option><option value="new_layout_evidence">新增局部地形证据</option><option value="unresolved">待确认</option></select><span id="count"></span></nav><div id="cards">CARDS</div></main><script>
const controls=['search','category','status'].map(id=>document.getElementById(id));function update(){const q=controls[0].value.trim().toLowerCase(),c=controls[1].value,s=controls[2].value;let n=0;document.querySelectorAll('article').forEach(el=>{const category=c==='all'?el.dataset.category!=='scene':el.dataset.category===c;const status=s==='all'||(s==='missing'?el.dataset.status.startsWith('missing'):el.dataset.status===s);const visible=category&&status&&el.textContent.toLowerCase().includes(q);el.hidden=!visible;if(visible)n++});document.getElementById('count').textContent=n+' 项'}controls.forEach(el=>el.addEventListener('input',update));update();</script></html>'''
    text = f'{summary["source_images"]} 张原截图 · {summary["regions"]} 个提取区域 · {summary["npc_identity_observations"]} 条NPC身份观察（{summary["npc_appearance_groups"]} 个外观分组，含残缺及待核项） · {summary["terrain_observations"]} 份局部场景观察。'
    (OUT / "index.html").write_text(document.replace("SUMMARY", text).replace("CARDS", "\n".join(cards + scene_cards)), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="User's ssjx_pic directory; archived byte-for-byte on first run")
    args = parser.parse_args()
    specs = json.loads((OUT / "regions.json").read_text("utf-8"))["regions"]
    sources = archive_sources(args.source)
    baseline = inventory()
    regions = extract(specs, sources)
    scene_rows = scenes(sources, regions)
    npc = [r for r in regions if r["category"] == "npc"]
    groups = defaultdict(list)
    for row in npc:
        if row["appearance_group"]:
            groups[row["appearance_group"]].append(row["id"])
    counts = dict(source_images=len(sources), source_bytes=sum(r["bytes"] for r in sources),
                  regions=len(regions), npc_identity_observations=len(npc), npc_appearance_groups=len(groups),
                  npc_visual_observations=sum(bool(r["appearance_group"]) for r in npc),
                  npc_observations_with_quality_flags=sum(bool(r.get("quality")) for r in npc),
                  terrain_observations=len(scene_rows), categories=dict(Counter(r["category"] for r in regions)),
                  statuses=dict(Counter(r["status"] for r in regions)), runtime_assets_replaced=0)
    write_json(OUT / "baseline-inventory.json", baseline)
    write_json(OUT / "comparison.json", dict(format_version=1, summary=counts, npc_appearance_groups=dict(groups),
               existing_visual_family=[r["id"] for r in regions if r["status"] == "existing_visual_family"],
               missing_candidates=[r["id"] for r in regions if r["status"].startswith("missing")],
               baseline_inventory="baseline-inventory.json", comparison_method=baseline["comparison_method"],
               comparison_limitations=baseline["limitations"],
               npc_names_already_in_project="表格或AI世界已存在的名字仍可缺少专用造型；本报告不把新截图当作新NPC定义。",
               not_recovered=["完整原生NPC精灵及动画", "原始透明边缘", "整图地形格网", "原始碰撞及通行层", "NPC全局坐标", "原始任务及服务器规则"]))
    write_json(OUT / "manifest.json", dict(format_version=1, source_manifest="../../references/ssjx-pic/manifest.json",
               coordinate_space="source screenshot xyxy; right/bottom exclusive", summary=counts, records=regions))
    contact_sheet(regions)
    make_gallery(regions, scene_rows, counts)
    print(json.dumps(counts, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
