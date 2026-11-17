## 插件目录与原生场景合同 · 2026-11-17

插件本体、示例素材和运行依赖统一到 `addons/godot_level_editor/`；各模块代码在其中的 `modules/`。作者地图、配表与个人资源迁入 `content/`，已有稳定 ID 与 UID 保留；路径迁移表见 `tools/release/layout-migration.json`。

地图采用 Godot 原生文件系统、场景树、保存与 F6，保留轮盘、白盒、点线面和场景对象绑定。“我的关卡”提供原生场景文件的浏览、搜索和打开入口；“关卡编辑”显示当前场景的常驻图。地图仍使用同一份原生场景文件保存。原生保存通过 native_level_registry 登记任务所需 ID，地图路径允许插件目录以外的项目目录。

主插件负责内部模块生命周期和缺省输入／配表初始化；运行服务使用 GLELightZones、GLENoiseBus、GLESaveSystem。用户主场景、已有输入和作者作品不由插件更新覆盖。下面的旧路径和目录入口仅记录当时合同；当前布局与实际验证见 [迁移记录](../cleanup/plugin_2026-11-17/validation.md) 和 [安装指南](../wiki/plugin-install.md)。

# 机关专项接口（v1，2026-10-30）

2026-11-16 连线复核：自动检查和窗口鼠标检查分开记录，不能用直接发送连接信号的测试代替鼠标操作。关卡与机关的完整窗口复测 55 项通过，覆盖布尔／事件／数值／对象引用拖线、必填输入与错类型校验、改参、撤销重做、保存重开及切回图；参数滚动区、校验规则与图格式保持。见 [本轮证据及边界](../narrative_editor/task_toolbar_2026-11-16/validation.md)。

## 当前素材范围：五种独立机关 · 2026-11-16

用户确认库中只保留双开门、单开门、压力板、按钮、升降台，当前内置源位于 `addons/godot_level_editor/scenes/mechanisms/{double_door,single_door,pressure_plate,button,lift_platform}.tscn` 及同名图；个人版本保存在 `content/scenes/mechanisms/`。组合、拉杆、终端、旧门、重复默认样例及其预览/演示任务已移除。下方首批七种、预连线组合和可搜索旧创建类型的描述是阶段历史，以本节为准。

每种素材只绑定自身一个物理组件。按钮按下和复位不会改变其他机关；门使用自己的交互→旋转动画；压力板只输出占位状态；升降台自己的交互执行往返。升降台距离检查和文字提示跟随移动平台，乘客到顶后可再次交互返回。

`Schema.COMPONENT_KINDS` 为五种创建类型；`COMPATIBILITY_KINDS` 只供旧关卡数据加载，不能通过搜索或 `add_kind` 新增。通用状态、事件、逻辑与任务接口保留。`Factory.blank()` 是新建入口，得到空白图；`Factory.standalone(kind)` 创建独立组件；`Factory.sample()` 仅作为工具兼容测试的内存夹具，不再生成用户库预设。

清理前先校验工程外备份。旧展示区改为五种独立素材；TestLevel 保留原组合的父变换并改为三个独立实例；黄昏山居的两份旧门读取图内嵌到关卡，保留对象、组件 ID 和任务引用。剧情交互点移到 `scenes/narrative/interaction_point.tscn`，不属于机关素材库。

操作见 [独立机关](../wiki/tutorials/button-door.md)，删除清单、依赖迁移和实际检查见 [本轮记录](independent_2026-11-16/validation.md)。

2026-11-17 在迁移后的插件结构中独立复测，目录仍为五种，运行、无交叉控制、选择联动、空白新建及保存重开保持。原始素材与作者 `content/` 共 79 个文件散列未变。见 [迁移后复核](independent_2026-11-17/validation.md)。

## 双规格旋转门与可视节点 · 2026-11-16

新建门使用 `single_door`（外框 2×3 m）/ `double_door`（外框 4×3 m），组件为 `runtime/rotating_door.gd`，素材为 `scenes/mechanisms/{single_door,double_door}.tscn` 及同名外部图。固定门框与铰链上的 `AnimatableBody3D` 门扇分离；单扇 +90°，双扇分别 +90° / −90°。默认米制网格；既有门和用户图不自动转换或删除。

状态严格为 `close / moving / open`，只允许请求稳定目标 `close / open`；动作 `open / close / toggle`。物理帧推进归一化时间，`motion_curve:Curve` 映射到 0°～90°；反向从当前进度沿同一曲线返回，到位后才完成。曲线固定起终点 (0,0)/(1,1)，缺失或无效曲线拒绝保存。`motion_seconds` 是完整单程时长。

组件继续提供公共命名状态、交互、动作、属性、完成信号与静默快照接口。主动交互产生输入事件，由图的交互→动画线执行旋转；任务直接调用 `request_state/perform_action`。锁定阻止主动交互和打开，允许关闭。`motion_info()` 提供 state/progress/angle/target/seconds/leaves，供隔离预览与调试包读取。

