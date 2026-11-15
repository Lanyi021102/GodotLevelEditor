> 当前关卡接口（2026-11-16）：关卡编辑使用整关常驻逻辑图，素材添加由三维轮盘负责；“接受任务”接取首项后自动串行后续任务。此前阶段移除的是旧房间接驳图。详见文末常驻逻辑合同与验证。

# 浅色界面覆盖说明 · 2026-11-15

2026-11-15 资源导航更新：关卡、机关、NPC 一级按钮均回到各自“我的…”目录。`asset_workspace.gd` 通过 `asset_panels["机关"/"敌人"]` 托管机关和 NPC 的两层页面，原模块面板仅移动到 `editor_host`，图格式、撤销归属、保存与运行逻辑保持。`open_tab("机关"/"敌人")` 保留程序化页面导航；一级按钮额外切回目录。二级栏及分隔线按当前分类互斥显示。

目录读取机关组合 `.tscn` 与 NPC `EnemyDefinition .tres`，路径作为目录项键，不引入配表或新资源 ID。单击只更新选择；双击／进入编辑打开资源；编辑页签只恢复已打开的资源，不加载仅被选中的卡片。NPC 新增 `definition_opened(path)` 在成功载入后发出，目录仅在目标实际打开后进入编辑，沿用已有草稿确认。机关切换前调用原保存接口，保存冲突阻止切换；原生场景切走时回到目录。目录重载使用不复用缓存的资源读取，保存后更新名称与统计。

模块新增 `library_actions: Array[Button]`：仅在套件托管期间隐藏编辑栏的新建／打开／示例入口，禁用套件时恢复；新建通过目录使用原 Store 写入，拒绝覆盖同名文件。`level_card` 增加可选 `new_title`、`metadata`、`fallback_icon`，现有关卡数据和交互保持兼容。资源没有预览时显示类型示意图。接口与验证见 [资源导航记录](asset_navigation_2026-11-15/validation.md)。

套件采用冷灰工作区、白色面板和蓝色强调。此说明覆盖下文历史的米白页头、蓝金渐变卡片与缩放动效约定。现有数据、运行接口、模块归属、撤销与原生三维视口边界不变。

- 一级导航为实蓝选中底和白字，二级页签为透明底、蓝字及底部指示线；中间分隔线只在关卡／任务子导航可见时显示。页头移除重复产品名；原生系统窗口标题保留。`navigation(button, height, primary)` 默认一级，关卡及任务子导航传入 `primary=false`。仅呈现调整，原有 `open_tab`、按钮映射与互斥选中保持。
- `select_navigation(Button, selected)` 统一维护互斥状态、选中字重和短时动画；调用者继续使用原页面映射。`navigation` 本身不监听会重复触发切换的 pressed 信号。`tab_motion` 对子页淡入只连接一次。图节点选中动效只复制 `panel_selected` 的 StyleBox 并动画其阴影，不增加 GraphNode 子控件，不改变端口索引、类别填色、运行绿色边框或图资源。连续选中取消旧 Tween，隐藏的导航及卡片复位。
- `editor_style.gd` 集中提供主题、导航及 `graph_canvas(GraphEdit)`；`workspace(Control)` 在模块进入套件窗口时统一应用画布与表格样式。
- `graph_canvas` 开启双层方格显示，设置画布边框及线条外观；不修改 `snapping_enabled/snapping_distance`、zoom、scroll_offset 或连接表。主网格间距仍由 Godot 原生规则决定。
- 关卡目录缩窄时减少列数，详情栏保持可见；卡片悬停仅改变边框及阴影，不改变缩放或命中区域。现有点击选择、双击进入、素材拖放和参数修改继续使用原调用。
- 节点正文改为白色；职责分类色、端口 ID、顺序、类型和颜色保留，选中边框使用蓝色，运行活动边框继续使用绿色。
- 白盒素材卡片按继承主题显示浅色；Godot 原生深色侧栏保持深色呈现。运行场景、HUD、关卡、机关、台本和 XLSX 内容未修改。
- 验证与截图见 [2026-11-15 视觉更新验证](visual_refresh_2026-11-15/validation.md)。

# GodotLevelEditor 窗口与事件任务接口 · 2026-11-12

2026-11-16 轮盘 V2：素材选择与放置归属原生关卡插件，独立窗口使用下文“常驻关卡逻辑与任务接取”合同，不再重复提供五类仓库。鼠标侧键短按切换轮盘；NPC、机关、Room 提供常驻／任务二级菜单和原生实例检查器。事件执行器注册 `godot_level_editor_task_directors` 组，供实例适配器按 world、level_id 和 task_states 判断任务对象存在性；不另建任务状态来源，不改工作簿 schema。详见 [轮盘 V2](../level_editor/quick_add_v2_2026-11-15/README.md)。

