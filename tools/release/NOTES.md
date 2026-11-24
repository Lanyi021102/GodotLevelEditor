GodotLevelEditor 0.3.0

面向零代码基础的关卡设计新人，使用 Godot 原生场景树和 3D 视口制作、保存与试玩白盒关卡。

本版更新：

- 白盒地形：通过轮盘绘制山峰、山脊、河道与高原，控制点和碰撞随关卡保存。
- 玩家 3C 预设：配置角色能力、镜头、输入与动作，将预设应用到当前关卡。
- 载具预设：放置和配置卡丁车、摩托车与悬停飞行器。
- 演出时间轴：取景、安排 NPC 走位与动作，并从关卡图或任务图触发。
- 制作与试玩改进：视口测距、NPC 实例交谈、任务执行反馈、天空缩略图及 Excel 配表冲突处理。

下载 **GodotLevelEditor-0.3.0.zip** 安装插件。需要 Godot 4.7.1 标准版。将 ZIP 中的 `addons/godot_level_editor` 放入自己的工程，等待导入，在“项目设置 → 插件”只启用 **GodotLevelEditor**。空工程会建立可直接 F5 试玩的起始场景。

更新时关闭 Godot 并替换插件目录，保留自己的 `content/` 目录。安装 ZIP 不包含作者地图、个人模型、任务／对白配表及开发测试。下方的 **Source code** 是开发工程快照，包含作者内容，与插件安装包不同。SHA-256 校验文件随安装包提供。

插件代码使用 MIT；第三方素材保留各自许可，见包内 `THIRD_PARTY.md`。详细检查和范围见源码 `docs/qa/release_0_3_0/validation.md`。

---

Version 0.3.0 adds whitebox terrain, player 3C presets, vehicle presets and a performance timeline. It also includes viewport measurement, per-instance NPC conversations, task execution feedback, sky thumbnails and Excel workbook conflict handling.

Install **GodotLevelEditor-0.3.0.zip** in Godot 4.7.1 Standard. Copy `addons/godot_level_editor` into your project and enable only **GodotLevelEditor**. Empty projects receive a playable start scene. Preserve `content/` when replacing the addon to update.

The named ZIP excludes authored maps, personal models, workbooks and developer tests. GitHub's automatic **Source code** archives contain the development project. Code is MIT; third-party asset terms are preserved in `THIRD_PARTY.md`. See the release verification record for checks and scope.

[中文 Wiki](https://lanyi021102.github.io/GodotLevelEditor/) · [English Wiki](https://lanyi021102.github.io/GodotLevelEditor/en/)
