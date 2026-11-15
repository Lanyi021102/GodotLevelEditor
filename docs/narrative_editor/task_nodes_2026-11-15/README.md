# 通用任务节点 · 2026-11-15

本轮扩展现有“事件 → 任务 → 任务图”，新增 33 种任务节点并开放 16 种已有关卡节点。保留原有 12 种任务节点、图资源稳定 ID、事件串行排序与关卡绑定。任务图当前共支持 61 种节点；新增节点由当前套件的 event_director 运行。

## 使用

在独立窗口打开 **任务 → 任务图 → 搜索添加**。节点标题使用中文，新增节点可按中文、英文或程序 kind 搜索；英文名称保存在提示中。图的节点、端口、参数、复制、撤销、保存、重开与运行高亮已接入现有画布。

示例图：`resources/narrative/examples/generic_access.task.tres`。它表达“背包至少有一张 access_card，并且 body 部位穿着 work_clothes → 完成通行条件子目标 → 发送 access_granted”。打开示例后另存自己的资源；将所需节点复制到事件任务生成的图中，追加当前任务的完成节点。示例未接入默认白盒或改写现有配表。

### 角色数据

角色的子节点挂载 `addons/godot_level_editor/runtime/actor_agent.gd`，`actor_path` 指向角色（默认 `..`）。已有玩家 LevelAgent 已使用该脚本，NPC 也可挂载。通过原生检查器配置：

- `inventory = {"access_card": 1, "work_clothes": 1}`：物件 ID 与拥有数量。
- `equipment = {"body": "work_clothes"}`：部位 ID 与当前穿着／装备的物件 ID。
- `state_flags = {"ready": true}`：自定义布尔状态。

“检查背包物件”按 ID 和最小数量查询；“检查角色穿着”按部位和物件 ID 查询，部位留空时检查任一部位。节点的角色对象 ID 留空表示玩家，也可选择当前关卡对象引用。查询失败返回 false，动作接口缺失或物件不足从失败端口继续。

“设置角色穿着”要求角色拥有该物件，物件 ID 留空表示卸下；删除最后一件已穿戴的物件会清空相应部位。这里提供穿着数据及查询／修改接口，服装模型替换和完整背包界面由后续角色表现系统接入。旧 `unlocked_items` 仅作为兼容的初始道具清单，不涉及能力解锁。

### 通用交互

将 `scenes/mechanisms/interaction_point.tscn` 拖入关卡或 Room，设置唯一 object_id、显示名和交互半径。玩家按现有 F 交互；任务图“物件交互时”绑定该物件引用。执行器也可接入已有机关的 `interacted(id, action, actor)` 信号，以及 NPC 的双参数互动信号。区域进入／离开直接连接现有 Region 的检测信号。

## 新增节点

| 中文 | English | kind |
|---|---|---|
| 离开区域 | On Region Exit | `region_exit` |
| 物件交互时 | On Object Interacted | `object_interacted` |
| 角色状态变化时 | On Actor State Changed | `state_changed` |
| 检查角色穿着 | Check Equipped Item | `has_equipped` |
| 检查角色状态 | Check Actor State | `actor_state` |
| 任一条件成立 | Any Condition | `any` |
| 条件取反 | Not | `not` |
| 比较数值 | Compare Numbers | `compare` |
| 读取布尔变量 | Get Boolean Variable | `get_variable` |
| 读取数值变量 | Get Number Variable | `get_number` |
| 设置任务变量 | Set Mission Variable | `set_variable` |
| 增减背包物件 | Change Inventory Item | `change_item` |
| 设置角色穿着 | Set Equipped Item | `equip_item` |
| 设置角色状态 | Set Actor State | `set_actor_state` |
| 等待时长 | Delay | `delay` |
| 计时器 | Timer | `timer` |
| 等待条件成立 | Wait Until | `wait_until` |
| 等待事件 | Wait For Event | `wait_event` |
| 并行执行 | Parallel | `parallel` |
| 等待全部完成 | Wait All | `wait_all` |
| 等待任一完成 | Wait Any | `wait_any` |
| 计数器 | Counter | `counter` |
| 流程开关 | Gate | `gate` |
| 取消分支 | Cancel Branch | `cancel_branch` |
| 激活子目标 | Activate Objective | `objective_start` |
| 完成子目标 | Complete Objective | `objective_complete` |
| 子目标失败 | Fail Objective | `objective_fail` |
| 检查子目标状态 | Check Objective State | `objective_state` |
| 任务失败 | Fail Task | `task_fail` |
| 保存检查点 | Save Checkpoint | `checkpoint_save` |
| 恢复检查点 | Restore Checkpoint | `checkpoint_restore` |
| 执行子图 | Run Subgraph | `run_subgraph` |
| 结束子图 | End Subgraph | `subgraph_end` |

