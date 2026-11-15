# 轮盘 V2 验证 · 2026-11-16

环境：Godot 4.7.1，macOS；实际渲染使用 Metal Forward+ / Apple M4。测试只创建、保存和移除临时测试关卡，不保存覆盖用户关卡。

| 检查 | 结果 | 记录 |
|---|---|---|
| 原生编辑器 headless：轮盘、放置、检查器与存盘 | 84 项通过，0 失败 | [headless.log](headless.log) |
| Metal 实际编辑器及原生视口拾取 | 86 项通过，0 失败 | [metal.log](metal.log) |
| 真实事件执行器：任务对象生命周期 | 22 项通过，0 失败 | [runtime.log](runtime.log) |

悬停问题确认为 bug：原生视口覆盖层可能先于插件 GUI 收到鼠标运动；运行中的编辑器还可能持有旧版本轮盘控件。修复使用窗口 `_input` 先处理轮盘环区，坐标通过完整 canvas 变换转入控件局部空间，兼容展开缩放动画；版本标记改变时仅重建轮盘，不重载场景。测试从最后使用的工具开始，逐一注入六个扇区鼠标事件，检查类别和动画高亮；再使 GUI 忽略轮盘，验证覆盖层路径仍有效。

Metal 测试同步移动测试窗口中的实际鼠标位置，防止引擎后续的原生悬停刷新使用旧指针位置覆盖注入事件。窗口焦点丢失时按产品规则取消轮盘。最终渲染测试日志没有 SCRIPT ERROR 或 ERROR；macOS 输入法服务另有系统 mach port 文字日志。

覆盖内容：

- 侧键短按呼出、松开保持、第二次短按取消；取消动画结束后释放视口。主轮盘六方向、白盒 16 种、滚轮、搜索、边缘定位、二级菜单及返回，删除“放入”选择器。
- 预览在用户场景之外，停用环境、摄像机、处理及碰撞副作用。菜单选择按下不穿透成放置，真实视口左键可以放置。支持连续添加、现有步长、旋转、撤销／重做及按类组织；已选 Room 不改变当前关卡归属。
- NPC 胶囊体的原生点击选择得到 NPC 根及检查器；模型、阵营、默认动作、Room 尺寸和机关场景引用可编辑、撤销、重做。属性和 `EntityProperties` 随关卡保存，派生模型不入盘。
- 真正的 EventDirector 和独立工作簿驱动任务：未激活隐藏、任务开始启用、完成或失败关闭、下一任务对象切换、恢复进度重新同步；任务 Room 和机关一起关闭检测、碰撞及处理；其他关卡的 active 等待任务不生成本关卡对象。常驻对象保留明确的游戏显隐操作。
- 最近使用区分常驻／任务；出生点复用；旧拓扑 Room 起始 ID 与新增一同撤销；组件内部引用保持。测试前后所有目录源 `.tscn` SHA-256 一致。

实际截图：[主轮盘](wheel.png)、[NPC 二级菜单](npc_submenu.png)、[NPC 检查器](npc_inspector.png)、[Room 检查器](room_inspector.png)、[机关检查器](mechanism_inspector.png)。

运行命令：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path /Users/lanyi/branch -- --quick-add-test
/Applications/Godot.app/Contents/MacOS/Godot --editor --path /Users/lanyi/branch --resolution 1600x1000 -- --quick-add-test --capture-quick-add
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch res://tools/level_editor/test_placed_entities.tscn
```

编辑器退出仍有 1 个 ObjectDB／UndoRedo 泄漏警告，V1 中仅启动退出编辑器也已复现；本次没有把它计为整个项目无警告。运行时生命周期测试无错误或警告。模型动画仅播放已有匹配片段，巡逻路径、战斗阵营规则和行为执行为预留接口，未宣称实现。
