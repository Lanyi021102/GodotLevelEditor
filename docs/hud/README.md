# HUD 编辑

更新：2026-11-12，转为个人白盒编辑器。

布局为 `scenes/hud.tscn`，在 2D 视口编辑；样式为 resources/ui/hud_theme.tres，控制器为 scripts/hud.gd。保留 CanvasLayer、Root 和主题，当前不预设 HUD 控件。原时间暂停按钮及其信号已删除。

世界 set_* / flash_message 等调用保留无界面兼容方法。台本字幕由独立对话层显示。验证见 tools/3c/test_3c.tscn 和 [转型记录](../cleanup/WHITEBOX_2026-11-12.md)。


## 事件与任务列表 · 2026-11-16 {#task-tracker}

`scenes/hud.tscn` 的 `Root/TaskTracker` 为左上角两级任务列表，可在原生 2D 视口调整位置与宽度。第一行显示事件中文显示名，第二行缩进显示该事件当前任务中文显示名；仅显示文字，不带左侧图标或图标占位，不显示任务编号或图节点状态。

任务完成后，从左向右划掉任务文字，短暂停留并淡出，再渐显下一项。最后一项播放后移除该事件。多个已接取事件分别排列；连续快速完成逐项播放，动画不阻塞运行器推进。对话隐藏并暂停动画，读档／检查点恢复清除旧动画队列。

选中 TaskTracker 可调整 `strike_seconds`（默认 0.25）、`completed_hold_seconds`（0.25）、`fade_out_seconds`（0.18）、`fade_in_seconds`（0.25）。无正在进行的事件时自动隐藏。事件与任务名称仍在“任务 → 事件与任务”填写，不需要另配 HUD 节点。

界面源为 `scenes/ui/task_tracker.tscn`、`task_tracker_line.tscn`；显示控制位于 `scripts/ui/task_tracker*.gd`。当前事件执行器复用 HUD 内实例，独立宿主缺少 HUD 时才创建备用实例。任务状态与存档格式不变，旧 objective_label.text / objective_changed 继续提供完整状态文字；简洁列表只显示事件及当前任务。

验证与实际画面见 [任务列表验证](task_tracker_2026-11-16/validation.md)。
