# 机关与 NPC 目录导航 · 2026-11-15

关卡、机关和 NPC 一级按钮统一先进入“我的…”目录。单击卡片只更新选择与详情；双击或点击“进入编辑”才打开具体资源，二级编辑页签恢复当前已打开的资源。目录包含搜索、刷新、新建卡片，未打开资源时禁用编辑页签。缺少缩略图时显示类型示意图。

套件以 `asset_workspace.gd` 托管原机关及 NPC 面板，编辑栏隐藏重复的新建／打开入口；禁用套件后恢复独立模块按钮。机关保持场景与图的成对保存，保存冲突阻止切换；NPC 保持原草稿确认，取消后保留草稿，成功载入后才进入目标编辑页。目录刷新重新读取磁盘，保存名称后立即更新卡片。

目录范围：机关为 `scenes/mechanisms/` 中的 Assembly 组合；NPC 为 `resources/enemies/` 中的 EnemyDefinition。单体机关和中立 NPC 场景继续在原生三维视口及关卡素材仓库编辑。没有引入目录配表或修改运行数据格式。

## 验证

在临时工程副本 `/tmp/branch-asset-navigation-AIYjkI` 内执行，避免测试操作影响正在打开的工作项目。

- Headless 编辑器：**78 项通过，0 失败**，见 [日志](headless.log)。
- Metal 实际渲染：**88 项通过，0 失败**，见 [日志](metal.log)。检查标准 1504 × 1000、窄窗口 1100 × 760，截图已人工查看。
- 覆盖单击与双击、一级／二级导航互斥、恢复当前草稿、NPC 取消／确认切换、机关保存冲突、新建资源、重复文件保护、保存后目录刷新、原生场景切换及现有任务／关卡回归。
- 本轮没有脚本解析错误。Headless 退出日志仍有原有 debugger 清理提示，两个渲染模式退出时均保留 1 个 ObjectDB 实例的清理警告。
- 56 份既有场景、资源与配表做 SHA-256 对照，55 份一致。工作期间白盒关卡仅出现相机子资源自动 ID 及对应引用的重新序列化，参数和结构一致；保留当前文件。测试新资源仅在副本中创建并删除。详见 [资源对照](resource_integrity.json)。

命令（在临时副本运行）：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /tmp/branch-asset-navigation-AIYjkI --editor -- --godot-level-editor-suite-test
/Applications/Godot.app/Contents/MacOS/Godot --path /tmp/branch-asset-navigation-AIYjkI --editor -- --godot-level-editor-suite-test --capture --capture-dir=res://docs/godot_level_editor_suite/asset_navigation_2026-11-15
```

## 截图

[我的机关](我的机关.png) · [我的 NPC](我的NPC.png) · [机关编辑](机关编辑.png) · [NPC 编辑](NPC编辑.png) · [机关窄窗口](我的机关_窄窗口.png) · [NPC 窄窗口](我的NPC_窄窗口.png)
