# 开发维护索引

本页用于接手功能修改时定位资料与代码。先读工程根 `AGENTS.md`、`README.md` 和 [工具共同规范](../../tools/BLUEPRINT_TOOLCHAIN.md)，再进入对应模块。

## 模块与文件归属

| 模块 | 主要代码位置（相对工程根） | 说明与接口 |
|---|---|---|
| 统一窗口、目录、任务配表与执行服务 | `addons/godot_level_editor/modules/godot_level_editor_suite/` | [README](../../godot_level_editor_suite/README.md) · [INTERFACES](../../godot_level_editor_suite/INTERFACES.md) |
| 关卡、轮盘、白盒、点线面与常驻图 | `addons/godot_level_editor/modules/godot_level_editor/` | [README](../../level_editor/README.md) · [INTERFACES](../../level_editor/INTERFACES.md) · [常驻图](../../level_editor/level_logic_2026-11-15/README.md) |
| 机关素材、组件、图与任务桥 | `addons/godot_level_editor/modules/godot_level_editor_mechanisms/` | [素材与节点](../../mechanism_editor/whitebox_v1/README.md) · [INTERFACES](../../mechanism_editor/INTERFACES.md) |
| 台本、任务图定义与图执行 | `addons/godot_level_editor/modules/godot_level_editor_narrative/` | [README](../../narrative_editor/README.md) · [INTERFACES](../../narrative_editor/INTERFACES.md) |
| NPC / 敌人状态机 | `addons/godot_level_editor/modules/enemy_editor/` | [README](../../enemy_editor/README.md) · [INTERFACES](../../enemy_editor/INTERFACES.md) |
| 天空与关卡环境 | `addons/godot_level_editor/modules/godot_level_editor_sky/` | [README](../../sky_editor/README.md) · [INTERFACES](../../sky_editor/INTERFACES.md) |
| 角色与第三人称操作 | `addons/godot_level_editor/scenes/player.tscn`、`addons/godot_level_editor/scripts/`、`content/scenes/3cplayground.tscn` | [3C Playground](../../3cplayground/README.md) |
| HUD | `addons/godot_level_editor/scenes/hud.tscn`、`addons/godot_level_editor/resources/ui/hud_theme.tres` | [HUD](../../hud/README.md) |
| 米制网格 | `addons/godot_level_editor/scripts/tools/metric_grid.gd` | [米制网格](../../whitebox_grid/README.md) |
| 本 Wiki | `docs/index.md`、`docs/wiki/`、`tools/wiki/`、`mkdocs.yml` | [更新文档](documentation.md) · [预览发布](publishing.md) |

## 资源的唯一来源

| 数据 | 位置与规则 |
|---|---|
| 大世界关卡 | `content/scenes/levels/`；`.tscn` 保存空间、配置和常驻图引用 |
| 房间素材 | `content/scenes/level_editor/rooms/`；保留用户素材 |
| 机关素材 | `addons/godot_level_editor/scenes/mechanisms/`；`.tscn` 与 `.graph.tres` 成对读写 |
| NPC 定义 | `content/resources/enemies/`；首批示例在 `samples_v1/`，[使用指南](../guides/npc-samples.md) |
| NPC 场景与原始素材 | 可放置场景 `addons/godot_level_editor/scenes/npcs/v1_*.tscn`；原模型、许可及导入快照 `addons/godot_level_editor/assets/characters/npc_samples_v1/` |
| 关卡目录 | `content/tables/levels.xlsx`；稳定关卡 ID 和场景路径 |
| 事件与任务 | `content/tables/events.xlsx`；任务仅绑定一个关卡，事件可跨关卡 |
| 台本 | `content/tables/dialogues.xlsx`；当前运行时直接读取 XLSX |
| 任务节点图 | 由任务行 `graph_path` 引用，默认在 `content/resources/task_graphs/` |
| 天空预设 | `content/resources/sky_presets/`；内置模板与自定义预设分开 |
| 光照 V1 基线 | `addons/godot_level_editor/scenes/lighting/cloud_island_v1.tscn` 及对应资源；[保留说明](../../lighting/cloud_island_v1/README.md) |

