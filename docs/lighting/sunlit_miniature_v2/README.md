# 晴日微缩光照 V2

2026-11-12 第三人称适配：透视游玩镜头停用微缩景深，让远处人物、门和线索保持清晰；V2 日光、补光、环境与曝光继续保留。景深组件仍计算观察深度，正交检查视角按 `runtime_depth_of_field` 使用原景深配置。当前越肩视角与验证见 [第三人称相机](../../3cplayground/THIRD_PERSON.md)，下文保留最初光照制作记录。

2026-11-02。按用户提供的两张 Tiny Glade 参考调整光照与后期：暖色侧上方阳光、偏冷且可读的阴影、柔和的微缩景深。场景表面材质、网格、贴图与角色外观保持原样，因此当前仍呈现现有白盒的颜色和纹理。

## 接入与资源

- 默认连续世界与 `scenes/3cplayground.tscn` 使用 V2，关卡生成工具也引用 V2。
- `scenes/lighting/sunlit_miniature_v2.tscn`：可复用组合，包含日光、WorldEnvironment、云层及景深跟随组件。一个世界实例化一套。
- `resources/lighting/sunlit_miniature_v2.tres`：天空、环境补光、色调映射、环境遮蔽、间接光与辉光参数。
- `scripts/presentation/miniature_lighting.gd`：运行时挂载并更新本组合的景深范围；编辑器中 WorldEnvironment 不挂载 CameraAttributes，不更改相机投影、旋转、跟随或操作方式。
- `assets/shaders/lighting/sunlit_miniature_v2_clouds.gdshader`：岛下云层采用两层三维噪声，缓慢漂移，形成空白区域的柔和云团。体积范围 Y=-23～1，密度从岛面下方渐增，Y=0 处始终为 0。其他海拔的关卡需调整云层与高度遮罩。

V1 的场景、Environment 和两份着色器逐字节保留，可将 Lighting 的场景引用切回 `cloud_island_v1.tscn` 对比。表面材质、角色资源、机关和回溯逻辑保持原样。四个现用房间及 3C 岛面的地板向下加厚到 3.6m，对应地板碰撞同步加厚，顶面仍在 Y=0。其他物块、接驳点、布局和用户自建资源不由光照组件改写。

## 参数与效果

| 项目 | V2 |
|---|---|
| 主光 | 俯角 48°，水平角 -38°；暖白，能量 2.65 |
| 补光 | 冷蓝白，能量 0.32；V1 为 0.65，减少整体灰平 |
| 阴影 | 角直径 1.8°、模糊 1.6、法线偏置 0.4；全局软阴影采样改为 Medium，4096 阴影图 |
| 色调与后期 | AgX、曝光 1.08；对比度 1.06、饱和度 1.03；仅高亮参与的低强度辉光 |
| 接触与间接光 | SSAO 强度 1.4、半径 0.7；SSIL 强度 0.4，帮助转角和物体接触处表现层次 |
| 雾 | 关闭覆盖全画面的普通距离雾；岛下有两层噪声控制的云团，密度参数 0.14，缓慢流动 |
| 景深 | 强度 0.085；焦点前 4.5m、后 5.5m 保持清晰，前后分别以 6m/9m 渐变进入虚化 |

在 Lighting/Sun 调整日光；在 WorldEnvironment 的 Environment 调整补光与后期；在 Lighting 根节点调整 `sharp_near_margin`、`sharp_far_margin`，在 `runtime_camera_attributes` 调整游戏中的虚化强度和过渡距离。`runtime_depth_of_field` 控制运行时景深。编辑视口始终清晰；已有编辑器会话若缓存了旧景深资源，先保存自己的修改，再重新打开工程刷新。

景深资源在运行游戏时才挂到 WorldEnvironment，编辑器不会得到它；脚本也会清除自身编辑实例的 CameraAttributes。游戏中使用相机的实际观察深度，随已有相机缩放、旋转及跟随更新，暂停时仍工作。每个实例的资源独立；相机若显式设置了自己的 Attributes，仍按 Godot 的覆盖规则优先使用相机设置。固定曝光避免转动镜头造成亮度跳变。

## 验证与截图

- 无界面导入检查通过。
- 光照专项：11 项通过，包含人物头脚及近处交互区域保持在焦内、最小/最大缩放与旋转、暂停观察、资源实例隔离及 V1 可加载。
- 当前 3C 集成：33 项通过，覆盖走跑刹停、跳跃、回溯、多个固定分身、主动交互回放与默认世界装配。
- 实际 Metal Forward+、1600×900 渲染检查默认关卡的出生点、近景和机关区域，以及 3C 测试场。截图直接来自游戏视口，未作图片后期处理。
- 源文件校验：本次编辑的三个既有源文件，变化仅为 Lighting 引用从 V1 改为 V2；Project Settings 另增加软阴影质量配置。角色资产、用户房间与机关资源、V1 光照均与开工校验值一致。检查期间另外观察到 `assets/shaders/whitebox/metric_grid.gdshader` 与 `addons/godot_level_editor/runtime/whitebox_block.gd` 出现并行更新（曲面网格投影），本次未写入或回退这两个文件，因此不把全工程表面材质声明为逐字节未变。详情见 `validation.json`。

[同机位修改前](before.png) · [当前出生点](preview.png) · [近景](close.png) · [机关区域](mechanisms.png) · [3C 测试场](playground.png)

复查入口：`tools/lighting/test_lighting.tscn`、`tools/3c/test_3c.tscn`。实际截图工具为 `tools/lighting/capture_lighting.tscn`，支持 `--scene=...`、`--lighting=...` 和 `--capture-dir=/absolute/path`；禁用持续进度读写，不保存试玩状态。

接口变化仅为新增可复用 V2 光照组合与其景深组件，现有关卡、角色、编辑器及会话接口不变。未恢复历史演示。

## 后续调整：云雾、厚底板与编辑景深

2026-11-02，按两次后续反馈更新：空白区域显示有流动层次的雾，底板向下加厚，景深限于游戏运行。`tools/level_editor/build_sample.gd` 重建样例时也保留 3.6m 厚度；未运行该重建工具覆盖当前关卡。

最终专项检查 18 项通过，当前 3C 检查 33 项通过，关卡接口与实际连通/通关检查 82 项通过。新增检查覆盖编辑场景不挂景深资源、游戏启用景深不会污染编辑资源，以及四房地板顶面高度保持为 0。实际 Forward+ 图形检查与记录见 `cloud_edges_validation.json`。

[云雾与厚底板实际画面](cloud_edges.png) · [近景](cloud_edges_close.png)

景深参数依据 [Godot CameraAttributesPractical](https://docs.godotengine.org/en/stable/classes/class_cameraattributespractical.html)，环境选项见 [Godot Environment and post-processing](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html)。
