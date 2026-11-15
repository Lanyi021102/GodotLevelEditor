# 敌人编辑器：公共接口需求（2026-10-30）

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
- 独立样例：`res://scenes/enemy_editor/guard_blueprint_sample.tscn`；首个定义：`res://resources/enemies/guard_default.tres`。

## 2026-10-31 · 仅呈现适配

- 新增敌人 `graph/node_presentation.gd`，只读引用机关的色表和纯呈现函数；需总控后续协调共用路径，不改机关运行接口。
- GraphNode 方向行无端口；启用端口位于 slot 1，但输入/输出连接索引仍为 0。`state_enter/state_exit`、类型 0 及资源字段保持不变。
- `debugger.session_pause_changed(session_id, paused)` → `panel.set_session_paused` 是插件内部显示接线，来源于原生调试会话；不改变游戏数据、消息或快照结构。
