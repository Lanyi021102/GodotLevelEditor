# 通用任务节点验证 · 2026-11-15

Godot 4.7.1.stable.official.a13da4feb。先运行 headless，再以 Metal 实际渲染检查任务图；1504 × 1000 截图中的条件、事件连线、中文端口和参数栏均可读。

| 检查 | 结果 | 证据 |
|---|---|---|
| 新增任务运行 | 90 项通过，0 失败 | [task_nodes.txt](validation/task_nodes.txt) |
| 新增节点编辑与实际渲染 | 79 项通过，0 失败 | [task_nodes_render.txt](validation/task_nodes_render.txt) |
| 原有事件、任务、对白与跨关卡运行 | 49 项通过，0 失败 | [regression.txt](validation/regression.txt) |
| 当前套件编辑回归 | 78 项通过，0 失败 | [editor_regression.txt](validation/editor_regression.txt) |
| 共享节点呈现回归 | 139 项通过，0 失败 | [presentation.txt](validation/presentation.txt) |
| 默认主入口 headless 运行 90 帧 | 正常退出，无脚本错误 | [main_smoke.txt](validation/main_smoke.txt) |
| 旧关卡 V2 回归 | 97 项通过，1 项已有失败 | [level_v2.txt](validation/level_v2.txt) |

新增检查覆盖真实玩家／NPC 的背包数量和穿着查询、数量不足拒绝、真实交互组件到任务图、区域进出和状态变化的信号桥、子目标 HUD、失败停止任务与重试按钮、同关卡检查点恢复及其图节点、延迟与计时取消、等待超时、门控、计数器、分帧汇合去重、嵌套并行取消、外部事件进入子图、子图异步恢复、中文／英文搜索、所有新增端口和参数、撤销／重做，以及保存重开不改变语义。

## 已有问题

旧关卡 V2 的失败项为 `restored trigger becomes active after a real exit and reentry`。在隔离副本中将本轮相关文件换回开工前的备份，同样得到 97 通过、1 失败，失败项相同，见 [level_v2_baseline.txt](validation/level_v2_baseline.txt)。本轮没有修改该关卡测试、旧世界的重叠检测复位逻辑或用户场景来掩盖此问题。

部分编辑器测试退出时仍可出现 `Plugin is not attached to debugger` 或一个 ObjectDB 实例泄漏提示；新增图节点与运行测试没有脚本错误。调试插件退场逻辑不在本轮修改范围。

## 复现

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch res://tools/narrative/test_task_nodes.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch --editor -- --godot-level-editor-suite-test --task-nodes
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/lanyi/branch --editor -- --godot-level-editor-suite-test --task-nodes --capture
```

[实际任务图截图](任务节点.png) · [节点与接口说明](README.md)
