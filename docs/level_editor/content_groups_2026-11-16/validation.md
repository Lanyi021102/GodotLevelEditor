# 新增内容分类父节点 · 2026-11-16

实现已完成。用户确认仅处理后续新增内容，已有物件不自动整理。

```text
关卡根节点
├─ NPCs
│  ├─ NPCs
│  └─ NPC2
├─ Rooms
│  └─ PermanentRoom
├─ Mechanisms
│  └─ Mechanism
└─ Whitebox
   ├─ WhiteboxBox
   └─ WhiteboxRamp
```

父节点是无脚本的空 Node3D，首次确认添加时建立，后续同类复用。取消预览不建组；同名业务节点保留并使用唯一分组名称。分组职责保存在 metadata 中，显示名称可以修改。既有根节点物件、出生点和保留光照不批量迁移。

轮盘、侧栏添加、Room 实例化、目录标准文件拖放及复制均接入分组事务。混合素材批量拖入按类别归档，并共享一次原生撤销。分组与实例拥有正确的场景 owner；复制继续分配新实例 ID，恢复用户内容和 EntityProperties 的 ownership，不保存派生预览。

world 和 Room 读取仅展开管理容器，保留原 `$world/object_id` 及 `room_id/object_id` 作用域，不把预制件内部机关提升为世界对象。已验证分组 Room 的实际运行初始化及进入事件、NPC 引用、机关组件及内部 ID 隔离。

新建关卡的初始地面、新建 Room 源场景生成的白盒也进入白盒分组。旧场景在载入时不会自动迁移。

## 检查

Godot 4.7.1。先执行 headless 检查，再使用 macOS Metal Forward+ 实际检查拖放及原生场景树。

| 检查 | 结果 | 记录 |
|---|---:|---|
| 分组与运行时作用域 | 10 / 10 | [日志](groups_runtime.log) |
| 轮盘、预览、配置及保存重开 | 84 / 84 | [日志](quick_add.log) |
| Metal 原生拖放、混合批量、分组及复制撤销 | 14 / 14 | [日志](native_drag.log) |
| 套件编辑器与新建关卡地面 | 78 / 78 | [日志](suite_editor.log) |
| 原生添加、复制、变形及场景保存 | 35 / 35 | [日志](native_editor.log) |
| 关卡运行及图读取 | 82 / 82 | [日志](level_runtime.log) |
| 事件、任务、配表及 NPC 互动 | 49 / 49 | [日志](event_tasks.log) |
| 关卡／任务实体生命周期 | 22 / 22 | [日志](placed_entities.log) |
| 独立关卡试玩 | 15 / 15 | [日志](standalone_play.log) |

实际窗口中的分类父节点与空节点检查器见 [原生编辑器截图](自动分组_原生编辑器.png)。原生拖放检查覆盖首次建组、同类复用、混合批量一次撤销、精确变换重做、NPC 复制后的适配器保存，以及拖放结束后鼠标恢复原生处理。

原生拖放启动命令：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/lanyi/branch --editor -- --warehouse-drag-test --capture-groups
```

用户资源核查见 [校验记录](resource_integrity.json)。工作期间已有的 `scenes/levels/5_adwa.tscn` 另有编辑，保留其当前内容，没有回滚；其余基线资源一致。分组实现没有批量改写关卡文件。测试会话只写入各自临时场景并清理。部分测试退出时仍有既有 debugger 清理／ObjectDB 提示，实际检查没有新的脚本错误。

## 接口及文件

- `addons/godot_level_editor/scene_groups.gd`：分类、容器识别、透明作用域遍历。
- `plugin.gd`：原生撤销新增事务、复制 ownership、全作用域新 ID 检查。
- `asset_drop_tool.gd` / `asset_drop_surface.gd`：原生视口中目录素材的临时拖放接收，非拖放期间忽略鼠标；不增加镜像视口。
- `radial_tool.gd`：复用实例创建和最近使用记录，接入同一个事务。
- `runtime/world.gd` / `runtime/room.gd`：管理层对运行读取透明。
- 套件 `level_warehouse.gd`：新关卡初始白盒归档。

保留了其他聊天同期对面／线／点操作、天空及关卡逻辑所做的修改。检查中为 world 恢复逻辑的动态返回值补充 Dictionary 类型标注，避免当前项目解析失败，没有修改该并行逻辑的处理规则。

撤销接口参考 [Godot EditorUndoRedoManager](https://docs.godotengine.org/en/stable/classes/class_editorundoredomanager.html)。

## 同日英文命名更新

父节点现统一为 `NPCs`、`Rooms`、`Mechanisms`、`Whitebox`。`5_adwa.tscn` 中已有的带标记“机关”容器改名为 `Mechanisms`，并同步其子节点 parent 路径；对照修改前文件，仅这些名称及路径变化，节点 unique_id、object_id、变换和配置逐字保持。业务实例名称不改。

英文命名复查：分组运行与保存 10 / 10、轮盘 84 / 84、Metal 原生拖放／撤销／复制 14 / 14 均通过。记录：[运行](english_groups_runtime.log)、[轮盘](english_groups_quick_add.log)、[原生拖放](english_groups_native_drag.log)。
