0.1.1 修复完整插件结构调整后的编辑与保存流程：

- 恢复“我的关卡”浏览真实地图文件，保留 Godot 原生保存、场景树、3D 视口与 F6。
- 修复关卡首次另存为的独立 ID、任务登记、覆盖已登记目标时的索引一致性和保存后的鸟瞰缩略图。
- 内置机关与 NPC 引导另存个人副本；个人 NPC 场景、模型和贴图保存在插件目录外，生成的碰撞匹配角色身高。
- 修复机关浏览／保存后的草稿状态，以及继承天空读取、保存后引用刷新和 HDRI 取消后重试。

下载 **GodotLevelEditor-0.1.1.zip** 安装插件。下方的 Source code 是开发工程快照，包含开发者地图，并非插件安装包。

需要 Godot 4.7.1 标准版。将 ZIP 内 `addons/godot_level_editor` 放入自己的 Godot 工程，等待导入后，在项目设置的插件页启用 **GodotLevelEditor**。

包含关卡、机关、NPC、台本、任务、天空编辑器，五种机关和13个 NPC 素材，以及角色、第三人称镜头、HUD 和光照。没有预装地图；新建地图及配表存放在 `content/`。

更新时关闭 Godot，替换插件目录并保留作品目录。内置素材修改前请先另存到作品目录。SHA-256 校验文件与安装说明随包提供。

本版验证包含隔离开发工程和插件空工程中的编辑、保存重开及真实 F6 流程，以及安装、更新和默认 F5 试玩。详细范围与已知引擎日志见源码内 `docs/qa/structure_2026-11-17/validation.md`。本版没有重做 Windows／移动导出验收。

验收限制：新任务夹具的渲染 F6 合成输入未完成稳定验收，未计为通过；对应 headless 完整链及原有 47 节点 F6 已通过。物理鼠标验收与事件注入检查分开记录。

Version 0.1.1 restores native map browsing and fixes Save As identities, personal asset persistence, mechanism draft state and inherited sky/HDRI workflows. Install the named addon ZIP, preserve your `content/` folder when updating, and use Godot 4.7.1. The automatic Source code archives are development snapshots, not addon installation packages.

源码使用 MIT 许可；第三方角色和动画保留各自的 CC0 许可。

[在线操作指南](https://lanyi021102.github.io/GodotLevelEditor/)
