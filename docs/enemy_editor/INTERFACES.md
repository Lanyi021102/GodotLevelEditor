## 插件目录与原生场景合同 · 2026-11-17

插件结构回归修复：内置定义默认只读，个人定义保存到 `content/resources/enemies/`，生成场景默认 `content/scenes/npcs/`，导入模型／依赖输出 `content/assets/characters/npc_imports/`。`definition_store.save_definition(..., allow_builtin=false)` 仅由开发生成器显式放开内置写入；原子保存后刷新规范资源缓存，避免原生场景保存用旧模型引用回写。生成场景的胶囊与 entity profile 按当前身高创建，后续原生碰撞编辑保留。个人目录卡片读取当前身高和模型，而不复用来源样例封面。完整边界及实测见 [结构回归记录](../qa/structure_2026-11-17/validation.md)。

插件本体、示例素材和运行依赖统一到 `addons/godot_level_editor/`；各模块代码在其中的 `modules/`。作者地图、配表与个人资源迁入 `content/`，已有稳定 ID 与 UID 保留；路径迁移表见 `tools/release/layout-migration.json`。

地图采用 Godot 原生文件系统、场景树、保存与 F6，保留轮盘、白盒、点线面和场景对象绑定。“我的关卡”提供原生场景文件的浏览、搜索和打开入口；“关卡编辑”显示当前场景的常驻图。地图仍使用同一份原生场景文件保存。原生保存通过 native_level_registry 登记任务所需 ID，地图路径允许插件目录以外的项目目录。

主插件负责内部模块生命周期和缺省输入／配表初始化；运行服务使用 GLELightZones、GLENoiseBus、GLESaveSystem。用户主场景、已有输入和作者作品不由插件更新覆盖。下面的旧路径和目录入口仅记录当时合同；当前布局与实际验证见 [迁移记录](../cleanup/plugin_2026-11-17/validation.md) 和 [安装指南](../wiki/plugin-install.md)。

# 敌人编辑器：公共接口需求（2026-10-30）

2026-11-16 连线复核：NPC 状态图以窗口鼠标／键盘事件完成端口拖线、撤销重做、搜索添加行为、显示名修改、保存重开，以及第二份定义连线保存，16 项通过；状态 ID 与第一份文件保持。既有画布检查明确载入独立三维夹具后 headless 42 项通过，不再依赖上次打开的场景。未修改 NPC 行为、状态端口或资源格式。见 [连线验证与证据边界](../narrative_editor/task_toolbar_2026-11-16/validation.md)。

## 移除无效能量参数入口 · 2026-11-16

NPC 编辑器“感知”页不再显示已移除玩法的“暴露能量惩罚”；运行角色的 `expose_penalty` 改为仅存储属性，原生检查器同样不显示。`EnemyDefinition.PARAM_DEFAULTS`、参数字典的同名键及已有数值继续保留，旧定义校验、赋值和场景序列化保持兼容，不批量改写 NPC 资源。其他警觉、噪音、求援与巡逻参数继续正常编辑。说明和实测见 [工程清理记录](../cleanup/project_hygiene_2026-11-16/validation.md)。

2026-11-16 示例 NPC V1：`resources/enemies/samples_v1/` 保存13个定义及清单，`scenes/npcs/v1_*.tscn` 为可放置场景；原始素材、许可和导入快照在 `assets/characters/npc_samples_v1/`。定义的 `npc_sample_v1` 元数据保存来源、尺寸、动作清单和缩略图路径；套件目录读取该元数据，支持原模型名搜索及真实缩略图。场景 `editor_display_name` 元数据供素材轮盘读取中文名称，未设置时沿用文件名；没有改变轮盘操作。

