> 当前关卡接口（2026-11-16）：关卡编辑使用整关常驻逻辑图，素材添加由三维轮盘负责；“接受任务”接取首项后自动串行后续任务。此前阶段移除的是旧房间接驳图。详见文末常驻逻辑合同与验证。

2026-11-16 选择工具与步长：工具栏统一为“呼出轮盘／选中面／选中线／选中点”，三个选择模式共享 `push_pull_tool` 的单元素 subgizmo 事务，通过 `selection_id()` 和 `element_frame()` 向原生操作轴提供元素中心。`mesh_elements.gd` 按共用位置焊接顶点，合并三角形边并排除共面内部对角线；线／点按屏幕距离拾取，过滤背面及近处白盒遮挡。变换仍调用 `face_edit.transformed_state`，保留 `mesh_edit.version=1`、对象 ID、碰撞更新与原生撤销；单点绕自身旋转返回未改动状态。Esc／空白取消子选择后恢复物体轴；选择模式内隐藏旧尺寸手柄，退出模式后恢复。`plugin.edit_step` 来自工具栏可填写输入和 0.1／0.5／1 预设，同步原生平移、元素移动及轮盘放置，只写项目 EditorSettings metadata，不重写现有场景。详细接口及验证见 [选择工具与步长](selection_tools_2026-11-16/validation.md)。

# 关卡专项接口 v1 · 2026-10-30

## 新增物件自动分类 · 2026-11-16

- `scene_groups.gd` 集中管理空 Node3D 父节点：`NPC`、`Room`、`机关`、`关卡白盒`。首次确认放置时创建，同类后续复用；取消预览不创建分组。只处理新增内容，既有根节点物件不自动迁移。
- 容器使用 `godot_level_editor_content_group` metadata 标记职责，重命名显示名称后仍可复用；同名的业务节点不被改造或覆盖，必要时使用唯一容器名称。管理节点无脚本、不含游戏逻辑。
- `plugin._add_nodes_undoable(parent, nodes, root, title, additional_owned=[])` 将分组创建、实例加入、owner 和旧拓扑首 Room 绑定合并到同一次原生撤销操作。批量混合素材按类别分别入组，保持一次撤销；已有分组不随撤销其他新增物件被删除。
- 轮盘、工具栏添加、实例化 Room、复制与标准素材拖放共用新增事务。`asset_drop_tool.gd`／`asset_drop_surface.gd` 仅在原生视口拖放目录素材期间接收拖放，其他时间鼠标过滤为 IGNORE；使用原有轮盘的被动预览和落点计算，不增加三维视口。普通文件仍走原生流程。
- `GROUPS.contents(root)` 仅展开标记的管理容器，不深入机关／NPC 预制件内部；world／Room 的读取、校验与运行初始化按此保持 `$world/object_id` 和 `room_id/object_id` 原作用域。容器不增加对象 ID，稳定 ID 和内部图引用不改。
- 新建关卡的初始地面、新建 Room 源场景生成的白盒也按新规则归档。已有场景、出生点、保留光照资源不自动整理。
- 检查和原生编辑器截图见 [自动分类验证](content_groups_2026-11-16/validation.md)。


2026-11-15 面操作轴：`push_pull_tool.gd` 管理选面与变换事务，首次点击只选择面；`block_gizmo.gd` 使用原生 subgizmo 接口，将唯一一组移动／旋转轴放在相连共面的唯一顶点平均中心。原生轴优先命中，再进行全场景最近可编辑面拾取；命中别的物体时延迟切换原生选择，避免在引擎遍历 gizmo 时修改集合。选面期间隐藏白盒尺寸手柄；Esc／空白点击调用 `clear_subgizmo_selection()`，保留物体选择并恢复物体轴及尺寸手柄。退出模式、切场景、切出 3D、F5/F6 与禁用插件均清理子选择。`face_edit.gd.transformed_state` 在拖动开始时的局部坐标中变换选面全部共用顶点，随后重新包围、归一化，继续使用 `mesh_edit.version=1`；源对象 ID、父级关系与运行碰撞接口保持。非法翻转及最小厚度继续拒绝，平移与旋转沿用原生吸附及场景撤销。验证见 [面操作轴](face_gizmo_2026-11-15/validation.md)。

