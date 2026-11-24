## 任务图播放演出 · 2026-11-24

任务图支持“播放演出”，通过所属关卡内的稳定演出 ID 读取。成功播放结束触发“完成时”，无法播放走“失败”；任务作用域结束会取消进行中的演出。 见 [演出接口](../performance_editor/INTERFACES.md)。

## 任务归属、试玩记录与配表保护 · 2026-11-19

任务图顶端显示所属关卡、任务、台本和修改状态。试玩动作按已登记的关卡路径打开原生场景后运行，事件表或任务图的草稿保存失败时保留编辑状态。独立图可在有效的当前关卡试玩。新建 NPC 交互、对白、任务节点等待真实绑定，从已绑定任务创建时沿用所属任务 ID。现有已保存节点与协议字段保持兼容。无选择时任务画布收起参数区，展开试玩记录可以定位节点和关联场景对象。

运行调试包新增可选的 trace 与 waiting。前者记录最近八次实际执行的节点及原因，后者从当前等待、汇合与子图状态读取。条件和汇合定位未满足的真实输入节点。恢复检查点时清理先前轨迹，调试数据不写入任务资源或存档。编辑器可读取未含这些字段的旧数据包。

台本、事件、原生关卡登记均通过 xlsx.save_tables 保存。编辑时保存读入的工作簿版本和 OOXML 部件，按稳定记录 ID 修改插件字段。作者附加工作表、附加列、独立备注行、作者公式及关联部件保留。写临时文件、复读、检查目标版本后替换。同一路径的外部修改或删除均返回冲突。台本可另存并继续编辑副本，事件表的另存草稿保留原游戏数据源。模块在运行中只需读取插件字段。验证见 [本轮验证](authoring_2026-11-19/validation.md)。

## 插件目录与原生场景合同 · 2026-11-17

插件本体、示例素材和运行依赖统一到 `addons/godot_level_editor/`；各模块代码在其中的 `modules/`。作者地图、配表与个人资源迁入 `content/`，已有稳定 ID 与 UID 保留；路径迁移表见 `tools/release/layout-migration.json`。

地图采用 Godot 原生文件系统、场景树、保存与 F6，保留轮盘、白盒、点线面和场景对象绑定。“我的关卡”提供原生场景文件的浏览、搜索和打开入口；“关卡编辑”显示当前场景的常驻图。地图仍使用同一份原生场景文件保存。原生保存通过 native_level_registry 登记任务所需 ID，地图路径允许插件目录以外的项目目录。

主插件负责内部模块生命周期和缺省输入／配表初始化；运行服务使用 GLELightZones、GLENoiseBus、GLESaveSystem。用户主场景、已有输入和作者作品不由插件更新覆盖。下面的旧路径和目录入口仅记录当时合同；当前布局与实际验证见 [迁移记录](../cleanup/plugin_2026-11-17/validation.md) 和 [安装指南](../wiki/plugin-install.md)。

任务／台本迁移回归使用 `tools/narrative/structure_qa/`，仅在有专用用户目录的隔离工程运行。覆盖原生继承地图首次另存及稳定 ID 登记、延迟创建页面、XLSX 新建保存重开、事件与任务归属、节点参数及撤销、场景引用接收、实际 F6 接取和两种对话模式；同时复查作者原有任务及 47 节点流程。headless 的连线回调检查与渲染窗口的原生鼠标拖线分开记录。步骤、证据与未覆盖项见 [结构迁移验证](structure_2026-11-17/validation.md)。

# XLSX 与统一窗口覆盖说明 · 2026-11-12

## 人工连线流程样例 · 2026-11-17

关卡 `content/scenes/levels/9_editor_flow_test.tscn` 登记为 level 9；事件 1004 的任务 1004001～1004003 分别引用 `content/resources/task_graphs/editor_flow_test/equipment.tres`、`mechanisms.tres`、`parallel.tres`，后者调用同目录 `child.tres`。常驻关卡图接取事件首项任务，三个任务沿用现有顺序推进合同；图与对白数据格式、稳定 ID 和运行 API 无变化。台本使用独立 `content/tables/editor_flow_test.xlsx`。

