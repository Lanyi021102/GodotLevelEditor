# 编辑器流程测试验证 · 2026-11-17

在现有工作区新增独立测试关卡和事件，以真实界面鼠标拖线，再从接取到完成实际试玩。用户要求非阻塞问题先登记、之后统一修复；本轮没有修改编辑器产品实现。

## 结论与证据

- 关卡 9“编辑器流程测试”、事件 1004、三个顺序任务 1004001～1004003 已登记并可打开。
- 常驻图、三个任务图、一个子图合计 **47 个节点、41 条连线、33 类节点**。全部最终连线通过原生鼠标拖拽建立，没有脚本生成连线。
- 完整人工试玩两遍通过；第二遍安装只读记录器，**12 项最终状态全部通过**。原始记录：[manual-session.json](manual-session.json)；真实运行画面：[manual-complete.png](manual-complete.png)。
- 8 组既有 headless 回归合计 **367 项断言、0 失败**。它们验证模块运行合同，不等同于人工操作每个编辑页面。
- 图规模、节点种类和最终资源哈希见 [evidence.json](evidence.json)。复测步骤见 [当前指南](../../wiki/tutorials/editor-flow-test.md)。

## 制作方式与改动范围

先用实际 UI 新建关卡、事件和首项任务，再准备独立台本、场景对象与空连线图。`tools/editor_flow_test/prepare.gd` 保留首次准备过程，创建图时显式断言 edges 为空；它不用于重新生成现有完成案例。之后在真实 Godot 图编辑器中拖出每一条边、保存并检查落盘端口。子图的角色状态节点通过“添加节点”搜索新增、修改参数并连线。

新增资源为 `scenes/levels/9_editor_flow_test.tscn`、`resources/task_graphs/editor_flow_test/*.tres`、`resources/narrative/editor_flow_test.xlsx` 和测试观察脚本。配表仅为本轮新增关卡／事件／任务登记；未更改默认入口、主台本或其他关卡。已有同 ID 的孤立图 `resources/task_graphs/1004001.tres` 保留，测试使用单独目录。保留进入本轮前已经存在的工作区改动。

`SessionRecorder` 监听任务、检查点、事件和按钮信号，并读取完成状态；不模拟按键、不发送交互、不推进任务。事件完成后写出结果和截图。证据记录 mode=manual，checkpoint_restores=0。

## 真实界面覆盖

| 项目 | 本轮检查 | 结果 |
|---|---|---|
| 目录与任务登记 | UI 新建关卡、事件、首项任务；进入任务图与常驻图 | 通过 |
| 连线 | 事件、布尔、数值、等待、子图等代表性端口，共 41 条最终边 | 保存后端口及数量正确 |
| 节点搜索与参数 | 搜索新增 set_actor_state；修改状态键并应用 | 子图写入 flow_verified=true |
| 撤销与重做 | 装备图撤销后保存 9 边，重做后保存 10 边 | 通过 |
| 断开与重接 | 子图拖离原终点输入，再经状态节点重连 | 通过 |
| 保存与切换 | 另存、打开、任务切换、适合画布、常驻图保存并重载 | 最终文件与试玩通过；保存日志见待复核项 |
| NPC 与站桩对话 | F 互动、F 继续；对白期间移动受限，结束后恢复 | 通过 |
| 任务接取与顺序 | 常驻图接取 1004001，自动推进 1004002、1004003 | 通过 |
| 背包与穿着 | 添加 flow_uniform、装备 body；两个条件 all 后判断 | 通过 |
| 按钮与门 | 第一次交互门不打开；按钮复位后第二次开门 | 通过 |
| 机关等待与区域 | 门 open 与进入 flow_finish 的条件汇合 | 通过 |
| 异步与子图 | delay 1 秒、timer 2 秒汇合；数值变量为 2；子图延时 0.5 秒返回 | 通过 |
| 完成反馈 | 自由对话自动结束、任务列表划线淡出、绿色完成提示 | 通过 |

第二遍原始时序：任务 1 在 47385 ms 开始，56952 ms 完成并启动任务 2；两次按钮交互为 76756 / 92867 ms；进入区域后任务 2 在 103894 ms 完成；检查点在 103921 ms 保存；任务 3 在 106489 ms 完成。以上为相对游戏进程启动时间，包含人工观察与停留。