2026-11-16 快速添加 V2：`asset_catalog.gd.assets(category)` 返回 `{path, title, category, kind}`；`template(category, lifetime)` 新增 `entity_kind/lifetime/template`，`recent_assets` 同时兼容旧路径和带存在范围的 JSON 描述。`radial_tool.gd` 托管短按切换、放置、清理和原生撤销；`radial_menu.gd` 提供六扇区、常驻／任务二级菜单、搜索和动画，不再提供父级选择。轮盘在活动 `Node3DEditorViewport` 覆盖层上方，并从窗口 `_input` 转换到动画后的控件局部坐标，避免原生覆盖层截走悬停。UI revision 允许热更新后重建旧轮盘而不重载关卡。ghost 位于编辑器 SubViewport、用户场景树之外，停用碰撞、处理及环境等副作用，不写入 `.tscn`。确认放置才创建实例，交给现有类别组织节点接入当前关卡；只刷新根作用域 ID，保留内部引用。已有出生点使用可撤销移动。切场景、切工作区、失去焦点、F5/F6 及禁用插件均清理预览。常驻检测 Room 不自动成为拓扑起始房间，旧拓扑 Room 的起始 ID 与实例使用同一撤销动作。

NPC／Room／机关根 metadata `godot_level_editor_entity` 保存 schema 1 的 `entity_profile.gd` 资源，包含模型、存在范围、任务、阵营、动作和行为引用。`EntityProperties` 是被关卡拥有的普通持久化子节点；其派生 `ModelPreview` 没有 owner，不入盘。`entity_inspector.gd`、`entity_inspector_panel.gd`、`entity_gizmo.gd` 提供原生检查器、撤销与根对象拾取。属性只改当前实例，不改源场景。任务存在性读取同一个世界的事件执行器及当前关卡 ID：任务 active 时显示和启用，结束／失败／未激活时关闭显示、处理与碰撞。事件执行器通过 `godot_level_editor_task_directors` 组提供发现入口。详见 [V2 操作、字段和验证](quick_add_v2_2026-11-15/README.md)。

2026-11-15 独立试玩：直接运行 world 根场景时，运行时创建标准 PlaySession 并使用现有玩家、镜头、HUD、出生点及复位；编辑器模式和嵌入已有主场景时不创建。会话不写回用户场景。详见套件合同。

2026-11-13 大世界仓库覆盖：关卡实体场景统一位于 scenes/levels/；世界导出 level_id 并使用 levels.xlsx 保存 ID、名称和中文名。关卡图移入仓库子页。常驻检测 Room 使用 uses_topology=false，旧连线房间默认 true。出生 Marker 驱动玩家初始及复位位置。详见 [套件当前合同](../godot_level_editor_suite/INTERFACES.md)。

2026-11-13：产品及插件路径改名、五项蓝色导航和原生视口边界以 [当前套件接口](../godot_level_editor_suite/INTERFACES.md) 为准。隐藏的方向占位行已移除，端口对应实际可见行，具名端口与图资源连线保持兼容。

## 统一窗口与节点呈现 · 2026-11-12

专项入口已统一到独立“GodotLevelEditor”窗口；原 EditorPlugin 仅保留模块注册和撤销／调试支持。节点类别只用颜色，隐藏分类文字前缀、方向说明行和空运行状态；端口索引、稳定 ID 和资源版本不变。当前合同与验证见 [套件接口](../godot_level_editor_suite/INTERFACES.md)。此前有关入口和分类前缀的说明为历史记录。


## 白盒转型覆盖说明 · 2026-11-12

当前以个人白盒编辑器为目标。时间暂停、回溯／快进、录像分身、轨迹、能量和能力解锁已删除。此前时间线／分身操作要求仅为历史记录。四套编辑器、定义格式、稳定 ID、连线、组件交互及调试继续保留。组件 tl_capture/tl_restore 供状态保存、复位与编辑器操作使用，不再注册时间线；has_item 只使用角色道具接口，无接口时返回 false。主入口为空白工作区，不接入旧谜题、守卫或剧情。验证见 [转型记录](../cleanup/WHITEBOX_2026-11-12.md)。

