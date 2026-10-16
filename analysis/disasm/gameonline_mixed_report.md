# gameonline.ext ARM/Thumb 静态控制流分析

## 输入与限制

- SHA-256: `e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03`
- 地址均为文件偏移，不是运行时绝对地址。
- 函数、语义和字符串用途需要人工复核；不把启发式候选计为完整恢复。
- 未执行原始 ARM/Thumb 程序，未发送网络请求。

## 统计

- functions: 1590
- root_graph_functions: 8
- heuristic_graph_functions: 1582
- arm_functions: 42
- thumb_functions: 1548
- unique_instructions: 73785
- decoded_code_bytes: 166614
- mode_conflict_bytes: 0
- literal_bytes: 12624
- distinct_call_sites: 9113
- ambiguous_indirect_branch_sites: 17
- resolved_local_call_sites: 8901
- unresolved_call_sites: 212
- distinct_nonempty_call_targets: 1308
- string_xrefs: 166
- keyword_string_xrefs: 47
- limit_hits: 0

## 重点字符串引用

| 函数 | 引用位置 | 字符串位置 | 内容 |
|---|---|---|---|
| `thumb_00000acc` | `0xad0` | `0x30aa8` | bag.str |
| `thumb_00002ae0` | `0x2baa` | `0x30838` | battle.str |
| `thumb_00003dc0` | `0x3dd4` | `0x307d8` | breakeffect.bin |
| `thumb_00005434` | `0x547a` | `0x30b60` | bet.str |
| `thumb_00008fa4` | `0x8fae` | `0x30a78` | cover.str |
| `thumb_000093c0` | `0x943c` | `0x30a48` | version |
| `thumb_00009904` | `0x9926` | `0x30a48` | version |
| `thumb_00009904` | `0x99ec` | `0x30a58` | download.str |
| `thumb_00009c44` | `0x9c5e` | `0x30d40` | forge.str |
| `thumb_0000a8a4` | `0xa8ba` | `0x30d00` | socketicon |
| `thumb_0000acc8` | `0xadf0` | `0x30d40` | forge.str |
| `thumb_0000b644` | `0xb69c` | `0x30d00` | socketicon |
| `thumb_0000d864` | `0xd868` | `0x30d4c` | guild.str |
| `thumb_0000d9b0` | `0xd9b4` | `0x30d4c` | guild.str |
| `thumb_0000db74` | `0xdb78` | `0x30dfc` | heroui.str |
| `thumb_0000f118` | `0xf11c` | `0x31654` | landmap.str |
| `thumb_0000fa3c` | `0xfa40` | `0x31528` | login.str |
| `thumb_0000fa3c` | `0xfa70` | `0x31510` | login |
| `thumb_0000fc04` | `0xfc2c` | `0x31510` | login |
| `thumb_00011010` | `0x11016` | `0x31510` | login |
| `thumb_00011308` | `0x1130c` | `0x30e64` | mail.str |
| `thumb_0001292c` | `0x1293a` | `0x3099c` | mainmenu.str |
| `thumb_000129da` | `0x129f2` | `0x30960` | set.str |
| `thumb_000129da` | `0x12a30` | `0x30960` | set.str |
| `thumb_000137c8` | `0x137d0` | `0x314a0` | %d.map |
| `thumb_000139ac` | `0x13abc` | `0x314a0` | %d.map |
| `thumb_000153e4` | `0x153f2` | `0x3147c` | tips%d.str |
| `thumb_00016220` | `0x16224` | `0x30e84` | mission.str |
| `thumb_00017434` | `0x17438` | `0x30f54` | pay.str |
| `thumb_000196ca` | `0x196f0` | `0x31084` | shizhuang.str |
| `thumb_0001a2f4` | `0x1a30c` | `0x3106c` | shop.str |
| `thumb_0001ab90` | `0x1abae` | `0x3106c` | shop.str |
| `thumb_0001af64` | `0x1afa0` | `0x30b68` | sm.str |
| `thumb_0001b878` | `0x1b896` | `0x310f4` | social.str |
| `thumb_0001b968` | `0x1b96c` | `0x310f4` | social.str |
| `thumb_0001ce5c` | `0x1ce90` | `0x310f4` | social.str |
| `thumb_0001ddfc` | `0x1de06` | `0x315dc` | teach.str |
| `thumb_0001f79c` | `0x1f7a0` | `0x316bc` | trade.str |
| `thumb_00020968` | `0x2096e` | `0x31140` | i18n.str |
| `thumb_0002171c` | `0x21724` | `0x31644` | worldmap.str |
| `thumb_00026e74` | `0x26e8e` | `0x313f4` | %s/%s.mrp |
| `thumb_00026e74` | `0x26e9e` | `0x31400` | gwy/%s.mrp |
| `thumb_0002b25c` | `0x2b262` | `0x31628` | worldmap.data |
| `thumb_0002f058` | `0x2f064` | `0x311c0` | commonRecord |
| `thumb_0002f090` | `0x2f09c` | `0x311c0` | commonRecord |
| `thumb_0002f0b0` | `0x2f0bc` | `0x311c0` | commonRecord |
| `thumb_0002f1cc` | `0x2f1d8` | `0x311c0` | commonRecord |

## 后续核验

优先复核下载/登录字符串的引用函数、间接调用的表偏移和调用参数；只有匹配公开 SDK 和具体机器指令后才能给 API 命名。间接跳转、回调和资源请求协议仍需补全。
