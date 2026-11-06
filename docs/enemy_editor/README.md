# 敌人状态机编辑器

Godot 4.7.1；按 [统一节点工具规范](../tools/BLUEPRINT_TOOLCHAIN.md) 实现。编辑器顶部选择 **敌人状态机**。

## 开始使用

1. 点击“守卫模板”取得四状态副本，或者打开 `res://resources/enemies/guard_default.tres`。
2. 搜索添加预制行为节点；拖动“条件转换”输出到“状态进入”输入，建立真正的运行规则。转换页编辑事件、条件、优先级及效果。条件全部满足（AND）；多条规则可表达 OR。大优先级先判断；同值按列表顺序，可上移/下移。
3. 状态页修改显示名称、行为、移动速度、入场计时及到位张望速度；感知页修改警觉积累、衰减、噪音警觉、暴露惩罚、求援范围和路点停留。稳定 ID 不随显示名称变化。
4. 保存为 `.tres`。在场景树选择守卫，点击“绑定到所选守卫”，再保存 `.tscn`。选择场景守卫会打开对应蓝图；“定位三维守卫”选中关联对象并切到三维视口，可按 F 聚焦。
5. “创建巡逻路点”把旧坐标转成可移动的 Marker3D；展开守卫的路线节点，在三维视口移动路点。运行时读取这些世界位置。场景已有路线时直接编辑它。
6. 打开 `res://scenes/enemy_editor/guard_blueprint_sample.tscn`，F6 运行独立样例。WASD 移动目标、N 制造噪音、Z 回溯两秒、Enter 继续。回到“敌人状态机”页，在运行实例列表观察高亮、计时、警觉和最近转换；悬停查看实际触发条件。该样例不写正式进度。

画布支持平移、缩放、框选、多选、复制粘贴、删除和撤销重做。Ctrl/Cmd+C、V、Z 与 Shift+Z 在画布聚焦时生效。右键空白处打开搜索。节点位置、缩放和平移保存在独立 `layout` 字段，不决定执行顺序，也不改变三维物体位置。

多条转换可共用一根可见连线。拖动断线会删除该线的全部规则，并可整体撤销；只删一条时在转换页选择“删除此转换”。删除节点会连带删除其转换；初始状态须先更换才能删除。场景绑定与路线创建使用 Godot 场景撤销历史，画布内容使用独立历史。

## 数据与运行

- `EnemyDefinition` 是定义资源：四种行为（巡逻、调查、追踪、停留），四类事件（感知、思考、噪音、求援），固定类型端口 `state_enter/state_exit`，白名单事实及比较条件。没有任意代码表达式。
- `EnemyMachine` 是每个实例的运行器；启动时冻结一份私有定义。每次事件至多一次转换，自环也须等待下一事件；同步求援的重入受到保护。图的布局与显示帧率不控制运行结果。
- `GuardAI.enemy_definition` 留空时使用首个模板并沿用原有导出参数。显式赋值后以定义为准。巡逻路径和出生位置仍属于场景。`patrol_route` 有值时优先读取其 Marker3D，未设置则使用原 `patrol_points`。
- 定义是 `.tres`，场景对象、实例 ID、资源引用和巡逻路线是 `.tscn`。实例的状态 ID、计时、最近转换原因进入原有回溯快照，且不包含定义或排版。恢复直接写回状态，不重新扣能量或求援。旧整数状态快照仍可恢复。
- `branch_enemy` 调试通道只从游戏上传数据。高亮按调试会话、实例及定义路径对应；未保存草稿有文字标记。运行定义在启动时固定，保存后重新启动游戏才应用新规则。

## 验证与保存

验证涵盖版本、重复 ID、初始状态、端点、端口类型、条件字段与类型、空条件、非有限数值、负行为参数、画布引用，以及场景巡逻引用。不可达状态和同优先级给出提示。状态循环以显式事件推进，不在一次求值内递归传播。

保存先写同目录临时文件，再替换目标；保留原资源 UID 并把 UID 注册到最终路径。文件被其他编辑器修改时拒绝覆盖，需重载或另存。草稿切换、重载与退出均有未保存提示。保存当前定义及编辑器开始运行前会检查关联守卫的巡逻引用。

## 自动验证

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch res://tools/enemy_editor/test_enemy_editor.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path /Users/lanyi/branch res://scenes/enemy_editor/guard_blueprint_sample.tscn -- --test-enemy-canvas
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path /Users/lanyi/branch --debug-server tcp://127.0.0.1:6017 -- --test-enemy-debugger
```

后两条会自动退出测试编辑器；调试测试启动一个本机子进程，6017 端口需空闲。临时资源与独立测试场景不会覆盖正式场景或存档。结果与集成事项见 [HANDOFF.md](HANDOFF.md)。

API 参考：[GraphEdit](https://docs.godotengine.org/en/stable/classes/class_graphedit.html)、[EditorDebuggerPlugin](https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html)。

## 节点配色与状态提示

敌人 FSM 节点均按持续“状态”归类，标题使用青绿色并写明类别；六类图例与两侧“输入 → / → 输出”帮助辨认。端口、连线的类型颜色独立于节点分类色。活动、选中、暂停、回溯保留分类色，以绿色边框、绿点和状态文字显示当前实例；计时、警觉和转换原因继续可读。详见 [2026-10-31 呈现统一记录](PRESENTATION_2026-10-31.md)。
