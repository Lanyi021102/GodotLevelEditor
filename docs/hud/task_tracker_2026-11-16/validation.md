# 左上角任务列表验证 · 2026-11-16

Godot 4.7.1，headless 与 Metal Forward+ 实际运行。任务表和图使用内存目录及 user:// 临时副本，未更改用户事件配表、关卡、任务或存档。

- HUD 专项：18 项通过、0 失败，覆盖真实事件与任务显示名、两级缩进、完成划线和渐显、逻辑独立推进、对话隐藏及暂停、最后一项结束、快速连续完成、多个事件、读档及动画中恢复。
- Metal 实际渲染：同 18 项通过、0 失败，确认文字在白盒亮背景上可读、两级紧凑排列、划线绘制在文字前方。
- 原有任务运行回归：49 项通过、0 失败。

初版画面（左侧标记已在下方纯文字更新中移除）：[进行中](01_当前任务.png)、[完成划线](02_划掉任务.png)、[下一项渐显](03_下个任务渐显.png)。

组件位于 `scenes/hud.tscn` → `Root/TaskTracker`，可编辑位置及四段动画时长。运行器依旧按原顺序推进，不等待动画。文本完成状态不写回任务数据；读档清空旧显示队列。旧 objective_label.text 与 objective_changed 继续提供完整状态投影，实际列表只显示事件名与当前任务名。

后期复查在 `/tmp/branch_task_hud_20261116/qa-project` 独立副本运行；副本曾捕获其他窗口修改中的 world.gd 类型推断错误，已随该窗口修复同步后重新通过回归。未修改其他模块负责的源文件。

复现：

```sh
Godot --headless --path /Users/lanyi/branch res://tools/hud/test_task_tracker.tscn
Godot --path /Users/lanyi/branch res://tools/hud/test_task_tracker.tscn -- --capture
```

日志：[headless.txt](headless.txt)、[render.txt](render.txt)、[runtime_regression.txt](runtime_regression.txt)。


## 纯文字更新 · 2026-11-16

按最新要求去掉事件、任务文字左侧的蓝色菱形，并移除 34px 图标占位；事件名、缩进的任务名及完成动画继续保留。此修改未更改字体、字号、描边或阴影配置。

独立副本 headless 18 项通过、0 失败；Metal 实际渲染同 18 项通过、0 失败。检查实际画面确认两级名称左侧无图标，划线与下一项渐显正常。

当前画面：[进行中](text_only/01_当前任务.png)、[划线](text_only/02_划掉任务.png)、[下一项渐显](text_only/03_下个任务渐显.png)。日志：[headless](text_only/headless.txt)、[Metal](text_only/render.txt)。

本轮已执行 Wiki 检查：当前有一项其他窗口更新中的 FAQ 链接缺少 `godot_level_editor_suite/display_refresh_2026-11-16/validation.md` 目标；本轮 HUD 的文档与截图链接存在，未代替其他窗口创建占位记录。
