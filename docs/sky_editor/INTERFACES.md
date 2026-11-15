# 天空编辑器接口 V1 · 2026-11-15

## 资源与关卡

- `addons/godot_level_editor_sky/preset.gd` 是版本 1 的 Resource 定义，`.tres` 是天气参数的唯一来源。未知版本、缺少 HDRI、无效云层或雾区间在保存／应用时拒绝，不静默覆盖。
- `resources/sky_presets/builtin/` 是内置模板，工具禁止覆盖；`custom/` 存个人预设，名称与文件引用分开。复制及另存创建独立参数副本，HDRI 源图继续共享引用。
- 世界根 `runtime/world.gd` 新增 `@export sky_preset: Resource`，`.tscn` 保存该引用。`levels.xlsx` 继续保持原格式，界面从实际场景引用读取天空信息，不在配表复制天气参数或绑定。
- `refresh_sky()` 应用已绑定资源，空引用恢复原环境；`preview_sky(preset) -> PackedStringArray` 临时应用，不修改 `sky_preset`。世界校验纳入天空类型及定义校验。F5/F6 使用同一引用。
- 场景根的 setter 及 ready 在场景树就绪后应用。临时 `SkyRuntime`、主光与私有 Environment 不设置 owner，不写入用户场景。

## 原有光照与预览

运行组件通过 `World3D.environment/camera_attributes` 应用私有资源，保持一个有效的世界环境，不额外实例化 WorldEnvironment。旧主光与 FogVolume 用 RenderingServer 的实例可见性临时抑制，旧景深组件的处理暂时停止；节点的 authored 属性、共享 Environment 和基线资源不改写。结束或解除绑定时恢复原世界环境、相机属性、可见性及处理状态。

同一运行组件更新预设时复用原始恢复状态。退出场景时仅在其私有 Environment 仍是当前世界环境的情况下恢复，避免覆盖新场景环境。太阳、曝光、雾与天空资源均为实例私有，不改写共享预设。

临时预览不修改磁盘绑定，保存场景也不把临时渲染状态写入场景。场景切换、关闭工作窗口及启动试玩会恢复已绑定环境；草稿保留在编辑器面板。绑定加入 Godot 场景撤销历史，天空参数编辑采用独立 UndoRedo；复制、保存及重开清理当前草稿历史。未保存草稿切换预设会被阻止。

## HDRI 与导出

导入复制到项目目录，文件名包含源内容散列，避免同名素材覆盖；Godot 完成导入后引用 Texture2D。HDRI 用 PanoramaSkyMaterial；选择颜色补光时保留 HDRI 背景与反射，环境补光改用颜色。程序云层是静态、带种子的平面投影，使用相机位置和世界高度；不创建云海节点。

`sky/export_plugin.gd` 注册到统一套件，收集天空 `.tres` 及递归依赖；HDRI 同时打包 `.import` 和实际导入纹理。已通过独立 PCK 运行读取 HDRI 的检查；没有验证 Windows 可执行文件或移动平台。

## 文件归属

天空模块只新增 `addons/godot_level_editor_sky`、`resources/sky_presets`、`tools/sky_editor`、`docs/sky_editor`。公共接入是 suite/plugin.gd 的天空页及导出／保存／预览生命周期，level_warehouse.gd 的关卡信息和新关卡默认引用，runtime/world.gd 的引用与应用接口。关卡图入口移除与 Room 校验属于另一聊天的箱庭改动，本专项保留其补丁。
