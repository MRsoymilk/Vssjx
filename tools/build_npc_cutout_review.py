"""Validate ImageGen PNGs and build a non-destructive before/after review.

This tool reads pixels only. It never paints, masks, resizes, or rewrites PNGs.
Image editing was performed with the built-in image_gen tool; exact prompts
and original screenshot regions remain in the recovery records.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import html
import json
import os
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "analysis/recovery/ssjx-pic/npc-cutouts"
CATALOG = ROOT / "client/assets/data/recovered-npcs-ssjx-pic.json"
TYPES = {"background_removal": "AI辅助去背景", "edge_completion": "边缘补全",
         "occlusion_fill": "遮挡修复", "full_body_reconstruction": "缺失身体补全"}


def checksum(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def href(path: str | Path) -> str:
    target = path if isinstance(path, Path) else ROOT / path
    return html.escape(os.path.relpath(target, OUT).replace("\\", "/"), quote=True)


def inspect_png(path: Path) -> dict:
    with Image.open(path) as image:
        if image.mode != "RGBA":
            raise ValueError(f"Not RGBA: {path}")
        alpha = image.getchannel("A")
        histogram = alpha.histogram()
        if histogram[0] == 0 or histogram[255] == 0:
            raise ValueError(f"Missing transparent background or opaque foreground: {path}")
        # Ignore near-invisible alpha=1 dust from generation for framing metrics.
        visible = alpha.point(lambda value: 255 if value >= 16 else 0).getbbox()
        if not visible:
            raise ValueError(f"Empty visible sprite: {path}")
        left, top, right, bottom = visible
        if min(left, top, image.width - right, image.height - bottom) < 2:
            raise ValueError(f"Character touches canvas edge: {path}")
        if histogram[0] / (image.width * image.height) < 0.15:
            raise ValueError(f"Suspiciously opaque background: {path}")
        return dict(width=image.width, height=image.height, mode=image.mode,
                    alpha_range=list(alpha.getextrema()), transparent_pixels=histogram[0],
                    transparent_fraction=round(histogram[0] / (image.width * image.height), 6),
                    visible_alpha_threshold=16, visible_rect_xyxy=list(visible),
                    foot_anchor_pixels=[round((left + right) / 2, 2), bottom],
                    visible_margin_pixels=[left, top, image.width - right, image.height - bottom])


def build() -> dict:
    source = json.loads((ROOT / "analysis/recovery/ssjx-pic/manifest.json").read_text("utf-8"))
    npc = [r for r in source["records"] if r["category"] == "npc"]
    job_data = json.loads((OUT / "jobs.json").read_text("utf-8"))
    jobs = job_data["jobs"]
    records = []
    seen = set()
    for job in jobs:
        if job["group"] in seen:
            raise ValueError("Duplicate appearance group: " + job["group"])
        seen.add(job["group"])
        related = [r for r in npc if r["appearance_group"] == job["group"]]
        if not related:
            raise ValueError("No original screenshot region for " + job["id"])
        path = ROOT / job["output"]
        input_path = ROOT / job["source_crop"]
        original = next(r for r in related if r["id"] == job["id"])
        if checksum(input_path) != original["crop_sha256"]:
            raise ValueError("Original crop changed: " + job["id"])
        info = inspect_png(path)
        record = dict(id=job["id"], name=job["name"], appearance_group=job["group"],
                      texture="res://" + job["output"].removeprefix("client/"),
                      path=job["output"], sha256=checksum(path), image=info,
                      repair_type=job["repair_type"], repair_label=TYPES[job["repair_type"]],
                      repair_instructions=job["repair"], ai_edited=True,
                      exact_original_pixels=False, original_animation_recovered=False,
                      frames=1, runtime_enabled=False,
                      source_crop=job["source_crop"], source_crop_sha256=checksum(input_path),
                      source_region_ids=[r["id"] for r in related],
                      aliases=[dict(region_id=r["id"], name=r["name"], service=r.get("service"),
                                    source_screenshot=r["source_path"], source_bbox=r["bbox"],
                                    name_confidence=r.get("name_confidence", "not_separately_assessed")) for r in related])
        records.append(record)
    expected_groups = {r["appearance_group"] for r in npc if r["appearance_group"]}
    if seen != expected_groups:
        raise ValueError("Uncovered appearance groups: " + str(seen ^ expected_groups))
    unresolved = [dict(region_id=r["id"], name=r["name"], source_crop=r["crop"],
                       source_label=r.get("label_crop"), status="insufficient_visual_evidence",
                       reason="仅姓名文字或极少被界面遮挡的边缘像素；不能据此确定完整人物外观，未生成任意替代人物。")
                  for r in npc if not r["appearance_group"]]
    summary = dict(appearance_assets=len(records), covered_npc_observations=sum(len(r["aliases"]) for r in records),
                   unresolved_identity_only=len(unresolved),
                   repair_types=dict(Counter(r["repair_type"] for r in records)),
                   rgba_verified=len(records), original_crops_preserved=True,
                   image_bytes=sum((ROOT / r["path"]).stat().st_size for r in records),
                   original_gameplay_bindings_changed=0)
    runtime_path = OUT / "runtime-bindings.json"
    if runtime_path.exists():
        runtime = json.loads(runtime_path.read_text("utf-8"))
        summary["runtime_maps"] = runtime["map_count"]
        summary["runtime_residents"] = runtime["resident_count"]
        for record in records:
            uses = [r for r in runtime["bindings"] if r["asset_id"] == record["id"]]
            record["runtime_enabled"] = bool(uses)
            record["runtime_actor"] = uses[0]["art"] if uses else None
            record["runtime_resident_count"] = len(uses)
    catalog = dict(format_version=1, source="用户ssjx_pic截图 + built-in image_gen编辑",
                   status="静态透明人物修复稿；小尺寸派生图已应用共用地图" if runtime_path.exists() else "静态透明人物修复稿，供审阅；未绑定运行NPC", summary=summary, records=records,
                   unresolved=unresolved,
                   provenance="analysis/recovery/ssjx-pic/npc-cutouts/jobs.json",
                   notice="包括去背景稿在内，全部经过生成式图像编辑，颜色、表情、轮廓可能发生变化；不能称为逐像素恢复。补全部分为AI推测，非原包事实。")
    write_json(CATALOG, catalog)
    write_json(OUT / "manifest.json", catalog)
    write_json(OUT / "validation.json", dict(checks=["all_20_groups_covered", "27_observations_mapped",
                "all_pngs_rgba", "real_zero_alpha_pixels", "opaque_character_pixels", "visible_silhouette_inside_canvas",
                "original_crop_sha256_unchanged"], summary=summary,
                visual_review="已逐张对照原裁片查看；头部、发型与服装可辨，文字、地面和邻近人物已移除。仍保留生成式变化风险。",
                pixel_editing_in_this_script=False))
    make_page(records, unresolved, summary)
    return summary


def make_page(records: list[dict], unresolved: list[dict], summary: dict) -> None:
    cards = []
    for row in records:
        title = html.escape(row["name"])
        aliases = html.escape(" / ".join(r["name"] for r in row["aliases"]))
        instructions = html.escape(row["repair_instructions"])
        cards.append(f'''<article data-kind="{row['repair_type']}"><h2>{title}</h2>
<p class="tag">{row['repair_label']} · RGBA · {row['image']['width']}×{row['image']['height']}</p>
<div class="pair"><figure><div class="original"><a href="{href(row['source_crop'])}"><img src="{href(row['source_crop'])}" alt="原截图裁片"></a></div><figcaption>原截图裁片</figcaption></figure>
<figure><div class="result"><a href="{href(row['path'])}"><img src="{href(row['path'])}" alt="透明人物修复稿"></a></div><figcaption>透明稿 · AI辅助处理</figcaption></figure></div>
<p class="aliases">关联：{aliases}</p><details><summary>补全约束与来源</summary><p>{instructions}</p><code>{html.escape(row['texture'])}</code></details>
<p><a download href="{href(row['path'])}">保存透明 PNG</a> · <a href="{href(row['source_crop'])}">查看原裁片</a></p></article>''')
    unresolved_cards = []
    for row in unresolved:
        unresolved_cards.append(f'<li><b>{html.escape(row["name"])}</b>：{row["reason"]} <a href="{href(row["source_crop"])}">裁片</a> · <a href="{href(row["source_label"])}">文字证据</a></li>')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>NPC透明抠图与补全对照</title><style>
:root{--tile-a:#e1e6ee;--tile-b:#bec7d4}*{box-sizing:border-box}body{margin:0;background:#0c1422;color:#e9f0fa;font:15px/1.65 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1500px;margin:auto;padding:28px}h1{font-size:29px;margin:0}header{max-width:1150px}header p{color:#b3c4d9}.notice{padding:12px 16px;background:#232b36;border-left:4px solid #ecc17c}a{color:#8ccaff}nav{position:sticky;top:0;background:#0c1422f2;display:flex;gap:10px;flex-wrap:wrap;padding:14px 0;z-index:1}input,select{background:#18283c;color:white;border:1px solid #43546c;border-radius:6px;padding:10px}#cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(370px,1fr));gap:18px}article{background:#172336;border:1px solid #304157;border-radius:10px;padding:16px}article[hidden]{display:none}h2{font-size:19px;margin:0}.tag{font-size:13px;color:#efc788}.pair{display:grid;grid-template-columns:1fr 1fr;gap:12px}figure{margin:0;min-width:0}figure>div{height:260px;display:flex;align-items:center;justify-content:center;border-radius:6px}.original{background:#0a111d}.result{background-color:var(--tile-a);background-image:conic-gradient(var(--tile-b) 25%,transparent 0 50%,var(--tile-b) 0 75%,transparent 0);background-size:20px 20px}figure a{height:100%;width:100%;display:flex;align-items:center;justify-content:center}img{max-height:244px;max-width:100%;object-fit:contain;image-rendering:pixelated}.original img{width:auto;max-width:96%}figcaption{text-align:center;font-size:12px;color:#b0c3d8;padding-top:5px}.aliases{color:#b8cbdf;font-size:13px}details p,code{font-size:12px;color:#9fb7d2;overflow-wrap:anywhere}summary{cursor:pointer}.unresolved{margin-top:30px;padding:20px;background:#1d2735;border-radius:10px}@media(max-width:500px){main{padding:14px}#cards{grid-template-columns:1fr}figure>div{height:230px}img{max-height:218px}}
</style><main><header><h1>NPC · 透明抠图与缺损补全</h1><p>20 张独立透明 PNG · 对应 27 条人物观察 · 10 张去背景稿 + 10 张边缘／遮挡／身体补全稿。</p>
<p class="notice">全部使用内置 image_gen 编辑。生成式抠图也可能改变表情、颜色和轮廓；修复稿供项目使用与审阅，不能称为原包像素的精确恢复。补全范围写在每张图的说明里。原裁片完整保留。</p>
<p><a href="../index.html">全部截图资源</a> · <a href="manifest.json">人物索引与来源</a> · <a href="jobs.json">完整提示词</a> · <a href="validation.json">透明通道验证</a></p></header>
<nav><input id="q" type="search" aria-label="搜索人物名称" placeholder="搜索人物名称…"><select id="kind" aria-label="处理类型"><option value="all">全部处理类型</option><option value="background_removal">去背景</option><option value="repair">含补全／修复</option></select><select id="background" aria-label="透明背景预览"><option value="checker">透明棋盘</option><option value="dark">深色底</option><option value="light">浅色底</option><option value="grass">草地色底</option></select><span id="count"></span></nav>
<div id="cards">CARDS</div><section class="unresolved"><h2>2 条身份记录：外观证据不足</h2><ul>UNRESOLVED</ul></section></main><script>
const q=document.getElementById('q'),kind=document.getElementById('kind');function filter(){let n=0;document.querySelectorAll('article').forEach(el=>{let match=el.textContent.toLowerCase().includes(q.value.trim().toLowerCase())&&(kind.value==='all'||(kind.value==='repair'?el.dataset.kind!=='background_removal':el.dataset.kind===kind.value));el.hidden=!match;if(match)n++});document.getElementById('count').textContent=n+' 张'}q.addEventListener('input',filter);kind.addEventListener('change',filter);document.getElementById('background').addEventListener('change',e=>{const colors={checker:['#e1e6ee','#bec7d4'],dark:['#07101a','#07101a'],light:['#f9fafc','#f9fafc'],grass:['#92bd64','#92bd64']}[e.target.value];document.documentElement.style.setProperty('--tile-a',colors[0]);document.documentElement.style.setProperty('--tile-b',colors[1])});filter();</script></html>'''
    runtime_note = ''
    if summary.get('runtime_maps'):
        runtime_note = f'<p>已应用共用地图：{summary["runtime_maps"]}张地图、{summary["runtime_residents"]}位现有NPC；使用40～60像素高的小尺寸派生图。<a href="runtime-bindings.json">查看地图绑定</a></p>'
    (OUT / "index.html").write_text(page.replace("CARDS", "\n".join(cards)).replace("UNRESOLVED", "\n".join(unresolved_cards)).replace('<nav>', runtime_note+'<nav>', 1), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(build(), ensure_ascii=False, indent=2))