## 插件归属

`addons/godot_level_editor_suite/plugin.gd` 是统一入口。四个已有 EditorPlugin 作为模块保留原生注册和调试／撤销接口，加入 godot_level_editor_suite_modules 分组并通过 godot_level_editor_module 标识。启用套件后隐藏各模块主界面入口，统一窗口托管其 Control；不复制定义或场景数据。

窗口为 Window(force_native=true, transient=false)，主题从 EditorInterface.get_editor_theme 合并原生资源后覆盖套件配色、字号和样式。面板暂时移动时用 godot_level_editor_reparenting 标记保护 _exit_tree 的撤销历史清理；关闭窗口仅隐藏，禁用插件时将模块控件恢复原父级。图端口和资源格式保持兼容。

2026-11-15 试玩窗口更新：F5/F6 保留工作窗口现有可见性，_build 和运行开始只隐藏未提交弹窗以解除模态焦点。_make_visible 在启动及运行期间不调用 show_window，不自动抢焦点或切换页面。手动关闭后保持关闭，显式菜单仍可打开；编辑数据和撤销历史保留。play_focus_test 分别实际启动 F5 主场景和 F6 用户关卡，headless 与 Metal 均通过 15 项。

2026-11-13 导航改版：镜像三维页及 level_workspace.gd 已删除，Godot 原生视口与白盒侧栏保持原位。外层 TabContainer 隐藏内置标签，托管七个页面；六个矩形按钮对应关卡、任务、机关、台本、NPC、其他。任务包含事件与任务、任务图两个子页。open_tab 继续使用原子页名称，关卡图映射到关卡编辑的图子页。选中状态由 tab_changed 更新，中蓝 #5b93bf、深蓝 #132d68、白色文字、米白 #fff0d8 页头。初始尺寸 1504×1000，之后保存用户尺寸。

文件归属：套件、工作簿适配器和事件执行器在 addons/godot_level_editor_suite；台本继续在 addons/godot_level_editor_narrative；原有 level/mechanism/enemy 模块仅改统一窗口接入、移动保护和呈现简化。原有房间、机关、光照、基础玩家和空白主入口保持。

## 工作簿接口

`runtime/xlsx.gd` 使用 ZIPReader/ZIPPacker 和 XMLParser 读写标准 OOXML 工作簿，不依赖 Excel、Python、Node 或第三方运行包。read_book 返回 {sheets, errors}；records 检查必需表头；write_book 写临时文件后替换目标。

支持 sharedStrings、inlineStr、文本／数值直接值、Unicode、转义、前导零和分表。遇到公式、丢失工作表／表头或错误版本拒绝运行，不静默降级到 CSV。

`event_catalog.gd` 配表 schema 2：

- 事件页：event_id, name, display_name, notes, order, start_type, start_key。
- 任务页：task_id, event_id, name, display_name, notes, order, graph_path, level_id。
- 配置页：version, next_event_id, next_task:<event_id>。

event_id >=1001；任务 ID 拼接所属事件 ID 和至少三位后缀。ID 不随排序、撤销或删除回退重用。任务到事件的关系通过 event_id 明确存储。程序名与显示名分别存储；顺序必须为非负且在各自作用域唯一。

台本 XLSX 页结构见 narrative_editor/INTERFACES.md。图资源引用 dialogue_xlsx，默认 res://配表/dialogues.xlsx。task_definition.table_file/load_dialogue 只读 XLSX。

## 事件执行器

`event_director.gd`：world_path 指定世界，workbook 指定事件工作簿。start_type 支持 manual / room_enter / event_received / game_start。start_event 接受事件 ID 或程序名，publish_event(key) 投递具名事件。

一个事件只配置一个当前任务执行器，不把未来任务加入触发队列；不同事件按稳定 ID 顺序推进。现有 event_runner 仍负责每图 64 个事件／帧、队列限制、具名端口和实际动作。任务完成先标记，等当前事件批次清空后才切换到下一任务，避免丢失同一批次的后续动作。

图的 task_start/task_complete 参数绑定当前任务 ID。event_hold 和 event_complete 是显式事件级控制；自动结束被 hold 取消时，最后一个任务图仍保留接收事件能力，便于稍后触发完成节点。

无效或缺失任务图不会伪造完成，当前任务等待配置。空事件没有未完成任务，开始后立即完成。

信号：event_started/event_completed/task_started/task_completed/objective_changed。HUD 使用显示名。ShowDialog 读取 XLSX 并继续使用 comment 边界；对话打开后临时隐藏目标与名牌，结束恢复。未接入默认空白 main。

capture_progress 返回 version/workbook/events/tasks/active/dialogues，active 包含 index/hold/objective/runner 状态。restore_progress 校验作用域和已知 ID，在错误时不改写当前状态，正常恢复不重发完成信号。原 main.gd 的 Narrative/Tasks 保存桥兼容此接口。