12 项状态为：事件完成、三个任务完成、至少两次按钮交互、门 open、Room active、变量 flow_count=2、物品数量为 1、body 穿着正确、子图角色状态为 true、检查点已保存。最终自由对话采用 3 秒计时；记录器在事件结束后捕获，因此完成截图仍可能保留这段对白。

## Headless 回归

运行方式：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch <测试场景>`。所有测试进程 exit 0。

| 测试场景 | 断言数 | 结果与日志 |
|---|---:|---|
| `tools/narrative/test_task_nodes.tscn` | 90 | 0 失败；[日志](task-nodes.log) |
| `tools/godot_level_editor_suite/runtime_test.tscn` | 49 | 0 失败；[日志](suite-runtime.log) |
| `tools/mechanisms/independent_v1/test_runtime.tscn` | 38 | 0 失败；[日志](mechanisms-runtime.log) |
| `tools/mechanisms/doors_v2/test_runtime.tscn` | 46 | 0 失败；[日志](doors-runtime.log) |
| `tools/level_editor/test_room_triggers.tscn` | 33 | 0 失败；[日志](rooms-runtime.log) |
| `tools/enemy_editor/test_enemy_editor.tscn` | 45 | 0 失败；[日志](npc-runtime.log) |
| `tools/sky_editor/runtime_test.tscn` | 32 | 0 失败；[日志](sky-runtime.log) |
| `tools/narrative/test_dialogue_modes.tscn` | 34 | 0 失败；[日志](dialogue-runtime.log) |

另做 headless 编辑器导入与新关卡启动检查，exit 0；[关卡启动日志](startup.log)。机关测试中的旧房屋对象引用提示由原测试明确作为既有检查结果保留，本轮未改用户资源。

## 非阻塞观察项：暂缓修复

| 编号 | 观察 | 影响与后续 |
|---|---|---|
| FLOW-01 | 靠近 NPC 时，名牌及附近标记文字变大、相互遮挡 | 未影响 F 交互、对话与任务；后续统一检查三维文字尺寸和遮挡 |
| FLOW-02 | 经辅助功能调用常驻图“保存／保存后重载”时，日志出现 progress dialog 在消息刷新／call_deferred 中使用的错误，回溯指向 level_logic_panel.gd:95 | 文件保存、重载和随后试玩成功；后续用普通点击独立复核调用时机，当前不判定根因。见 [日志摘录](save-log-excerpt.txt) |

用户在其他屏幕的鼠标／键盘操作、焦点变化和因失焦重试的拖拽不作为编辑器 Bug。临时 single-window 配置下的子窗口焦点日志、另存时把完整路径误填进文件名导致的首次失败，均不计入确认产品问题。

## 覆盖边界

- task_fail 及子图 failed 出口已连线，成功路径没有触发它们；检查点保存已测，恢复／重试未在人工试玩中触发。
- 33 类是图内种类数，不表示全部节点都走过每个出口。当前节点选择器还提供其他种类，本轮没有验证全部端口组合。
- NPC 行为图、五类机关各自的完整制作 UI、天空／HDRI 导入、HUD 编辑、所有 NPC 模型和关卡点线面工具未在本次人工流程中逐项复测；上表回归只支持各自实际断言。
- 图节点移动／自动整理没有取得明确验证证据，不计为通过，也未据此认定 Bug。

## 文档与命名

同步 README、Wiki 教程／功能地图／版本记录、mkdocs 导航和台本任务 INTERFACES。新增显示名使用“编辑器流程测试”“检查背包与穿着”“按两次按钮并穿过门”“等待流程检查完成”“测试员”“门后区域”等自然中文，符合共同命名约定；稳定 ID 与引用保留。

`python3 tools/wiki/wiki.py check` exit 0：19 个 Wiki 页面、1262 个本地链接、52 个图片引用、164 条搜索记录，errors=[]。构建仅提示一条既有专项文档旧锚点信息，不是本轮新增链接。已用本地实际浏览器检查新教程正文、导航与连线表格，显示正常。