新增 `single_door/double_door` 门框对象节点、`door_leaf`、`door_animation`、`door_state`。金色 OBJECT 线固定表达同一对象的门框→门扇→动画→状态，错接其他门或其他节点类型拒绝保存。动画有事件输入及已接受/失败/实际到位输出；三状态卡分别输出当前 BOOL 和一次 entered EVENT。新端口仍使用稳定具名 ID 与图格式 1。

`door_blueprint.gd` 是七节点模板的共同来源；素材生成与面板添加复用同一构建器。通过 + 节点添加单/双开门时同时创建组件与完整图，分配新 ID，置于原图右侧，一次原生撤销可以整体移除。

`door_curve.gd` 在图节点内编辑真实组件 Curve；点编辑、时长与预设使用原生场景撤销；起终点锁定。曲线存于组件场景，图只存对象绑定、动作、状态与排版，多个节点不复制一份曲线。`door_nodes.gd` 展示门框/门扇参数、状态、角度及播放位置；对象值高亮先检查类型，避免将 OBJECT 字符串与 BOOL 直接比较。

操作、实际截图与验证见 [旋转门教程](../wiki/tutorials/rotating-door.md) 和 [专项验证](doors_v2_2026-11-16/validation.md)。这次门规格工作独立于上一节四项 QA 的冻结验收。

## 内置素材与个人作品保存 · 2026-11-17

`save_policy.gd` 统一识别插件路径；先归一化 `..`，保护判断忽略大小写，避免 macOS 的 `ADDONS` 路径绕过。面板、原生机关场景与图资源保存均保护 `res://addons/`。内置素材点击保存会提供 `content/scenes/mechanisms/` 下未占用的场景／同名图路径，已有个人资源不会被默认文件名覆盖。

`Store.save_pair(root, path, allow_builtin=false)` 默认拒绝插件目录；只有开发生成器显式传 `true` 才可生成内置素材。现有非插件项目路径的配对保存合同保持，不重命名用户资源或改变稳定 ID。

个人版本写盘成功后，面板从未改写的磁盘数据重载源标签，再打开个人副本的真实原生标签，避免源草稿误留为未保存。原生 Save As 被拒绝时恢复根节点的原场景路径和未保存状态；成功另存后清除该草稿的旧拒绝提示。拒绝仍以“已处理但不写盘”返回，不能仅凭 Godot 保存 API 的 OK 判断成功。

图自动居中、窗口布局和标签恢复不再通过滚动通知修改定义或标记脏状态。用户平移、缩放、滚动条和“适应图”继续记录视图；节点、参数、曲线与原生撤销合同保持。

开发副本与插件空工程的完整编辑／另存／重开／原生关卡 F6、插件替换和内容散列验证见 [迁移流程验证](structure_2026-11-17/validation.md)。当前中文名称未增加装饰性前缀。

## QA 保存、剪贴板与自定义动作合同 · 2026-11-16

本轮合同对应 QA-01、QA-05、QA-07、QA-08；模块专项与总控独立整合检查已通过，具体来源、早期失败记录和源码快照见 [本轮 QA 记录](../qa/bugfix_2026-11-16/validation.md)。

- `native_save_guard.gd` 在插件启用时注册为优先 `ResourceFormatSaver`，与 `Store.save_pair` 共用场景／图的冲突保护。原生保存也先校验图、组件与配对磁盘变化，成功后更新外部图引用与跟踪散列；拒绝时保留文件、草稿和未保存状态。
- 文件系统扫描可能重建 saver 注册顺序；自动注册后延迟恢复 guard 优先级，`_apply_changes()` 在原生保存前同步再次确保顺序。该钩子用于安排 saver 顺序，不承担否决写入；实际拒绝仍由 guard 处理。
- Godot 保存回调不能直接否决后续 saver；拒绝写盘的分支会以已处理返回，避免内置 saver 继续覆盖。调用方不能仅凭 `EditorInterface.save_scene()` 返回 OK 判断成功，需要查看机关面板状态、`dirty` 与实际配对文件。`.tscn` 是机关成对保存的场景格式。
- 剪贴板存复制时的节点参数、内部边、位置及绑定对象的 PackedScene 快照，粘贴不再回读源节点 ID。粘贴为新节点与局部对象 ID，同一次粘贴中共享的原绑定映射到同一新组件；原件后续修改或删除不使快照失效，图内引用与空间对象一同撤销重做。
- 纯自定义动作只有匹配当前 `from`（或 `*`）的规则才执行；没有匹配且不是组件内置动作时返回 `{ok:false, reason}`，不得落入内置字典、误报成功或发出完成事件。内置动作的现有语义保留。
- 按钮进入 `pressed` 的正常状态转换统一设置 `reset_after` 计时，包括自定义 `interact`；离开时清除计时。`tl_restore` 直接恢复保存的剩余计时与状态，不调用正常转换入口，不重放交互、状态或动作事件。

2026-11-16 选择联动修复：原生三维选择通知可能在 `_syncing` 释放后到达；若当前图节点已经绑定到该对象，`scene_selection_changed` 保留当前节点及参数面板。多个状态／动作节点引用同一组件时不再跳到第一个组件节点；三维选择不同组件仍按原逻辑定位。资源格式、绑定与图数据不变。验证见 [选择联动回归](selection_fix_2026-11-16/validation.md)。

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
