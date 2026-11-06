# 关卡专项接口 v1 · 2026-10-30

## 米制网格呈现 · 2026-11-02

白盒默认表现改用 `resources/materials/whitebox_metric_grid.tres` 的共享着色器及独立底色副本，通过 `scripts/tools/metric_grid.gd` 创建。1 / 0.5 / 0.1 m 刻度按世界空间计算，不依赖 UV；平面使用真实单位切向，曲面使用三向混合投影。`tint`、`visual_scene`、碰撞、推拉数据和场景持久化合同保持兼容。指定 `visual_scene` 时保留模型材质。曲面投影边界与验证见 [材质说明](../whitebox_grid/README.md)。

## v0.4 呈现统一 · 2026-10-31

- 仅在 `node_presentation.gd` 维护关卡节点职责分类，直接复用 `addons/branch_mechanisms/graph/node_presentation.gd` 的颜色、节点样式、方向行、端口行及活动边框。未改机关专项文件。
- 持续读取 `source/read_state/player_state` 与记忆 `latch` 属于状态；`goal` 输出一次完成事件，属于触发；`emit_event` 下一帧投递，属于延迟／流程。该映射仅用于标题、筛选和图例，不改 `level_graph.gd` 的定义或节点 kind。
- 方向标识行不启用端口；实际槽位行从 `i` 移到 `i+1`，启用端口的连接索引、顺序、类型和颜色完全不变。保留节点／端口 ID、连线数据、版本 1 资源格式以及运行执行器。
- 活动样式读取现有值、执行计数和原因；事件计数增加时短暂提示，回溯清除过时提示。调试器的暂停／继续仅更新编辑器显示；不写运行实例，也不新增运行消息字段。`Runtime` 标签路径保持兼容。
- **交总控协调**：若将机关呈现工具移至公共目录，需要保留 `apply/direction_row/port_row/show_runtime`、分类色常量及活动样式元数据的兼容接口。当前采用只读复用与本专项适配，不修改公共规范或其他编辑器。

## v0.3 推拉扩展 · 2026-10-31

- 白盒增加仅存储的 `mesh_edit`：`{version: 1, signature, vertices: PackedVector3Array}`。顶点相对 `size` 归一化；`.tscn` 是唯一持久化来源。旧白盒没有该字段时继续程序化生成。
- 共边、共面三角形组成可选表面；沿真实世界法线按 0.1 位移，共用顶点一起更新。尺寸和中心重新计算，其他顶点的世界位置保持不变。拒绝相邻面退化、翻转和局部尺寸小于 0.1 的操作；不提供任意布尔切割或自交检测。
- `apply_face_state({size, transform, mesh_edit})` 原子用于编辑器撤销重做；碰撞从同一编辑网格生成。更改形状类型、阶数等生成参数会临时使用该参数的生成形状；撤销参数后恢复匹配的推拉数据，`size` 仍可继续缩放。
- `native_snap.gd` 通过 Godot 4.7 原生吸附对话框设置平移步长 0.1 并开启吸附；根据原生控件单位和图标定位，不依赖界面语言，设置后用 `EditorInterface` 实际值校验。公共运行时玩家、Timeline、存档和事件接口不变。

本专项只新增 `addons/branch_level_editor`、`scenes/level_editor`、`resources/level_editor`、`tools/level_editor` 与本文档目录；公共文件仅追加 `project.godot` 插件启用项，保留其他插件和默认入口。运行场景遵循当前清理基线。

| 对象 | 接口与含义 |
|---|---|
| 世界根 `runtime/world.gd` | `topology`、`events` 引用两张 `BranchLevelGraph`；`world_id`、`start_room_id` 为稳定 ID |
| 房间根 `runtime/room.gd` | `room_id` 为实例作用域，`display_name` 可改；局部 `object_id` 不依赖节点名 |
| 空间接驳点 | 本地 -Z 指向房间外；每条图边连接两个接驳点，允许双向连续穿行；未连接的接口保持封闭 |
| 区域目标 | `controlled_actor()` 只接受 `branch_player` 组且 `is_clone()` 不为 true 的角色；角色碰撞层为 2 |
| 组件锚点 | `component_scene` 可实例化独立机关组合/敌人场景；`component_definition` 传入守卫 `enemy_definition`；`component_output_path` 选择组合内部的读取端点 |
| 机关读取端点 | `is_powered() -> bool` 或 `is_open() -> bool`；只读查询，不绕过机关图改变门状态 |
| 白盒块 | `size` 控制碰撞体，`visual_scene` 可替换表现；模型应只包含表现节点，布局和逻辑继续复用 |