测试场景的 `SessionRecorder` 仅观察运行信号和最终状态，写入 `docs/qa/editor_flow_2026-11-17/manual-session.json` 与完成截图，不驱动交互或任务推进。其绿色“流程测试完成”提示需事件结束后 12 项检查全通过；再次试玩会覆盖同名记录。`tools/editor_flow_test/prepare.gd` 仅保留首次准备无连线素材的过程，现有图已存在时禁止重跑。当前操作见 [流程测试指南](../wiki/tutorials/editor-flow-test.md)，真实鼠标连线、回归结果及未覆盖项见 [验证记录](../qa/editor_flow_2026-11-17/validation.md)。

## 单句对话类型 · 2026-11-16

对白行新增可选 `dialogue_mode`：`free`（自由对话，默认）或 `stationary`（站桩对话）。XLSX“对白”页在 text 之前写入 dialogue_mode，原 schema version=2 与必需表头保持；旧 XLSX、TRES、CSV 迁移缺省按 free，非法值拒绝载入。原 type 字段仍为引导／对白／提示分类，ID 和顺序不变。export_signature 包含新类型，类型修改参与相同 UndoRedo 事务；表格内容列前提供原生下拉编辑，详情中也可修改。

dialogue_player 不再暂停整个 SceneTree。free 按 playback_duration 自动逐句播放；duration=0 使用字符／词组与标点估算，正数继续作为明确时长覆盖。stationary 忽略计时，仅接受交互、ui_accept 或鼠标左键的非重复按下。每次换句重置开句帧，结束仍逐句及逐 comment 发出原完成信号，不跨 comment 自动播放。外部暂停不由对话解除。

新增 current_mode() 和 blocks_player_input()。越肩相机按 blocks_player_input 只锁站桩操作，停止水平惯性并释放鼠标；恢复时尊重对话前的输入状态与窗口失焦。关闭句的交互输入保留一个物理帧隔离，避免同一次 F 同时触发旁边机关。没有该新方法的旧对话适配器继续按 is_active 锁定，保持旧宿主兼容。

自动时长默认 0.8 秒起读时间 + 非拉丁字符数／5 + 拉丁词组数／3 + 标点停顿；逗号等 0.18 秒，句末与换行 0.35 秒；范围 2.5～3600 秒。它是可解释的阅读估算，不表示已有录音时长。操作与验证见 [当前指南](../wiki/guides/dialogues.md) 和 [验证记录](dialogue_modes_2026-11-16/validation.md)。

2026-11-16 姓名可读性：台本“NPC 姓名”按完整姓名自动分配蓝、青、紫色系实色标签，同名保持一致。深底配白字、浅底配深灰字，比较相对亮度对比度后自动选择；选中行也保持标签对应字色。标签通过只读单元格自定义绘制回调显示，沿用原生文字绘制及滚动裁切；切换单元格绘制模式后恢复原姓名，字体、字号和字重保持。不会写 `library.speakers`，不修改配表角色颜色或运行时对话表现。检查见 [实色标签验证](../godot_level_editor_suite/filled_labels_2026-11-16/validation.md)，字体解析见 [宋体与字形验证](../godot_level_editor_suite/songti_colors_2026-11-16/validation.md)。

2026-11-16 台本显示：`dialogue_panel` 按字体测量 ID／姓名列宽、保留省略行的全文 tooltip，并提供选中对白的换行阅读区。`dialogue_table_layout` 标记紧凑行样式；字体／窗口变化重新测量，不截断作者数据。搜索无匹配时禁用预览区编辑。布局变化、选中和预览不置脏、不改变 XLSX；原表格／右键编辑、搜索、稳定 ID 与撤销继续沿用。检查见 [显示验证](../godot_level_editor_suite/display_refresh_2026-11-16/validation.md)。

## QA 台本文件与任务绑定合同 · 2026-11-16

