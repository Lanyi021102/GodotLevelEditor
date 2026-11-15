# 机关专项接口（v1，2026-10-30）

## 命名状态与首批素材 · 2026-11-16

新增 `runtime/stateful_component.gd`，七种组件共用 `state_names/requestable_states/action_names/get_state`、`request_state/perform_action/set_property_value`、`state_changed(previous,current)`、`action_finished(action,success)`、`interacted` 和感应区域事件。状态请求的返回仅表示接受；门与升降台到位后才进入稳定目标状态并发出动作完成。中途反向／停止报告原动作取消。属性使用白名单，自定义状态转换 from/action/to 在保存时校验。

Assembly 增加关卡对象 `object_id` 和可选 `primary_component`，`output_component()` 提供主要组件；旧图、端口及版本 1 保持。原有 `instance_id` 和局部组件 ID 保留。场景轮盘按已有机制刷新实例标识；任务通过 `关卡对象引用::局部组件ID` 分别定位组合里的组件，显示名不参与引用。旧组件保持原接口，新素材采用新组件，不重写用户旧场景。

机关图增加 20 种节点（含七种组件）；组件信号转为有界、按帧处理的事件队列，状态变化不会每帧重复触发。`tl_capture/tl_restore` 保存组件状态、运动进度、目标、计时及队列，恢复时不重发事件；仅用于保存、复位与编辑操作。

`state_access.gd` 解析实例和组件；`task_nodes.gd` 提供 11 种任务／常驻图节点；`task_bridge.gd` 将组件信号统一交给 event_director._broadcast。动作和条件经过现有 task_actions，常驻图和任务图复用同一桥。`task_parameters.gd` 为两个图提供实例、状态、动作下拉选择，`validate_bindings` 在保存前检查实际引用。等待节点使用既有 runner 异步等待及检查点状态，不阻塞引擎。

素材、独立示例、文件归属与验证见 [首批机关说明](whitebox_v1/README.md) 和 [验证记录](whitebox_v1/validation.md)。

2026-11-15：套件增加“我的机关 → 机关编辑”，复用本模块原面板与 Store；`library_actions` 仅供套件隐藏目录操作按钮，独立入口保留。目录只收录可编辑的 Assembly 组合，组件源仍在关卡素材库使用。具体导航、保存冲突处理与验证见 [套件合同](../godot_level_editor_suite/INTERFACES.md)。

2026-11-13：产品及插件路径改名、五项蓝色导航和原生视口边界以 [当前套件接口](../godot_level_editor_suite/INTERFACES.md) 为准。隐藏的方向占位行已移除，端口对应实际可见行，具名端口与图资源连线保持兼容。

## 统一窗口与节点呈现 · 2026-11-12

专项入口已统一到独立“GodotLevelEditor”窗口；原 EditorPlugin 仅保留模块注册和撤销／调试支持。节点类别只用颜色，隐藏分类文字前缀、方向说明行和空运行状态；端口索引、稳定 ID 和资源版本不变。当前合同与验证见 [套件接口](../godot_level_editor_suite/INTERFACES.md)。此前有关入口和分类前缀的说明为历史记录。


## 白盒转型覆盖说明 · 2026-11-12

当前以个人白盒编辑器为目标。时间暂停、回溯／快进、录像分身、轨迹、能量和能力解锁已删除。此前时间线／分身操作要求仅为历史记录。四套编辑器、定义格式、稳定 ID、连线、组件交互及调试继续保留。组件 tl_capture/tl_restore 供状态保存、复位与编辑器操作使用，不再注册时间线；has_item 只使用角色道具接口，无接口时返回 false。主入口为空白工作区，不接入旧谜题、守卫或剧情。验证见 [转型记录](../cleanup/WHITEBOX_2026-11-12.md)。

## 米制网格可选表现 · 2026-11-02

`PowerDoor` 与 `runtime/lever.gd` 新增 `use_metric_grid: bool = false`，3C Playground 显式开启。开启后共用 `scripts/tools/metric_grid.gd` 的 1 / 0.5 / 0.1 m 网格，继续响应颜色参数、开合、供电及无副作用快照恢复；编辑器切换开关会重建表现。没有更改图资源版本、交互、连线、碰撞或快照字段。其余已有机关资源维持原参数。验证见 [材质专项](../whitebox_grid/README.md)。

遵循 [蓝图工具链规范](../tools/BLUEPRINT_TOOLCHAIN.md)。本专项不改玩家、Timeline、SaveSystem 与正式关卡组装。

## 资源与实例