Wiki 描述这些来源，不维护第二份参数表或图运行数据。组件的 `tl_capture / tl_restore` 只用于状态保存、复位和编辑器操作，不表示时间线功能仍存在。

## 按修改目标查入口

| 修改目标 | 先看这些文件 |
|---|---|
| 改独立窗口导航与保存行为 | `addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd`、`asset_workspace.gd` |
| 改关卡目录或新建关卡 | `addons/godot_level_editor/modules/godot_level_editor_suite/level_warehouse.gd`、`runtime/level_catalog.gd` |
| 改轮盘或实例属性 | `addons/godot_level_editor/modules/godot_level_editor/radial_tool.gd`、`radial_menu.gd`、`entity_inspector.gd` |
| 改常驻图与任务接取 | `addons/godot_level_editor/modules/godot_level_editor/level_logic_panel.gd`、`runtime/level_logic_graph.gd`，以及套件 `runtime/event_director.gd` |
| 增加机关状态或动作 | `addons/godot_level_editor/modules/godot_level_editor_mechanisms/runtime/stateful_component.gd`、`graph/schema.gd`、`editor_panel.gd` |
| 调整单/双开门、状态卡和旋转曲线 | 机关模块 `runtime/rotating_door.gd`、`door_nodes.gd`、`door_curve.gd`；[接口](../../mechanism_editor/INTERFACES.md)、[验证](../../mechanism_editor/doors_v2_2026-11-16/validation.md) |
| 让任务读取机关状态 | 机关模块 `state_access.gd`、`task_nodes.gd`、`task_bridge.gd`、`task_parameters.gd`，及任务执行器 |
| 改工作簿格式 | 套件 `runtime/xlsx.gd`、`runtime/event_catalog.gd`，以及相关模块接口 |

改动公共接口时，记录调用方、兼容影响和验证结果。显示名可修改，稳定对象 ID、任务 ID 与端口 ID 不随名称变化。

## 检查入口

清理历史工程副本或过时说明前，先看 [清理索引](../../cleanup/README.md)。只读盘点命令为 `python3 tools/cleanup/audit_project.py --output /tmp/project-audit.json`；它不会按名称或“无文字引用”自动删除素材。资源校验工具 `tools/cleanup/check_resources.gd` 可在独立副本中反序列化场景／资源并检查依赖，不实例化用户场景。

下面命令在工程根执行，用 `Godot` 表示本机 Godot 可执行文件。macOS 本项目常用 `/Applications/Godot.app/Contents/MacOS/Godot`；Windows 使用安装位置的可执行文件。

```sh
Godot --headless --path . --editor --import --quit
Godot --headless --path . res://tools/mechanisms/whitebox_v1/test_runtime.tscn
Godot --headless --path . res://tools/level_editor/test_level_logic.tscn
Godot --headless --path . res://tools/godot_level_editor_suite/runtime_test.tscn
```

按涉及的模块选择相关测试。编辑器检查、实际渲染检查及历史结果见 [机关验证](../../mechanism_editor/whitebox_v1/validation.md)、[常驻图验证](../../level_editor/level_logic_2026-11-15/validation.md)、[套件说明](../../godot_level_editor_suite/README.md)。这些记录不是当前代码每次运行必然通过的保证。

节点窗口的鼠标操作回归使用 `tools/narrative/run_mouse_editor_checks.py --project <独立副本> --log /tmp/mouse-check.log`；追加 `--npc` 检查 NPC 状态图。macOS 需解锁桌面并允许测试进程取得前台焦点。它实际发送端口拖线和控件输入事件，不把直接调用连线函数的测试算作鼠标检查。步骤、日志及范围见 [连线操作验证](../../narrative_editor/task_toolbar_2026-11-16/validation.md)。

多个聊天并行时先确认文件归属；测试若会写入场景或工作簿，在独立副本中执行。涉及视觉的修改应在 headless 检查之后进行实机渲染检查。

Wiki 自身检查与发布命令见 [预览与发布](publishing.md)。Wiki V1 的交付检查单独记在 [V1 验证记录](validation-v1.md)。QA-01～QA-10 的修复、模块专项、总控独立整合与源码快照见 [2026-11-16 QA 验证记录](../../qa/bugfix_2026-11-16/validation.md)，不要把 V1 的历史通过数当作修复后的整合验收。