- QA-03 / QA-04：新台本 `xlsx_path` 为空时，首次“保存对白”选择路径后调用与导出一致的 XLSX 写入入口。只有写入成功才同时更新 `xlsx_path/source_path`、清除 `dirty/export_dirty`；失败保留当前库、目标前的路径和草稿。
- “打开对白”按扩展名分派：XLSX 走 `read_xlsx`，旧 `.tres` 走资源加载与合法旧结构迁移。候选库先完成版本、结构和内容校验，成功后才替换当前库及撤销历史；无效输入或当前未保存时显示原因，不用空库覆盖。旧 `.tres` 迁移后的第一次保存须选择 XLSX 目标，不继承并覆盖默认工作簿。
- QA-06：`runtime/task_bindings.gd.validate` 由任务保存与套件运行入口复用。在可确认的任务所属世界内检查 NPC / Room 引用及可复用子图，拒绝引用另一任务专属对象；合法当前任务对象不因隐藏而被拒绝。外关卡任务保留既有暂停／续接，不能用不相干的当前场景证明目标已删除。
- 缺失引用的错误在校验保存或运行启动处可定位，不创建一个永远等待缺失 NPC 的有效 runner。模块专项、合法隐藏对象／跨关卡兼容及总控独立整合结果见 [本轮 QA 记录](../qa/bugfix_2026-11-16/validation.md)。

2026-11-16 对象引用拖放：任务节点的 object／room／npc／actor／mechanism 在卡片底部及参数区提供场景树拖放框，放下即绑定并进入同一次图撤销事务。复用关卡公共适配器，维持任务 NPC 裸 object_id 与世界对象 scoped ref 的既有语义；下拉选择和已有引用保持。切换编辑场景后刷新候选及显示，不修改图。详见 [公共合同](../level_editor/INTERFACES.md) 和 [验证](../level_editor/scene_reference_2026-11-16/validation.md)。

2026-11-16 机关桥：任务节点注册机关状态变化／交互／动作完成／感应触发、状态判断、等待到位、状态／动作请求和交互／属性设置。task_runner 复用现有等待、超时、取消和恢复；task_actions 转发到独立机关模块。event_director._connect_world 绑定机制桥，并通过现有 _broadcast 同时服务常驻关卡图与当前任务。引用格式与接口见 [机关合同](../mechanism_editor/INTERFACES.md)，素材与验证见 [首批机关](../mechanism_editor/whitebox_v1/README.md)。

当前台本作者和运行数据均为配表/dialogues.xlsx，使用对话组、Comments、对白、角色、配置五张表。dialogue_library 的 workbook_sheets/write_xlsx/read_xlsx 负责转换；xlsx_path 指定当前工作簿，csv_path 和 CSV 函数仅用于旧数据迁移，不被当前执行器读取。task_definition 改用 dialogue_xlsx/table_file/load_dialogue；事件和任务由套件 event_director 驱动。当前接口见 [套件接口](../godot_level_editor_suite/INTERFACES.md)，下文 V2 合同中有关 CSV 和旧独立入口的条款不再适用。

# 台本与任务接口 V2 · 2026-11-12

## 作者数据

`dialogue_library.gd`：Resource，`schema_version=2`。

- `groups: Array[Dictionary]`：`{id, name, comments}`。
- comment：`{id, name, lines}`，是独立触发及连续播放单位。
- line：`{id, speaker, text, type, duration}`。`duration=0` 按字数自动估时；正数为秒数，最大 3600。类型为引导／对白／提示。
- `speakers: Dictionary[String, Color]`：同名角色共用颜色，新角色按名称自动配色。
- `next_line_id`：单调递增的对白 ID 分配计数，格式至少五位十进制字符串；计数不随撤销回退。组／comment ID 自动生成且不在主表编辑。
- `csv_path`：当前编辑源的配表导出路径。

作者源 `.dialogue.tres` 保留所有编辑数据；CSV 是运行时台词来源。源文件变更仅在再次导出后影响运行数据。旧版 schema 1 的组转换成新 comment，保留旧组 ID 和单句 ID；新增顶层整理组 ID。未知版本拒绝，不静默覆盖。

## CSV 合同

固定 UTF-8 表头：

```csv
version,group_id,group_name,group_order,comment_id,comment_name,comment_order,line_id,line_order,speaker,color,text,type,duration
```

一行代表一条对白；空组／空 comment 用空子 ID 的行保留作者结构。顺序从 0 开始，同一对象的名称、归属和顺序必须一致。ID 读取为字符串，支持旧英文标识和新的数字标识，不丢前导零。颜色使用十六进制 RGBA。同名 NPC 的颜色必须一致。