export_plugin.gd 将配表目录的 XLSX、事件引用的任务图以及任务资源引用的工作簿加入导出，不依赖 CSV 或目标设备上的表格软件。

## UI 约束与验证

2026-11-12 用户明确要求：不增加格式说明、空运行消息、常驻教学文字或节点分类前缀；分类只保留颜色。保存失败等实际操作结果仍可显示，详细说明使用 tooltip。

验证入口和实际通过项目见 README。旧测试入口已指向当前工作流；不再测试已删除的时间线／分身系统，也不把其恢复。

## 改名与兼容 · 2026-11-13

应用名、插件目录、脚本类、节点名称、玩家／交互分组、调试通道和配表引用路径同步改名。Godot UID 与用户编辑数据的稳定 ID 保留；数据格式不升版。branch 作为条件节点 kind 和局部条件状态键保留，其含义为条件分支，与产品名无关。Git 远程与外部备份地址保持真实有效，未对远程服务改名。

三类图不再创建隐藏的 PortDirections 占位行，端口从实际第一行开始。具名端口、连接索引、顺序、类型和颜色不变；避免 Godot 在隐藏行后计算端口时出现越界。验证包括 139 项节点呈现检查和 Metal 实际渲染。

## 关卡仓库与任务所属关卡 · 2026-11-13

level_catalog.gd 读取配表/levels.xlsx：关卡页 level_id/name/display_name/scene_path，以及可选 notes/preview_path；旧四列可读，可选值补空。配置页 version=1、next_level_id。关卡 ID 是固定数字文本，关卡名唯一；场景都位于 scenes/levels/。世界脚本导出 level_id，world_id 继续作为既有运行实例／存档作用域，旧资源中的 world_id 不重编号。LevelCatalog 的 for_world 优先读取 level_id，再按场景路径匹配。

level_warehouse.gd 分为“我的关卡”卡片目录和“关卡编辑”；编辑中包含五个常驻仓库及“关卡图”子页。新关卡创建地面、玩家出生 Marker、图定义与保留光照，写场景和工作簿；元数据写入失败则清理本次新文件。编辑关卡信息只改元数据，不改 ID 或资源路径。素材卡片提供标准 {type:files, files:PackedStringArray}，已放置项引用真实 Node，原生视口负责放置及场景撤销。重复拖放时只为新实例修正同作用域的重复 room_id/object_id/instance_id，已载入场景的 ID 不改写。

room.uses_topology 默认 true 保持旧房间连通检查；permanent_room.tscn 显式 false，是大世界常驻检测区，不要求房间连线。空世界允许没有 Room。主入口 _initialize_world 读取 role=player 的 spawn_marker，设置 player.global_transform、spawn_transform 和相机；没有 Marker 时保持旧入口位置。

任务 schema 2 的 level_id 必填且只能引用 levels.xlsx 中的一行。事件没有关卡字段。add_task(event_id, level_id) 是显式双参数接口，next_task_id 只预览编号；新建弹窗验证通过后才分配。事件与任务 Tree 新增所属关卡列；任务显示一个中文名，事件动态聚合子任务关卡，不保存另一份事件绑定。复制保留关卡并分配新任务 ID。旧任务迁移：报到任务属于连续世界，其余无法判断的旧任务按用户选择属于当前白盒。

EventDirector 当前任务必须与 current_level_id 匹配才创建／推进执行器并接收触发。bind_world(new_world) 断开旧信号，保存当前图状态，连接新关卡 Room/NPC 并按所属关卡恢复；不进行场景传送。跨关卡事件的下一任务可处于 active 等待，但在错误关卡不执行。capture_progress/restore_progress 保留暂停执行器的状态。启动试玩时主插件窗口保持原状态，新建任务／关卡等弹窗隐藏以解除模态焦点。

levels.xlsx、events.xlsx、引用的关卡、任务图与资源依赖都纳入导出插件。表格在游戏中直接读取，运行时无表格软件依赖。当前默认白盒入口仍不接入示例任务。

验证：49 项任务运行检查（包含跨关卡隔离及续接），52 项套件编辑检查（实际渲染额外验证卡片尺寸，共 53 项），11 项实际试玩窗口焦点检查，5 类原生视口放置检查；原有关卡／机关／敌人／相机／白盒材质回归通过。所有工作簿更改及界面已渲染检查。

## 界面动效边界 · 2026-11-13

editor_style.gd、level_card.gd 的 Tween 只作用于编辑器 Control 的透明度、缩放及阴影。页面／详情淡入 0.18 秒，卡片悬停 0.17 秒；新操作结束前一 Tween，卡片隐藏时复位。圆角 shader 只裁切 UI 图片透明度，不改变图片颜色。静态缩略图保存在 resources/level_previews；捕获工具只渲染临时场景副本。游戏节点、角色和环境均不接入这些动效。

