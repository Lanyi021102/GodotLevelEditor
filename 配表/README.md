# 配表

- levels.xlsx：关卡、配置工作表；关卡页保存 ID、名称、中文名、场景路径和可选备注／缩略图路径，关卡场景统一位于 scenes/levels/。
- events.xlsx：版本 2，事件、任务、配置三个工作表；每个任务必填唯一 level_id，事件不绑定关卡。
- dialogues.xlsx：对话组、Comments、对白、角色、配置五个工作表。

工作簿是编辑器和游戏共同的数据源。ID 列保留文本格式，不手动重编号；order 控制顺序。配置页用于保存版本和下一次分配计数，不删除。

在 Excel 修改后关闭文件，在插件中重新打开或重新读取。配表使用直接值，不执行公式。字段说明和编辑操作见 ../docs/godot_level_editor_suite/README.md。