`.tscn` 保存布局、参数、实例及图引用；`.tres` 保存图定义、具名端口、节点 ID 和连线。排版位于 `positions/view_scroll/view_zoom`。资源版本为 1；未知版本拒绝运行与保存。执行器使用私有定义副本，状态不写回共用资源。

图节点：`port`；`source`、`constant`、`number`、`greater`、`object`、`read_state`、`all`；`goal`、`latch`、`unlock`、`objective`、`checkpoint`。事件与布尔状态之间必须通过 `latch` 显式转换。无输入的数据端口使用 false/0/空引用；未连接的目标不完成。没有 unlock 控制器的空间边为开放通路；有控制器而无输入时锁定。

节点/边用稳定 ID，端口用固定名称。拓扑边每个端点仅允许一个连接；数据输入仅允许一个来源。校验版本、重复 ID、端口类型、悬空引用、图循环、对象绑定、孤立房间和三维接口对齐。首版不支持隐式反馈循环，也不宣称能证明任意新谜题可解。

## 总控接入

- `component_available(object_id, component)` 在世界装配完成后逐个发出；连接信号应在世界进入场景树之前。也可读取 `runtime_components() -> Dictionary`，键为 `room_id/object_id`。
- `room_entered(from_room, to_room, actor)` 是实际跨过空间接口中心的方向通知，不传送玩家、不切场景、不操作相机。
- `goal_completed(goal_node_id)`、`objective_changed(text)`、`progress_requested(progress)` 由图连线真实触发；保存请求在当前事件批次清空后发出。
- `capture_progress()` 返回 `{schema_version: 1, world_id, graph_id, states}`。`restore_progress(data) -> bool` 检查作用域、版本、节点与布尔值，原子恢复，不再次执行奖励/目标/保存事件。正式文件写入由总控负责。
- goal/latch 的 `persistent=true` 为世界持续进度；`persistent=false` 为可回溯房间逻辑。`tl_capture/tl_restore` 覆盖局部状态、待处理事件、帧号、最近原因及未发出的保存请求，不回退永久进度，不重放入场副作用。
- 总控给运行组件接现有委托型回退适配器，世界根也需登记。组件状态先恢复，再恢复世界图。插件不主动登记 Timeline、不操作 SaveSystem、不创建正式玩家。复用旧守卫场景时去掉其自动登记适配器，避免重复注册。
- 物理帧执行：机关/守卫按自身规则推进，世界事件图优先级 500，现有 Timeline 在 1000 捕获。同级节点及事件扇出按稳定 ID 排序；事件每帧预算 64，余项留至下一帧。冻结和恢复的归属由总控协调。

## 跨专项兼容

- 兼容 [机关接口](../mechanism_editor/INTERFACES.md) 的独立 `.tscn` 组合；锚点实例化时按 `world_id/room_id/object_id` 分配组合 `instance_id`，保留组合内局部 ID。总控只登记组合根快照。
- 守卫沿用 [敌人接口](../enemy_editor/INTERFACES.md)：定义资源、状态机、`spotted`、快照接口不变；锚点设置有作用域的 `enemy_instance_id`，将 `patrol_local` 转为世界坐标。
- 首版三房保留已有 PressurePlate/KineticPlate/Breaker/PowerDoor 接口和局部 `source_ids` 兼容装配。赋予 `component_scene` 时不再追加这些旧连线，也不覆盖组合内组件参数；后续由总控协调替换成已验收的机关图预制组合。
- `placeholder` 没有场景时仅保留接口占位，不提供虚假通电/攀爬等行为。玩家、草丛和梯子等缺失能力用 `placeholder_contract` 写明条件与待实现接口；`world.warnings()` 可列出。
- 旧电闸离场时关闭自己的动态暗区；LightZones 尚无单项注销接口，反复加载的区域槽回收交总控协调。
- 调试使用只读 `branch_level:state/remove` 通道。包包含编辑器会话、实例路径、世界/图 ID、语义摘要、实际值与最近原因；同一定义的多个实例分开显示，运行不接受编辑器写状态。