## 米制网格呈现 · 2026-11-02

白盒默认表现改用 `resources/materials/whitebox_metric_grid.tres` 的共享着色器及独立底色副本，通过 `scripts/tools/metric_grid.gd` 创建。1 / 0.5 / 0.1 m 刻度按世界空间计算，不依赖 UV；平面使用真实单位切向，曲面使用三向混合投影。`tint`、`visual_scene`、碰撞、推拉数据和场景持久化合同保持兼容。指定 `visual_scene` 时保留模型材质。曲面投影边界与验证见 [材质说明](../whitebox_grid/README.md)。

## v0.4 呈现统一 · 2026-10-31

- 仅在 `node_presentation.gd` 维护关卡节点职责分类，直接复用 `addons/godot_level_editor_mechanisms/graph/node_presentation.gd` 的颜色、节点样式、方向行、端口行及活动边框。未改机关专项文件。
- 持续读取 `source/read_state/player_state` 与记忆 `latch` 属于状态；`goal` 输出一次完成事件，属于触发；`emit_event` 下一帧投递，属于延迟／流程。该映射仅用于标题、筛选和图例，不改 `level_graph.gd` 的定义或节点 kind。
- 方向标识行不启用端口；实际槽位行从 `i` 移到 `i+1`，启用端口的连接索引、顺序、类型和颜色完全不变。保留节点／端口 ID、连线数据、版本 1 资源格式以及运行执行器。
- 活动样式读取现有值、执行计数和原因；事件计数增加时短暂提示，回溯清除过时提示。调试器的暂停／继续仅更新编辑器显示；不写运行实例，也不新增运行消息字段。`Runtime` 标签路径保持兼容。
- **交总控协调**：若将机关呈现工具移至公共目录，需要保留 `apply/direction_row/port_row/show_runtime`、分类色常量及活动样式元数据的兼容接口。当前采用只读复用与本专项适配，不修改公共规范或其他编辑器。

## v0.3 推拉扩展 · 2026-10-31

- 白盒增加仅存储的 `mesh_edit`：`{version: 1, signature, vertices: PackedVector3Array}`。顶点相对 `size` 归一化；`.tscn` 是唯一持久化来源。旧白盒没有该字段时继续程序化生成。
- 共边、共面三角形组成可选表面；沿真实世界法线按 0.1 位移，共用顶点一起更新。尺寸和中心重新计算，其他顶点的世界位置保持不变。拒绝相邻面退化、翻转和局部尺寸小于 0.1 的操作；不提供任意布尔切割或自交检测。
- `apply_face_state({size, transform, mesh_edit})` 原子用于编辑器撤销重做；碰撞从同一编辑网格生成。更改形状类型、阶数等生成参数会临时使用该参数的生成形状；撤销参数后恢复匹配的推拉数据，`size` 仍可继续缩放。
- `native_snap.gd` 通过 Godot 4.7 原生吸附对话框设置平移步长 0.1 并开启吸附；根据原生控件单位和图标定位，不依赖界面语言，设置后用 `EditorInterface` 实际值校验。公共运行时玩家、Timeline、存档和事件接口不变。

本专项只新增 `addons/godot_level_editor`、`scenes/level_editor`、`resources/level_editor`、`tools/level_editor` 与本文档目录；公共文件仅追加 `project.godot` 插件启用项，保留其他插件和默认入口。运行场景遵循当前清理基线。

