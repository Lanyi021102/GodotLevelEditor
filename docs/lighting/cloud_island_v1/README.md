# 白模空岛氛围 · 光照 V1

2026-11-02，按用户要求从清理前恢复包提取，作为第一版光照基线保留。

## 使用

- `scenes/lighting/cloud_island_v1.tscn`：完整可复用组合，包含 WorldEnvironment、日光与下方云海。在场景中实例化一次即可使用；同一世界使用一套 WorldEnvironment 与日光。
- `resources/lighting/cloud_island_v1.tres`：可直接在 Inspector 编辑的 Environment 资源。
- `assets/shaders/lighting/cloud_island_v1_sky.gdshader`：原版暖灰渐变天空。
- `assets/shaders/lighting/cloud_island_v1_clouds.gdshader`：原版高度渐浓云雾。

V1 作为独立基线保留。当前连续世界和 3C 测试场已切换到 [晴日微缩光照 V2](../sunlit_miniature_v2/README.md)，V1 场景、环境与着色器仍保持原样。将 Lighting 引用切回本场景即可对比。

## 原版参数

日光颜色 `#fff3df`，能量 1.85，角直径 1.7，阴影模糊 2.2；环境补光 `#d7e1e7`、强度 0.65；AgX 曝光 1.0；SSAO 半径 0.65、强度 1.7。

普通雾颜色 `#d8d9cf`、密度 0.0009。体积雾的全局密度为 0，通过 CloudSea 的高度着色器实现局部密度；云海中心 `(0,-16,0)`、尺寸 `(180,38,180)`，密度参数 0.48。从岛面以下逐渐加浓，保留可行走区域的清晰度。云海采用世界高度，移动整个世界到其他海拔时需同步调整高度遮罩。

当前入口 HUD 启用 light_background，适配浅色天空上的文字对比。

当前项目开启 TAA，体积雾分辨率采用原版均衡档 96/96。云雾和 SSAO 依赖 Forward+，实际图形运行已单独验证；不沿用旧场景的性能数字。

## 保留边界

恢复的是光照、天空、云雾及参考图，当前房间、机关、角色和 HUD 继续由新工具链管理。原参考图还包含窄视角、移轴景深、灰白材质与悬浮底座；当前运行相机保留原有控制与投影，因此不承诺当前世界与原截图逐像素相同。原镜头与景深参数记录在 source.json，可供后续镜头配置复用。

[原版氛围参考](reference.png) · [当前世界效果](current_world.png)

来源和着色器 SHA-256 见 source.json；本次验证见 validation.json。