## 独立关卡试玩 · 2026-11-15

world.gd 在非编辑器模式 deferred 检查 current_scene == self 且没有 main 会话，满足时创建 scenes/level_editor/play_session.tscn。该组件复用 main.gd；main 新增 world_path，默认 World 保持原主入口兼容，试玩组件设为 .. 指向当前关卡。只创建一个现有玩家、第三人称镜头、LevelAgent 及 HUD，persist_progress=false；不改变场景根、布局、ID 或存盘内容。出生点及掉落复位沿用原逻辑。嵌入主游戏或其他宿主的世界不自动创建会话。导出显式包含试玩组件及其依赖。

关卡卡片可保存备注及 preview_path；删除前检查任务引用，只移除目录行，保留场景并在 user://level_archive 存元数据。操作失败保留原目录。节点正文改为浅色，分类色继续在标题和端口表达，选中使用金色边框，不增加前缀或说明行。工具栏按需换行，避免把原生窗口撑宽。

## 箱庭关卡当前合同 · 2026-11-15

关卡目录的一行与一份大关卡场景对应，箱庭内部布局直接在原生 3D 视口搭建，不使用房间接驳图。level_warehouse.pages 仅包含出生点、Layout 白盒、常驻 Room、常驻机关、常驻 NPC 五类仓库。suite 不再 _adopt(level.panel)，旧 open_tab("关卡图") 重定向关卡编辑并保持当前仓库分类。模块仍保留旧图的资源及运行兼容；启用套件时不再由原关卡插件接管图资源编辑。

原生侧栏删除接驳点卡片、起始房间与节点图按钮；新建 Room 不参与拓扑，world.validate 对纯检测区不再要求 start_room_id。旧用户场景及拓扑资源不自动迁移。任务、机关与 NPC 逻辑图、运行事件信号和所有稳定 ID 保持。验证见 [箱庭工作流](sandbox_levels_2026-11-15/validation.md)。

## 天空页与关卡信息 · 2026-11-15

统一窗口增加“天空”导航及独立预设面板。关卡信息新增预设选择，详情显示引用名称；绑定保存在 `.tscn` 的世界根 sky_preset，levels.xlsx 格式不变。新关卡默认 V2 天空模板；旧关卡不自动迁移。关闭工作窗口及开始试玩结束临时预览，草稿保存与场景保存分开。天空导出插件补齐预设及导入 HDRI 依赖。完整合同与验证见 [天空接口](../sky_editor/INTERFACES.md) 和 [验证](../sky_editor/validation/validation.md)。


## 通用任务节点 · 2026-11-15

任务图新增通用穿着／背包／角色状态检查、变量、等待、并行与汇合、子目标、失败、检查点、子图等 33 种节点，并开放 16 种已有节点。当前事件执行器连接场景、角色数据和运行调试；节点参数、进度恢复、同关卡检查点与兼容边界见 [通用任务节点](../narrative_editor/task_nodes_2026-11-15/README.md)。原有用户资源、配表和默认白盒入口保持。

## 常驻关卡逻辑与任务接取 · 2026-11-15

level_warehouse 不再创建 pages/inventories 或提供素材拖放；logic_panel 托管当前 world.level_logic。关卡目录、关卡信息和天空绑定保留。套件保存全部与原生场景保存接入图数据保存，原生保存钩子不会递归请求保存场景。

event_director 增加 accept_task(task_id)->{ok,reason}，仅接取当前关卡事件的首项任务，接取后沿用既有串行任务及跨关卡续接；重复、失效、非首项或错误关卡的任务返回失败。level_runner 与 active[event].runner 独立运行，常驻 NPC 的允许交互状态与当前任务需求取并集；对话共用同一播放器。保存进度额外记录常驻图 ID、变量、等待及执行状态，不改变旧配表 schema 或稳定 ID。详见 [常驻关卡图](../level_editor/level_logic_2026-11-15/README.md)。

## 新增关卡物件自动分类 · 2026-11-16

新增 NPC、Room、机关、白盒统一放到根下对应的空 Node3D 管理容器，由关卡插件负责原生撤销和稳定 ID。新建关卡的初始白盒地面也进入“关卡白盒”；已有用户关卡不自动整理。目录及列表继续引用实际实例，不新增配表字段。world／Room 的对象读取兼容透明容器，内部预制件仍保留自己的作用域。详细合同与检查见 [关卡接口](../level_editor/INTERFACES.md#新增物件自动分类--2026-11-16) 和 [自动分类验证](../level_editor/content_groups_2026-11-16/validation.md)。