- `write_csv(path) -> PackedStringArray`：先验证，写临时文件后替换目标；失败保留上一次导出。
- `read_csv(path) -> {library, errors}`：标准 CSV 引号与转义，支持逗号、换行和 Unicode；不合法时返回 null library 和错误，不返回部分可运行数据。
- `comment_by_id(id) -> Dictionary` 查找播放单位，`all_ids()` 收集作者 ID。
- `export_plugin.gd` 将实际导出的任务资源所引用 CSV 加入游戏包。CSV 采用 `importer=keep`，通过 FileAccess 读取原始文件。

## 任务桥

`task_definition.gd` 继承 GodotLevelEditorLevelGraph（图 schema 1 保持），新增 `dialogue_csv` 文件路径；`dialogue_library` 保留为作者源引用。`csv_file()` 优先显式 CSV 路径，其次作者库 csv_path，最后源文件同名 .csv。`load_dialogue()` 只读取配表，不回退到源资源里的文字。

| kind | 参数 | 输入 | 输出 |
|---|---|---|---|
| task_start | task | run:event | then / failed:event |
| task_complete | task | run:event | then / failed:event |
| npc_interact | npc, task | 无 | then:event |
| show_dialog | dialog_id（comment） | run:event | then / failed:event |
| dialog_completed | dialog_id（comment 或单句）, task | 无 | then:event |

ShowDialog 不接受顶层整理组 ID，也不会连续播放同组的其他 comments。旧样例 `reception_intro` 现在是 comment ID，因此原任务图无需重绑。共享关卡图的 dialog_id 校验兼容数字字符串，其余节点／端口类型和版本保持。

任务执行仍由独立 task_director 负责，使用既有事件执行器的稳定顺序、64 事件／帧预算与 256 队列上限。载入校验 CSV、任务引用、真实房间和 NPC；缺失配表、缺失 comment 或无效版本拒绝运行。

## 运行时

- `dialogue_player.show_dialog(comment_id) -> bool`，复制当前 comment 的 lines。
- 每句按 duration 或自动估时推进，结束后发出该句 `dialogue_completed(id)`，最后发 comment ID 和 `closed`；不发顶层组完成，不自动进入下一个 comment。
- `opened/closed` 让任务执行器暂存并恢复目标文字、NPC 名牌和宿主 HUD 的显隐。
- 对话层 PROCESS_MODE_ALWAYS，任务和 NPC 为 PAUSABLE。对话保存／恢复 SceneTree 暂停状态，自动计时在暂停期间继续；F / Enter 可以提前推进。无 Timeline、分身、能量或能力系统依赖。
- 玩家通过 `godot_level_editor_player` 和 `godot_level_editor_interactable` 的距离检查触发 NPC；`interact(actor)` 不接受 null。
- `capture_progress / restore_progress`：`{version:1, graph_id, tasks:{id:active|completed}, dialogues:{id:true}, objective}`。持续进度恢复不重放完成副作用。存档单句和 comment 完成记录，保留旧 ID 兼容；未完成段落下次从头播放。
- `godot_level_editor_narrative:state/remove` 是独立只读调试通道，保留运行计数和原因。

## 文件归属和验证

本专项维护 addons/godot_level_editor_narrative、resources/narrative、scenes/narrative、tools/narrative、docs/narrative_editor。共享变更仅为关卡图的 comment 命名、提示与数字 dialog_id 校验。main、玩家、core、HUD、autoload 和默认白盒入口由同时进行的白盒编辑器聊天维护；未恢复其移除的系统。用户房间和机关资源保留。

专项样例使用 tools/narrative/session_fixture.tscn，与默认主入口分开。31 项运行测试与 25 项编辑器测试，以及实际渲染结果见 README。


## 通用任务节点 · 2026-11-15

任务图新增通用穿着／背包／角色状态检查、变量、等待、并行与汇合、子目标、失败、检查点、子图等 33 种节点，并开放 16 种已有节点。当前事件执行器连接场景、角色数据和运行调试；节点参数、进度恢复、同关卡检查点与兼容边界见 [通用任务节点](task_nodes_2026-11-15/README.md)。原有用户资源、配表和默认白盒入口保持。

