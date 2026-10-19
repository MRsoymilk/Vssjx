# 游戏音频

运行时与资源管理共用 `client/assets/data/audio-v1.json`，按稳定音频ID记录资源路径、名称、技能绑定、触发时机、默认音量与来源。新增音频须登记清单，不从网络消息加载任意路径。

## 雷霆一击

- 用户提供的 `thunder.wav` 原样保存在 `client/assets/audio/skills/thunder.wav`，SHA256为 `b6bda3ddd73ab62003919cfc961b0c94df2b06ee06025a3e069867ff75e52c77`。
- WAV为48kHz、16位双声道，时长约1.648秒。未裁剪、归一化或重编码原文件。
- 技能 `sheet_010` 在 `skill-effects-v1.json` 通过 `audio_id: thunder` 绑定，和命中特效的 `cast_impact` 同步，每次播放一次。普通攻击、其他技能及相同战斗修订的界面刷新不触发。
- 通过场景 `skill_sound.tscn` 创建播放器，默认-6dB，播放结束释放；取消／离开战斗停止并清理。复用本地、联网PVE、队伍和切磋的公共特效入口；音频不影响伤害和服务器结算。
- `skill_audio_test.tscn` 11项通过，包含实际本地／联网命中时机、刷新去重及取消清理；音频文件与原始文件SHA256一致。未重新导出或部署客户端。
