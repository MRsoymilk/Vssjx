# NPC透明抠图与补全

根据用户“尽量从背景提取人物，不全的尝试补全”的追加要求，使用**内置 `image_gen`**，分别编辑20个外观组；没有使用CLI或外部API回退。每个人物一张独立透明PNG，复用外观通过索引关联。

打开 [原裁片／透明稿对照页](index.html)。20张图覆盖27条有外观的NPC观察，其中10张主要去背景、4张补边缘、5张修复文字或玩家遮挡、1张补全缺失身体（时尚先锋）。所有原裁片保留，人物名沿用前次目读及置信标记。

## 文件

- 透明PNG：`client/assets/recovered/ssjx_pic/npcs/*.png`。
- 项目资源索引：[`client/assets/data/recovered-npcs-ssjx-pic.json`](../../../../client/assets/data/recovered-npcs-ssjx-pic.json)。含 `res://` 资源路径、原裁片及摘要、关联NPC、修复类型、图像尺寸、透明通道统计和脚部锚点提示。
- [完整提示词及逐图处理要求](jobs.json)。`repair` 写明去除和补全的范围，`prompt` 保存实际提交给内置工具的完整提示词。生成文件已复制到项目，不依赖个人生成目录。
- [清单](manifest.json)、[验证记录](validation.json)。

PNG保留内置工具输出的真实Alpha及原始分辨率，未通过Python绘制、抠色、缩放、重新编码或修改图像。验证脚本只读取像素和元数据；网页使用CSS缩放预览，不更改PNG。

## 补全与使用边界

**包括去背景稿在内，全部经过生成式编辑，不能声称原像素完全不变。** 工具可能改变表情、颜色、轮廓和像素排列，尤其缺失身体或被大面积遮挡的部位含AI推测。它们是可供审阅的静态修复素材，不是原包精灵、四向动作或完整动画。

部分同外观人物（例如天池上人／独指人、齐霞儿／医者、达人使者／博浪沙火鹤）指向同一PNG，不重复生成。外观关联基于人工视觉判断，未证明其原始资源ID相同。NPC身份、站位、任务和服务文字保留。

## 地图应用

20种外观的小尺寸派生图已应用本地／联机共用目录的 **213张地图、1,100位现有NPC**。9处按已知同名NPC直接对应，12处根据同屏身份／服务或角色用途适配，1,079处用于原有AI人物的地域外观。新手灵空台的三位引导人物保留原外形。没有新增NPC、改名、移动站位或更换任务发布人。

齐霞儿用于天化村，五毒天王用于花涧派，周轻云用于幻波池，诸有功和博浪沙火鹤用于慈云寺北，天池上人和隐名剑仙用于昆仑派，杂货店老板用于八旗镇。没有直接姓名依据的借用明确标为 `context_or_service_adaptation` 或 `authored_appearance`，不将外观相同写成人物身份相同。

- [逐个地图绑定记录](runtime-bindings.json)：地图、NPC ID、名称、格子、服务、外观资源及适配理由。
- 运行PNG：`client/assets/actors/npc_ssjx_*.png`，由原透明稿确定性裁边、最近邻缩小和添加2像素透明边距生成，可见高度40～60像素。
- 运行元数据：`client/assets/data/actors/npc/ssjx_*.json`，单静态帧，脚部锚点位于地面原点，使用既有点击判定、名字和任务标记。
- 高分辨率透明稿保持原样。`runtime_enabled:true` 表示对应派生图已被地图使用；运行资源键写在 `runtime_actor`，不是直接把千像素高的大图画进地图。

重建顺序：

```powershell
python tools/build_recovered_npc_art.py
python tools/build_ai_world.py
python tools/build_npc_cutout_review.py
```

基础资源导入器也包含这20项，后续重建不会漏掉NPC。接入与实际渲染的验证记录见 [NPC地图验证](../../../../tests/recovered_npc_maps.md)。

红发老祖、铁钟道人（读字待核）在这批资料中仅能保留文字或极少被界面遮挡的边缘像素，缺乏可靠的完整外观；没有任意生成一个角色冒充还原。两条记录仍在清单中标为 `insufficient_visual_evidence`。

## 验证与复建审阅页

```powershell
python tools/build_npc_cutout_review.py
```

验证包括20组外观覆盖、27条人物映射、全部PNG为RGBA、存在完全透明背景和不透明角色像素、可见轮廓未触及画布边界、原裁片SHA-256未变。Alpha低于16的微小近透明边缘不参与可见轮廓和脚部锚点估算，原PNG不被改写。

重建命令只校验现有图片并生成JSON／HTML，不会重新调用图像生成。重新生成图像需明确执行内置 `image_gen` 编辑，使用 `jobs.json` 中的提示词和输入裁片；不要将生成结果覆盖到原始证据目录。
