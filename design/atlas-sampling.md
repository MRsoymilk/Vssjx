# 人物／怪物动画的边缘串帧修正

[返回设计索引](README.md) · [资源重建](../docs/resource-recovery.md)

性质：**当前渲染实现约束**。修正纹理采样而非重绘素材，不更改逻辑位移或动作时序。

用户截图显示人物和山狼在某些动画帧头顶出现横线或碎像素。原图集各帧的裁切位置正确；移动、镜像和摄像机变换产生半像素坐标时，最近邻采样也可能因纹理坐标舍入取到相邻帧边缘。紧排的动态换装帧同样受影响。

通过真实 OpenGL SubViewport 对照复现：将游戏的 AtlasTexture 帧与独立裁出的同一原始帧放在相同坐标、朝向下渲染，关闭像素对齐时可观察到不属于当前帧的像素。仅启用 AtlasTexture.filter_clip 仍可复现；开启视口的变换像素对齐后，对照差异消失。

修正包括：

- 项目根视口开启 rendering/2d/snap/snap_2d_transforms_to_pixel，覆盖战斗与人物预览。
- 本地 world_viewport.tscn 与联机 online_world_view.tscn 的 SubViewport 分别显式开启 snap_2d_transforms_to_pixel。新增 SubViewport 不会自动继承根视口设置，必须各自配置。
- OriginalArt.actor 创建的帧统一开启 filter_clip，限制绘制区域。

保持原始图像、ANI帧顺序、动作时序和角色锚点；像素对齐作用于渲染变换，逻辑位置与移动速度继续使用原精度。

验证：atlas_sampling_test.tscn 在本地和联机的真实场景视口中，对山狼、原始角色、动态换装角色的待机／行走／攻击／受击帧，检查整数、四分之一像素、半像素和镜像位置。1344组实际渲染与独立原始帧逐字节一致。hero_appearance_test 525项与monster_attack_test 153项均通过。渲染对照需要图形模式运行，headless只检查视口和图集配置。

渲染设置只随相应客户端版本生效；已有网页与 APK 是否包含修正，以具体发布记录为准。
