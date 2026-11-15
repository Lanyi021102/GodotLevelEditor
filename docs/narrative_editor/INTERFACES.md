# XLSX 与统一窗口覆盖说明 · 2026-11-12

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

轮盘新建 NPC 的模型、阵营、默认动作与行为引用存于关卡实例 metadata 的 `entity_profile.gd`，不改 NPC 源场景。模型动画按已有同名片段播放；巡逻与行为定义保留为后续行为接入字段。`EntityProperties` 按同世界事件执行器的 active 任务状态控制任务 NPC 的显示、处理与碰撞，任务完成／失败后关闭；常驻 NPC 不依赖任务激活。此规则同样适用于任务 Room 与机关。完整字段和持久化合同见 [轮盘 V2](../level_editor/quick_add_v2_2026-11-15/README.md)。