- 插件：`res://addons/godot_level_editor_mechanisms/plugin.cfg`；主工作区“机关蓝图”。
- `runtime/assembly.gd` 是独立 `.tscn` 根节点；`definition` 引用同名 `.graph.tres`（格式版本 1）。
- `.tscn` 只维护组件参数、变换、对象 ID；`.tres` 维护图节点、具名端口、连线、节点参数及排版。运行状态不写回定义。
- 图节点 `id`、端口名称、组件 `object_id` 为稳定引用；显示名、节点名和画布位置不参与引用。
- 完整对象引用为 `(assembly.instance_id, object_id)`。关卡编辑器复制/摆放独立组合时须分配新的 `instance_id`；局部 object_id 保留，以复用同一图定义。机关画布复制组件节点会同时复制三维对象，分配新的 node ID 与 object_id。
- 同一组合内 object_id 重复会验证失败；Godot 原生复制场景对象后需要重新绑定。推荐从机关图复制。
- `Factory.component(kind, id)` 创建 `lever` / `plate` / `door`；`Factory.sample()` 创建标准 AND 样例。
- `Store.validate(root)`、`Store.save_pair(root, path)`、`Store.load_pair(path)` 用于验证与成对读写。保存使用旧文件备份，写入失败回滚；不支持的版本拒绝保存/载入。

## 玩家与回放（交总控接入）

- 拉杆加入 `godot_level_editor_interactable` 组；`can_interact(actor: Node3D)` 检查 enabled、一次性状态、可见性与世界距离；`interact(actor)` 返回是否成功。
- `interact(null)` 用于明确的脚本驱动和隔离预览；玩家与回放应传实际角色，不以 null 绕过距离检查。
- 成功主动交互发出 `interacted(object_id, "interact", actor)`。总控在玩家输入日志记录组合实例 ID、对象 ID、动作与物理帧；回放重新解析对象并调用同一接口。
- `is_powered()` 读取布尔状态；拉杆/门提供 `power_changed(bool)`。图执行器轮询状态，不依赖恢复时重发事件。
- 能量、动画与交互按键由宿主负责；本组件不扣能量、不监听全局输入。成功与扣能量的原子顺序由总控协调。

## 图执行与回溯

- `assembly.configure()` 收集局部绑定并验证；`step()` 只推进一个 60 Hz 逻辑帧；默认由 `_physics_process` 调用，优先级 -10。
- 连续数据按拓扑排序求值，同级按稳定 node ID 排序；门在后续自身物理更新推进碰撞和外观。事件相位在数据相位之后，因此事件修改源状态于下一逻辑帧影响门。
- 端口：BOOL / NUMBER / OBJECT / EVENT。上升沿是显式 BOOL→EVENT 转换；延迟是至少下一帧的有状态推进。每帧事件预算 64，待处理上限 256；组合逻辑循环拒绝。
- 图内门每帧先撤销旧目标再求值，断线或配置错误不会遗留开门命令。图内门的旧 `source_paths/power_nodes` 应为空。
- `assembly.tl_capture()/tl_restore(state)` 覆盖帧号、前值、待处理事件、调试状态和各对象状态；包括拉杆计时、一次性状态、压力板延时、门开合比例。恢复不重执行主动交互。
- 总控应只注册组合根的快照，避免又给子组件重复注册；冻结、分身回放及存档策略沿用公共时间线。可用现有委托型回退适配器，但应由总控确认冻结归属后接入。
- 需单独保存永久解锁等世界进度，本版不把房间机关状态写进正式 SaveSystem。

## 兼容与调试

- `runtime/door.gd` 继承既有 `PowerDoor`，保留 `add_power_source`、`source_paths`、`is_open`、`tl_capture/tl_restore` 等接口。新门以地面为固定原点；旧 PowerDoor 仍按原逻辑移动根节点。
- 公共变更仅 `scripts/world/power_door.gd`：支持工具模式、可重复构建几何、编辑器中不运行供电物理更新。压力板运行逻辑直接委托原 `PressurePlate`。
- 调试消息 `godot_level_editor_mechanism:state/remove` 由独立 EditorDebuggerPlugin 接收。运行实例按编辑器会话与实际场景路径区分，包带 definition_id；UI 按 definition_id 与图资源路径校验其与当前图对应。隔离预览明确使用场景副本。
- 关卡编辑器按 `.tscn` 实例摆放，图的局部绑定不依赖外部 NodePath；跨组合、关卡事件或敌人事件的桥接留给总控协调。

## 后续

2026-11-16 轮盘实例：关卡中新增机关可先放占位体，在原生检查器选择 `component_scene`，继续复用既有 placement 组件装配合同。模型与存在范围存于实例 metadata，不改机关源文件及图内 ID；常驻／任务机关共用 `EntityProperties`，任务未激活或结束时关闭实例显示、处理与碰撞。详见 [轮盘 V2](../level_editor/quick_add_v2_2026-11-15/README.md)。

草丛（隐蔽状态/检测体）和梯子（接驳点/攀爬能力）尚未实现；待对应运行组件接口明确后注册节点类型，不在图执行器内实现角色能力。

## 总控 3C 接口更新 · 2026-11-02

共享玩家与会话已切换到 WASD/Shift/空格、Q/E 浏览后暂停、T 继续、R 固定录像分身、F 主动交互。允许回到分身生成前，已有录像不被改写。HUD 仅保留暂停按钮，能量玩法移除。组合的 can_interact/interact 与无副作用快照接口不变，玩家/分身实际接入交互记录及回放。具体合同和验证见 [3C Playground](../3cplayground/README.md)。本次未修改编辑器实现或用户关卡与机关资源。
