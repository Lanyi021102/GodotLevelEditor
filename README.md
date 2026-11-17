# GodotLevelEditor

Godot 4.7.1 编辑器插件。包含关卡轮盘、白盒与点线面辅助、机关、NPC、台本、任务、天空编辑器，以及角色、第三人称镜头、HUD 和基础试玩。地图使用 Godot 原生场景树、3D 视口、场景文件、保存和 F6 运行。

## 安装插件

在 [Releases](https://github.com/Lanyi021102/GodotLevelEditor/releases) 下载 `GodotLevelEditor-版本号.zip`，将其中的 `addons/godot_level_editor` 放入自己的 Godot 工程。等待导入后，在“项目设置 → 插件”启用 **GodotLevelEditor**。只需启用这一项；内部模块由它管理。

安装包包含五种独立机关、13 个示例 NPC、模型动画、光照和运行组件，不包含作者地图、个人任务／对白及开发验证资料。GitHub 自动生成的 Source code 是开发工程快照，其中可以包含作者地图；它与插件安装 ZIP 不同。

空工程首次启用会建立起始场景；直接按 F5 或点播放即可操控默认角色。已有工程主场景保留。

完整步骤见 [插件安装与更新](docs/wiki/plugin-install.md)。

## 打开开发工程

使用 Godot 项目管理器打开根目录 `project.godot`；macOS 也可双击 `启动项目.command`。F5 运行主场景，F6 运行当前关卡。独立编辑窗口由顶部 GodotLevelEditor 或“项目 → 工具 → 打开 GodotLevelEditor”打开。

```text
addons/godot_level_editor/   插件本体、内置素材、空白模板、运行组件
content/                    作者作品：地图、配表、任务图和个人素材
project.godot               普通 Godot 工程设置
icon.svg                    开发工程图标
docs/                       Wiki、接口和验证记录
tools/                      开发检查、自动打包及 Wiki 工具
.github/workflows/          GitHub 自动构建与发布
```

只有 `addons/godot_level_editor/` 进入插件 ZIP。GitHub 源码与本地使用同一插件目录结构，无需发布时搬运或改写资源路径。

## 新建与编辑地图

在 Godot 文件系统中找到 `addons/godot_level_editor/templates/empty_level.tscn`，右键选择“新建继承场景”，使用 Godot“场景 → 另存为”保存到 `content/scenes/levels/`，或工程中其他自选目录。不要直接覆盖插件内置模板。

使用原生场景树与 3D 视口编辑。工具栏“呼出轮盘”、白盒、点线面和步长继续可用。使用 Godot 原生保存、复制和 F6 试玩；独立窗口的“关卡”页只编辑当前场景的常驻逻辑，不再提供“我的关卡”卡片目录或地图删除入口。首次保存关卡时登记稳定 ID，供任务选择所属关卡。

默认作品入口是 `content/scenes/main.tscn`。地图在 `content/scenes/levels/`，配表在 `content/tables/`，任务图在 `content/resources/task_graphs/`。迁移保留已有关卡、任务、对象 ID 与资源 UID。

WASD 移动，Shift 跑步，空格跳跃，F 交互；鼠标转动镜头，右键拉近，V 换肩，中键回正。Esc 释放鼠标，点击游戏画面恢复操作。基础试玩不保存长期进度。

## 发布和许可

推送 `plugin-vX.Y.Z` 标签后，GitHub Actions 自动打包、在空工程验证安装／更新／试玩，再创建 Release 并附上 ZIP 与 SHA-256 校验文件。普通源码推送不会创建 Release。也可在 Actions 手动试打包，仅生成构建产物。见 [插件构建与发布](docs/wiki/development/plugin-release.md)。

原创代码采用 [MIT](LICENSE)，第三方 Quaternius 角色与动画保留各自 CC0 许可及来源证据。详见插件内 `THIRD_PARTY.md`。

[在线 Wiki](https://lanyi021102.github.io/GodotLevelEditor/) · [功能地图](docs/wiki/features.md) · [迁移与验证](docs/cleanup/plugin_2026-11-17/validation.md)