| 对象 | 接口与含义 |
|---|---|
| 世界根 `runtime/world.gd` | `topology`、`events` 引用两张 `GodotLevelEditorLevelGraph`；`world_id`、`start_room_id` 为稳定 ID |
| 房间根 `runtime/room.gd` | `room_id` 为实例作用域，`display_name` 可改；局部 `object_id` 不依赖节点名 |
| 空间接驳点 | 本地 -Z 指向房间外；每条图边连接两个接驳点，允许双向连续穿行；未连接的接口保持封闭 |
| 区域目标 | `controlled_actor()` 只接受 `godot_level_editor_player` 组且 `is_clone()` 不为 true 的角色；角色碰撞层为 2 |
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
- 调试使用只读 `godot_level_editor_level:state/remove` 通道。包包含编辑器会话、实例路径、世界/图 ID、语义摘要、实际值与最近原因；同一定义的多个实例分开显示，运行不接受编辑器写状态。

## v0.2 适配 · 2026-10-30

- 仍使用格式版本 1，新增预制节点类型；旧节点/端口 ID 与四房世界继续兼容。中文名称只影响显示，不作为引用。
- 白盒新增 `shape_kind/steps/step_height/thickness/curve_angle/skew`。`size` 初始为 1，尺寸按 0.1 量化，最小 0.1；编辑器原生缩放也以 0.1 量化，支持非等比正缩放。旧场景通过既有 `size` 保存布局。门洞/窗洞/管道使用真实三角碰撞；形状网格与碰撞由同一生成器产生。单个定高楼梯最多 64 级。
- `palette_assets/*.tscn` 是原生拖放预设，数据协议 `type=files`；拖放预览、落点与撤销采用 Godot 的原生场景拖放。实例在进树时分配空缺的稳定 ID，不修改共用预设。Room 编辑器表现使用线框，避免把检测体误作放置表面。
- Room 增加 `player_entered(room_id, actor)` / `player_exited(room_id, actor)`。检测范围为局部 X/Z 各半宽、Y 从 0 到 `bounds_size.y`；排除分身，仅检测 `godot_level_editor_player`、角色碰撞层 2。接驳点的旧 `room_entered(from,to,actor)` 仍表示跨接口方向，二者语义分开。
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

## 台本与任务兼容扩展 · 2026-11-12

GodotLevelEditorLevelGraph 新增 npc_interact/dialog_completed/show_dialog/task_start/task_complete，沿用版本 1 与原端口合同。共享画布支持参数编辑和分类呈现；实际任务执行由独立 task_director 负责。正式玩家补上既有 Room 检测合同要求的 godot_level_editor_player 分组，分身仍被过滤。现有世界事件与快照格式保持兼容；说明和回归结果见 [任务接口](../narrative_editor/INTERFACES.md)。

## 箱庭关卡当前接口 · 2026-11-15

独立套件不再托管 level.panel，不显示“关卡图”；旧 open_tab("关卡图") 仅兼容导航到关卡编辑，不选择某个素材页。原生摆放侧栏移除节点图、起始房间和接驳点入口，新建 Room 场景／物件及 palette_assets/room.tscn 均为 uses_topology=false。world.validate 仅在存在旧 uses_topology=true 房间时要求有效 start_room_id；多个常驻检测区仍可独立触发 Room 进入事件。旧图资源、稳定 ID、运行接驳及保存格式不变，用户场景不改写。完整验证见 [箱庭工作流](../godot_level_editor_suite/sandbox_levels_2026-11-15/validation.md)。

## 常驻逻辑图当前合同 · 2026-11-15

world.level_logic 是独立的 level_logic_graph 资源，默认内嵌于关卡 .tscn；不覆盖既有 events/topology 资源。关卡编辑托管 level_logic_panel，仅显示逻辑画布和参数；删除五类素材仓库与列表，空间制作由轮盘负责。NPC 使用 world.objects() 中稳定的作用域引用，并在编辑与运行校验中排除 lifetime=task 的对象及其后代。新增 task_accept 的 run:event 输入与 then/failed:event 输出，参数 task 在备注中通过工作簿选择。

event_director 同时维护常驻 level_runner 与各已接取事件的当前任务 runner，按既有预算和异步规则执行；触发广播到常驻图和当前有效任务图。首次直接运行关卡时自动创建唯一服务，automatic_starts=false，避免配表自动条件绕过新工作流的接取。旧显式事件执行器继续兼容原启动条件。完整边界与验证见 [常驻关卡图](level_logic_2026-11-15/README.md)。
