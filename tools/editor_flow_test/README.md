# 编辑器流程测试辅助文件

实际案例：`res://scenes/levels/9_editor_flow_test.tscn`。使用原生 F6 及 WASD / F 完成，不需要运行准备脚本。

- `prepare.gd`：首次制作时准备新场景对象、独立台本与没有任何连线的图，作为制作过程留存。已完成的资源存在时会拒绝重跑；不是清空或重置现有样例的工具。
- `session_recorder.gd`：只读观察器，仅附在新测试关卡上。观察真实游戏信号，事件完成后核对 12 项状态，输出 JSON 与完成截图。不会发送交互或推进任务。

完整操作、连线规模与验证边界见 [指南](../../docs/wiki/tutorials/editor-flow-test.md) 和 [验证记录](../../docs/qa/editor_flow_2026-11-17/validation.md)。
