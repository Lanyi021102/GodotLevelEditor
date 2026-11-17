## 插件目录与原生场景合同 · 2026-11-17

插件本体、示例素材和运行依赖统一到 `addons/godot_level_editor/`；各模块代码在其中的 `modules/`。作者地图、配表与个人资源迁入 `content/`，已有稳定 ID 与 UID 保留；路径迁移表见 `tools/release/layout-migration.json`。

地图采用 Godot 原生文件系统、场景树、保存与 F6，保留轮盘、白盒、点线面和场景对象绑定。独立窗口“关卡”只显示当前场景的常驻图，旧“我的关卡”卡片／删除流程不再是当前入口。原生保存通过 native_level_registry 登记任务所需 ID，地图路径允许插件目录以外的项目目录。

主插件负责内部模块生命周期和缺省输入／配表初始化；运行服务使用 GLELightZones、GLENoiseBus、GLESaveSystem。用户主场景、已有输入和作者作品不由插件更新覆盖。下面的旧路径和目录入口仅记录当时合同；当前布局与实际验证见 [迁移记录](../cleanup/plugin_2026-11-17/validation.md) 和 [安装指南](../wiki/plugin-install.md)。

# 天空编辑器接口 V1 · 2026-11-15

## 按需窗口初始化兼容 · 2026-11-16

天空页可在关卡页尚未创建时直接打开。当前关卡中文名优先使用已初始化关卡目录，否则只读取并缓存关卡工作簿元数据，不触发关卡页面构建；预设、临时预览、绑定和导入协议保持。启动与实际页面检查见 [套件启动验证](../godot_level_editor_suite/startup_2026-11-16/validation.md)。

## 分类界面更新 · 2026-11-16

- `panel.gd` 的五个分类页分别为天空背景、时间与太阳、环境光、云层、雾；每页独立滚动，切换预设保留当前分类。预设名称、保存状态、关卡中文名及绑定操作常驻显示。沿用套件字体、缩放和现有资源显示名。
- 数字、颜色、时刻控件位于 `number_edit.gd`、`color_edit.gd`、`time_edit.gd`，滑块外观由 `slider_style.gd` 局部提供。数值保留 `.value/.editable/set_value_no_signal` 接口，颜色提供 `.color/set_color_no_signal`，用于草稿同步与撤销；不改预设字段、路径或版本。
- 时刻以 HH:MM 编辑，内部仍存浮点小时；云量／雾浓度显示百分比，内部仍为 0–1。颜色仍存 Color，界面允许 #RRGGBB 输入。无效时间／色值保留合法值并反馈错误。
- 自动模式只显示计算结果；手动输入行不显示旧值。`sun_mode:1→0` 把当前 `solar_angles()` 复制到手动 elevation/azimuth，和模式修改在同一个撤销动作中。切换期间不写资源文件。
- 数字显示精度与箭头增量分开，避免 min=1、step=10 把 1200m 显示成 1201m，或把 1.08 曝光显示成 1.1。HDRI／模板、补光来源和云雾开关决定可见参数；收起时保留数值。
- HDRI 请求归属、锁定、错误恢复与保存／绑定合同保持。界面重建期间抑制旧控件的焦点回调写入新草稿。检查见 [本次验证](ui_2026-11-16/validation.md)。

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

2026-11-16 QA-09 修复合同：导入持有递增请求号和发起导入的草稿引用，异步等待后均校验请求、目标与面板生命周期。导入期间禁用或拒绝预设切换、新建、复制、还原、保存／另存及绑定，`save_external()` 不提前保存导入中的草稿；再次导入也被拒绝。完成、读取／图像／导入错误或面板退出时解除锁定，结果仅应用到仍为同一请求的原草稿；对象已替换则取消，不应用到当前另一草稿。同一草稿的其他参数编辑可继续；结束预览和关闭工作窗口仍可用，完成后不自动重开窗口或恢复预览。模块 headless／Metal 各 53 项及运行 32 项通过，总控天空回归另列，见 [QA 记录](../qa/bugfix_2026-11-16/validation.md)。

导入复制到项目目录，文件名包含源内容散列，避免同名素材覆盖；Godot 完成导入后引用 Texture2D。HDRI 用 PanoramaSkyMaterial；选择颜色补光时保留 HDRI 背景与反射，环境补光改用颜色。程序云层是静态、带种子的平面投影，使用相机位置和世界高度；不创建云海节点。

`sky/export_plugin.gd` 注册到统一套件，收集天空 `.tres` 及递归依赖；HDRI 同时打包 `.import` 和实际导入纹理。已通过独立 PCK 运行读取 HDRI 的检查；没有验证 Windows 可执行文件或移动平台。

## 文件归属

天空模块只新增 `addons/godot_level_editor_sky`、`resources/sky_presets`、`tools/sky_editor`、`docs/sky_editor`。公共接入是 suite/plugin.gd 的天空页及导出／保存／预览生命周期，level_warehouse.gd 的关卡信息和新关卡默认引用，runtime/world.gd 的引用与应用接口。关卡图入口移除与 Room 校验属于另一聊天的箱庭改动，本专项保留其补丁。