appearance 增加 `pose_mode=humanoid_t/rest`，默认值保持旧人形 T Pose，`rest` 只恢复自然绑定姿态；均计入签名、验证和保存。NPC 专属尺寸适配保留模型根的旋转与比例，支持小动物与非1倍源模型；不改玩家的 CharacterModel。骨骼动画只锁定根骨骼的水平位移，保留垂直步态。示例逐场景配置碰撞，初始无敌对转换，Pug／Sheep 无步态时只待机。操作见 [当前指南](../wiki/guides/npc-samples.md)，资源与验证见 [样例记录](samples_v1_2026-11-16/validation.md)。

2026-11-15 模型导入：EnemyDefinition 增加可空 `appearance: Resource`，由 `appearance_data.gd` 保存 PackedScene 模型、骨架路径、匹配外部骨架、可选动画来源／片段和身高。空值保持旧运行表现，schema 与状态端口 ID 不变。`appearance_panel.gd` 的变更进入原面板 UndoRedo 与冲突保存；`npc_visual.gd` 供编辑预览及 GuardAI 共用，无选中动作时关闭自动播放并显示 T Pose／特殊骨架静止姿态。`create_npc_scene(path)` 只生成新场景，不覆盖已有文件；模型资源为标准依赖。操作、匹配限制及验证见 [模型导入](MODEL_IMPORT.md)。本次维护 enemy_editor、guard_ai.gd 适配与本模块测试；沿用其他聊天完成的“我的NPC → NPC编辑”导航。

2026-11-15：套件增加“我的NPC → NPC编辑”，原 EnemyDefinition、保存、撤销与草稿确认继续复用。面板增加 `definition_opened(path)`，仅在 `_load` 成功后发出；`library_actions` 供套件隐藏目录操作，独立模块恢复显示。目录选择不会调用加载；确认切换后以成功载入信号进入编辑页。详见 [套件合同](../godot_level_editor_suite/INTERFACES.md)。

2026-11-13：产品及插件路径改名、五项蓝色导航和原生视口边界以 [当前套件接口](../godot_level_editor_suite/INTERFACES.md) 为准。隐藏的方向占位行已移除，端口对应实际可见行，具名端口与图资源连线保持兼容。

## 统一窗口与节点呈现 · 2026-11-12

专项入口已统一到独立“GodotLevelEditor”窗口；原 EditorPlugin 仅保留模块注册和撤销／调试支持。节点类别只用颜色，隐藏分类文字前缀、方向说明行和空运行状态；端口索引、稳定 ID 和资源版本不变。当前合同与验证见 [套件接口](../godot_level_editor_suite/INTERFACES.md)。此前有关入口和分类前缀的说明为历史记录。


## 白盒转型覆盖说明 · 2026-11-12

当前以个人白盒编辑器为目标。时间暂停、回溯／快进、录像分身、轨迹、能量和能力解锁已删除。此前时间线／分身操作要求仅为历史记录。四套编辑器、定义格式、稳定 ID、连线、组件交互及调试继续保留。组件 tl_capture/tl_restore 供状态保存、复位与编辑器操作使用，不再注册时间线；has_item 只使用角色道具接口，无接口时返回 false。主入口为空白工作区，不接入旧谜题、守卫或剧情。验证见 [转型记录](../cleanup/WHITEBOX_2026-11-12.md)。

1. `EnemyDefinition` Resource：版本、初始状态、状态数组、转换数组、感知参数；不包含实例状态。状态 ID 稳定，显示名称可改。条件只读白名单事实，不执行表达式。
2. `EnemyMachine` RefCounted：每个守卫独立创建；`configure(definition)`、`evaluate(event, facts)`、`capture()`、`restore(data)`。优先级大者先；同优先级按数组顺序；每次事件最多一次转换。
3. `GuardAI.enemy_definition` 可选导出。未赋值使用守卫模板与原有导出参数；显式赋值后以定义参数为准。保留 `State` 枚举、`state`、`state_timer()` 和 `spotted` 信号。
4. `GuardAI.tl_capture/tl_restore` 增加 `enemy_machine` 字典，旧快照缺失此键时使用原有 state/timer；恢复不执行入场副作用，不再次扣能量/呼叫同伴。
5. 运行调试只通过 `EngineDebugger` 的 `godot_level_editor_enemy:state` 通道上传实例路径、定义路径、状态 ID、计时器、最近转换和回溯标记。编辑器不向游戏写状态。实例离场发送 `godot_level_editor_enemy:remove`。
6. 仅修改公共文件 `scripts/stealth/guard_ai.gd`（适配），`project.godot`（启用插件）。不修改 Timeline、场景、关卡生成器、HUD。其余代码位于独立插件/资源/测试/文档目录。