## v0.2 适配 · 2026-10-30

- 仍使用格式版本 1，新增预制节点类型；旧节点/端口 ID 与四房世界继续兼容。中文名称只影响显示，不作为引用。
- 白盒新增 `shape_kind/steps/step_height/thickness/curve_angle/skew`。`size` 初始为 1，尺寸按 0.1 量化，最小 0.1；编辑器原生缩放也以 0.1 量化，支持非等比正缩放。旧场景通过既有 `size` 保存布局。门洞/窗洞/管道使用真实三角碰撞；形状网格与碰撞由同一生成器产生。单个定高楼梯最多 64 级。
- `palette_assets/*.tscn` 是原生拖放预设，数据协议 `type=files`；拖放预览、落点与撤销采用 Godot 的原生场景拖放。实例在进树时分配空缺的稳定 ID，不修改共用预设。Room 编辑器表现使用线框，避免把检测体误作放置表面。
- Room 增加 `player_entered(room_id, actor)` / `player_exited(room_id, actor)`。检测范围为局部 X/Z 各半宽、Y 从 0 到 `bounds_size.y`；排除分身，仅检测 `branch_player`、角色碰撞层 2。接驳点的旧 `room_entered(from,to,actor)` 仍表示跨接口方向，二者语义分开。
- 区域增加 `player_entered(actor)` / `player_exited(actor)`。世界事件图用稳定 Room ID 或 `room_id/object_id` 绑定；世界根直接摆放的物件位于 `$world/object_id` 作用域。
- `world.publish_event(key, actor=null)` 向图发送具名事件；`emit_event` → `event_received` 在下一物理帧送达。事件与操作可分支，不执行任意表达式或任意方法名。每帧执行 64 个事件，输入/待执行队列各限制 256 项；快照增加输入队列、启动标记、执行计数和事件上下文。
- 新操作桥位于 `runtime/level_actions.gd`。开关调用既有 `set_powered(bool)`；压力板仍由真实占位驱动。守卫优先调用可选 `level_start_patrol()`，否则通过现有 GuardAI 的公开快照接口恢复原巡逻状态后启用处理，不改敌人定义或共享状态机。
- 玩家接口：`level_kill(reason) -> bool`、`level_test_state(state) -> bool`、`level_has_item(key) -> bool`。提供可选 `runtime/actor_agent.gd` 作为子节点适配器；支持真实击杀、状态查询、道具查询与无副作用恢复。未接入击杀接口时走“失败”输出，不能假报成功。无专用道具接口时兼容读取 `Abilities.has(key)`。
- 总控可自行委托这些玩家接口；独立演示角色只在 `tools/level_editor/demo_actor.gd`，不替换现有玩家控制。代理的死亡/显隐/碰撞/处理标记通过 `tl_capture/tl_restore` 恢复；道具归属继续由宿主决定。世界内的代理会通过 `runtime_components()` 和 `component_available` 暴露，仍不自动登记公共 Timeline。
- 回溯后重新建立 Room/区域重叠基线，恢复碰撞不会被误判为再次进入；真正离开后再次进入会重新触发。恢复不重执行死亡、警报或奖励事件。
- “整理节点”只修改排版，支持撤销；最小卡片宽度根据实际中文标题字体测量。预设图可按当前编辑器字体重新排版，自定义图保持自己的布局。

待总控：接入正式玩家/库存/死亡表现及时间线代理登记；把相应游戏事件接到 `publish_event`，协调关卡指令与敌人自定义状态。公共 Timeline、SaveSystem、玩家控制、敌人状态机与机关执行器均未由本专项改写。

## 总控 3C 接口更新 · 2026-11-02

共享玩家与会话已切换到 WASD/Shift/空格、Q/E 浏览后暂停、T 继续、R 固定录像分身、F 主动交互。允许回到分身生成前，已有录像不被改写。HUD 仅保留暂停按钮，能量玩法移除。组合的 can_interact/interact 与无副作用快照接口不变，玩家/分身实际接入交互记录及回放。具体合同和验证见 [3C Playground](../3cplayground/README.md)。本次未修改编辑器实现或用户关卡与机关资源。