## 执行规则

- 条件 AND／OR／NOT 读取当前值；Branch 在事件到达时判断一次；Wait Until 被执行后持续读取条件，并在条件已经满足时立即继续。timeout=0 表示不限时。
- Delay／Timer 使用游戏物理步长，游戏暂停时不会继续计时。run 不重复启动同一个已运行的等待；cancel 清理等待并输出已取消。Timer 还输出剩余秒数。
- Wait For Event 仅接收激活后的事件；不追认激活前发生的消息。需要识别提前完成的行为时，记录角色状态或任务变量，再使用 Wait Until 检查。
- Parallel 提供 A/B/C/D 四条分支，可只连接需要的分支。scope 留空时使用稳定节点 ID，嵌套分支保留父作用域；指定名称后可以用 Cancel Branch 取消该作用域及其子级。
- Wait All 记住各个已连接输入端口的完成情况；重复触发 A 不会代替 B。Wait Any 第一次输入即完成。两者在 reset 前只输出一次。Wait Any 的 cancel_others 可取消同一次 Parallel 的其他分支，包括待执行事件、计时和子图。
- Counter 达到目标次数时只输出一次 reached；reset 后重新计数。Gate 通过 open／close 输入改变后续 run 是否允许通过。
- 任务变量目前支持布尔与数值；同一 event_director 管理的事件／任务／子图共享变量字典，使用不同标识区分含义。数值通过 Compare Numbers 判断。
- 子目标保存 active/completed/failed 状态及可选属性；显示在已有目标 HUD。完成／失败操作要求目标先激活，重复完成不重复生效。可选目标失败不会自动使主任务失败；设计者通过条件和连线决定推进。
- 子图是原生任务图资源，必须通过“结束子图”返回成功或失败。子图共享变量、调用各自的台本工作簿，独立保存运行状态；最多嵌套 8 层。导出器递归包含子图和工作簿。
- Fail Task 停止当前事件，不推进下一任务；HUD 显示原因。有可用检查点时显示“从检查点重试”按钮并释放鼠标。外部组件也可调用 retry_from_checkpoint()。
- Save Checkpoint 在继续事件已入队后保存，恢复从保存节点之后接续。保存角色位置、速度、背包、穿着、状态，现有组件的 tl_capture/tl_restore 状态，以及任务变量、子目标、等待、汇合、子图和任务阶段。恢复不重放已完成动作。
- 检查点属于同一试玩会话、同一关卡实例，拒绝跨关卡或缺失对象的恢复，不负责重新创建已删除的场景对象。检查点本体不写永久存档；原有进度存档继续保存扩展后的任务运行状态。
- 当前任务离开所属关卡时暂停，重新进入后接续；不同事件仍可并行，事件内部任务依旧按配表顺序推进。

## 接口与兼容

运行器：`addons/godot_level_editor_narrative/runtime/task_runner.gd`；通用角色桥：`task_actions.gd`；检查点：`task_checkpoint.gd`。现有共享 event_runner 只增加默认空的扩展钩子，关卡旧图继续使用原执行方式。旧独立 task_director 保留原 12 种节点兼容，遇到新节点会明确提示使用套件 event_director，避免静默不执行。

事件执行器新增 task_failed(task_id, reason)、checkpoint_saved、checkpoint_restored 信号；capture_progress 的 version=1 保持兼容，新增 variables/failure_text 和各活动事件的 objectives。旧存档缺少这些字段时使用空值。节点图仍为 schema 1，未知节点和类型错误拒绝载入。运行调试复用原 godot_level_editor_narrative 通道。

验证见 [validation.md](validation.md)，画布截图见 [任务节点.png](任务节点.png)。