## 按共同蓝图规范补充

- 定义转换增加固定端口 `from_port=state_exit` / `to_port=state_enter`，类型均为状态转换；事件字段与布尔/数值条件分开。布局单独放 `layout.nodes/scroll/zoom`，不参与运行判断。
- `EnemyMachine.capture/restore` 保存 `state_id/timer/last_transition/last_reason`。最近原因包含事件、条件及当时的实际值。单次事件最多一次转换；求援期间防止同一实例同步重入。
- `GuardAI` 新增 `enemy_instance_id: String`、`patrol_route: NodePath` 和 `enemy_runtime_state(): Dictionary`。场景内空/重复 ID 由插件重新分配并将场景标为未保存；运行时程序生成的旧守卫可继续用空 ID，调试以实例路径区分。
- `patrol_route` 指向 Node3D，其直接 Marker3D 子节点按场景顺序作为巡逻点，启动时转为世界坐标；留空则保留原 `patrol_points`。需要其他专项生成路线时只需设置此引用，不改守卫执行器。
- 编辑器从场景选择打开定义；从蓝图定位关联守卫。资源绑定与路点创建使用 Godot 场景撤销历史；纯图编辑使用自己的 UndoRedo。运行前 `_build()` 检查当前场景守卫引用，不触碰其他专项组件。
- 运行调试包含 `instance/instance_id/definition/state_id/timer/last_transition/last_reason/behavior/speed/alert/seen/position/rewound`。游戏只发消息；编辑器不写游戏或正式进度。停止会话/实例离场会清理显示。
- 原 `State` 枚举顺序、`state`、`state_name()`、`state_timer()`、`is_alerted()`、听觉/求援方法及 `spotted` 保留。新增自定义状态通过稳定字符串 ID 表达，旧整数 `state` 对此返回 -1；其他专项应读 `enemy_runtime_state().state_id`。原四状态的整数映射不变。
- 回溯增加 `enemy_machine/saw_target/target_path` 字段；旧字段继续存在。无需修改 Timeline、Rewindable、玩家、存档或 HUD。
- 旧守卫仅保留内部回归夹具：`res://tools/enemy_editor/fixtures/guard_blueprint_sample.tscn`；兼容定义为 `res://addons/enemy_editor/runtime/legacy_guard.tres`，不进入 NPC 素材目录。

## 2026-10-31 · 仅呈现适配

- 新增敌人 `graph/node_presentation.gd`，只读引用机关的色表和纯呈现函数；需总控后续协调共用路径，不改机关运行接口。
- GraphNode 方向行无端口；启用端口位于 slot 1，但输入/输出连接索引仍为 0。`state_enter/state_exit`、类型 0 及资源字段保持不变。
- `debugger.session_pause_changed(session_id, paused)` → `panel.set_session_paused` 是插件内部显示接线，来源于原生调试会话；不改变游戏数据、消息或快照结构。

## 旧 NPC 素材清理 · 2026-11-16

NPC 素材清理后，`resources/enemies/` 只保留新示例及用户自己的定义。旧 `guard_default.tres` 移到 `addons/enemy_editor/runtime/legacy_guard.tres` 供存量场景兼容；重复的 `new_enemy.tres` 删除。角色构造器改用 `addons/enemy_editor/runtime/npc_actor.tscn`。旧守卫样例归入 tools 测试夹具，模型源文件和玩家模型不清理。 验证见 [清理记录](../enemy_editor/legacy_cleanup_2026-11-16/validation.md)。
