# 蜀山剑侠Online MRP 静态逆向记录（2026-10-16 更新）

## 本轮实际结果

已修正旧 ARM 扫描器，并运行新的 ARM/Thumb 混合静态控制流分析、SDK 表布局交叉核对和资源缺口检查。仍未恢复原始服务器地址、完整报文协议、在线服务器或服务器下发资源。

输入：`unpacked/ssjx/gameonline.ext`，204904 字节。
SHA-256：`e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03`。
分析前后及所有报告中的输入哈希一致；未修改或执行原始 ARM/Thumb 程序。

## 修正的错误

1. 旧脚本使用 defaultdict，在评分时为没有调用者的函数插入空记录，导致调用目标数从 3 被错误统计为 14。已改为不产生读取副作用的普通字典。
2. 旧脚本的 51224 项不是有效指令总数。重新生成的 ARM 粗扫描为 39898 个可解码项、11326 个跳过数据项；这仍不是正确 ARM/Thumb 模式下的代码总量。
3. 恢复 LR（例如 POP LR）不能单独视为函数返回；现在分别处理 BX LR、POP/LDM PC、MOV PC,LR。
4. 入口 `0x00000014: BLX 0x0002cd64` 切换到 Thumb。新脚本处理 ARM/Thumb 切换、2/4 字节宽度、条件分支、返回和文字常量池边界。
5. 数值常量与 PC 推导地址分开跟踪，避免把长度、标志等小整数当成字符串或函数地址。
6. 真正的调用点和无法确定是尾调用还是返回的间接跳转分开计数。不能解析的跳转、IT/跳转表等控制流明确保留为未解析项，不猜测目标。

## 工具与输出

Capstone 5.0.6 已在 `.python_deps/` 本地安装；“缺少 Capstone”的早期结论已过时。

- `disassemble_gameonline.py`：修正后的旧 ARM 粗扫描，用于保留对照，不是主要结果。
- `disassemble_gameonline_mixed.py`：混合控制流、函数候选、调用点、PC 地址、文字常量池和字符串引用；支持 `--self-check`、`--verify-results`。
- `analyze_gameonline_resources.py`：公开 SDK 布局匹配、间接调用线索与本地资源检查。
- `mrp_sdk_reference.json`：固定公开参考版本及表字段来源。
- `disasm/gameonline_functions.asm`：含模式、调用和字符串注释的函数候选汇编。
- `disasm/gameonline_functions.tsv`、`gameonline_calls.tsv`、`gameonline_strings.tsv`：索引。
- `disasm/gameonline_mixed.json`、`gameonline_mixed_report.md`：完整结构化分析和概览。
- `disasm/gameonline_resource_findings.json`、`gameonline_resource_findings.md`：SDK/资源线索及依据。
- `disasm/gameonline_verification.json`：输入哈希、检查结果及生成文件大小/哈希清单。

## 已核对统计

| 指标 | 结果 |
|---|---:|
| 函数候选 | 1590 |
| ARM / Thumb 候选 | 42 / 1548 |
| 入口及地址取用图内候选 | 8 |
| 其余启发式扩展候选 | 1582 |
| 去重解码指令项 | 73785 |
| 独立调用点 | 9113 |
| 解析为本地目标的调用点 | 8901 |
| 未解析调用点 | 212 |
| 非空且去重的本地调用目标 | 1308 |
| 另列的歧义间接跳转点 | 17 |
| PC 地址来源的字符串引用 | 166 |
| 其中关键词引用 | 47 |
| SDK 表布局匹配点 | 156 |
| 网络 API 布局匹配点 | 0 |

这些是静态候选统计，不代表恢复了 1590 个经人工核实的完整函数；8 个入口图候选也包含地址取用候选，不等于它们全部在启动时执行。模式重叠为 0、没有触发数量上限，只说明本轮分析没有这些内部冲突，不证明所有模式和函数边界正确。

## 能用于后续重建的具体线索

| 函数候选 | 已记录的资源引用 |
|---|---|
| `thumb_00009904` | `version`、`download.str` |
| `thumb_000093c0` | `version` |
| `thumb_0000fa3c` | `login.str`、`login` |
| `thumb_000137c8`、`thumb_000139ac` | `%d.map` |
| `thumb_00026e74` | `%s/%s.mrp`、`gwy/%s.mrp` |
| `thumb_0002b25c` | `worldmap.data` |

`unpacked/ssjx` 中没有 `.map` 文件，而存在 `worldmap.data`。这构成“客户端构造数字地图文件名，但现有解包资源没有这种文件”的明确缺口线索；尚不能证明其下载命令、文件格式、下载地址或是否由客户端自行生成。

`socketicon` 只是资源名称，不能当作已经定位了网络 socket 函数的证据。

公开 SDK 表匹配到了分配、文件读写等调用；尚未匹配到 `mr_socket`、`mr_connect`、`mr_send`、`mr_recv`。这不证明游戏没有网络功能，仍可能存在未解析的平台接口、动态表或上层转发。未给未知函数强行命名为网络函数。

SDK 参考：`vmrp/vmrp`，commit `ffe01e9fc203a830ad55b6b9636500e0fdc971b4`，`mrc/mr_table_offsets.c`。表字段按 32 位指针布局匹配，不声称它就是原始客户端使用的精确 SDK 版本。源码来源记录在 `mrp_sdk_reference.json`；参考实现未合入客户端。

## 验证结果

10 项合成输入自检通过；23 项结果一致性/文件检查通过，包括模式、指令宽度、地址对齐、目标存在性、去重统计、旧报告统计及输入哈希一致性。这些检查验证分析器和输出的一致性，不替代对目标程序语义的人工验证。

部分进一步定向检查被工具安全检查拦截，本轮未完成相关函数语义和报文结构的逐项核验。

## 复现

在本目录执行：

```bash
python3 disassemble_gameonline.py && python3 disassemble_gameonline_mixed.py && python3 analyze_gameonline_resources.py && python3 disassemble_gameonline_mixed.py --verify-results
```

## 未完成与优先方向

优先核验 `%d.map` 的读取/写入调用链、资源版本与分块落盘流程，再追踪未知平台分派和消息缓冲区。需要补齐协议证据后才能实现兼容服务器；本轮没有声称补回场景数据、恢复服务器资源或让原客户端登录成功。

本轮只修改分析脚本和分析输出；未修改客户端/服务端业务代码，未连接历史服务器，未进行 Git 提交。