## 关卡常驻图复用与任务接取 · 2026-11-15

task_definition.allowed_kinds() 提供可覆盖的节点白名单，level_logic_graph 复用同一参数、端口、对白校验和异步 runner，仅开放适合常驻空间的节点。任务开始、完成、失败、事件结束及任务子目标节点不出现在关卡图；task_accept 只出现在关卡图。NPC 与对白完成触发在关卡图中没有 task 参数，不受任务状态过滤。任务图仍绑定所属任务；首项被接受后，后续任务按原顺序自动接续。当前细节见 [常驻关卡图](../level_editor/level_logic_2026-11-15/README.md)。

## 轮盘实例与任务存在性 · 2026-11-16

Room 现为箱体触发区域。任务图与常驻关卡图共用 `room_active`（room:String、expected:bool，value:bool 输出）和 `room_exit`（room:String、once:bool，then:event 输出），继续支持原 `room_enter` kind。参数使用既有 Room 引用下拉／拖放，校验同任务独占范围。激活先于进入事件更新；任务启用检测与玩家进入激活分开，结束或失败清除激活状态。接口及实测见 [Room 合同](../level_editor/INTERFACES.md) 和 [本轮验证](../level_editor/room_triggers_2026-11-16/validation.md)。

轮盘新建 NPC 的模型、阵营、默认动作与行为引用存于关卡实例 metadata 的 `entity_profile.gd`，不改 NPC 源场景。模型动画按已有同名片段播放；巡逻与行为定义保留为后续行为接入字段。`EntityProperties` 按同世界事件执行器的 active 任务状态控制任务 NPC 的显示、处理与碰撞，任务完成／失败后关闭；常驻 NPC 不依赖任务激活。此规则同样适用于任务 Room 与机关。完整字段和持久化合同见 [轮盘 V2](../level_editor/quick_add_v2_2026-11-15/README.md)。


## 任务图连续切换 · 2026-11-16

套件 edit_task 在未保存图与目标不同路径时调用 task_panel.confirm_graph_switch(continuation)，并显示任务图页的保存／放弃／取消弹窗；保存失败保留当前图及错误，成功后才打开目标。重复打开相同路径不重新加载资源、不清空撤销历史。文件打开使用 CACHE_MODE_IGNORE，遵循同一保护；成功后按事件表中唯一匹配的 graph_path 恢复 bound_task_id，未登记／多重归属时清除旧绑定。目标资源类型检查通过后才更新任务绑定；配表、图资源格式及运行接口不变。验证见 [切换修复验证](task_switch_2026-11-16/validation.md)。

## 旧 NPC 素材清理 · 2026-11-16

存量 `scenes/narrative/npc.tscn` 的脚本使用首批中体型男性的 NPCVisual 替代 CapsuleMesh，保持 object_id、display_name、interaction_radius、can_interact/interact 和 interacted 信号。已有对话场景和任务绑定无需重建。 验证见 [清理记录](../enemy_editor/legacy_cleanup_2026-11-16/validation.md)。


## 任务归属同步与操作分类 · 2026-11-16

task_definition.LOCAL_TASK_KINDS 定义当前任务内的 task_start/task_complete/task_fail/npc_interact/dialog_completed。task_panel 在重建（含打开、粘贴、撤销／重做）及保存前将这些节点的 params.task 同步为 bound_task_id，修改标记 dirty，不自动写盘，不更改节点 ID。独立文件仅在事件表 graph_path 唯一匹配时恢复绑定，不猜测未登记／多重归属图。缺少任务时 validate 显示节点名称、ID 和任务表编辑入口；task_accept 等跨任务接取节点不参与此同步。

任务图顶部仅显示五个常用按钮，其他操作沿用原回调并归入文件／编辑／绑定／试玩菜单。共享 node_picker 提供常驻分类筛选、分组结果与角色色，_can_offer_node(kind) 在分组前按任务或常驻图白名单过滤。node_category 保留隐藏的程序化索引接口；全部列表的标题行 metadata 为空且不可选择，不能当作节点添加。图数据、类型化端口及运行接口保持。

实际验证与截图见 [任务图工具与绑定验证](task_toolbar_2026-11-16/validation.md)。
