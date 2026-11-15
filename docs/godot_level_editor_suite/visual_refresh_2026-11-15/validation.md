# 编辑器浅色界面与方格画布验证 · 2026-11-15

已直接更新当前项目。采用冷灰工作区、白色面板、蓝色强调；缩紧导航、关卡卡片与图工具栏，统一表格、输入框及弹窗，修正窄窗口目录与详情栏裁切。节点采用白色正文，标题职责色及端口类型色保留。卡片悬停仅改变边框与阴影。

## 变更边界

- 仅编辑器 UI、主题与布局：`editor_style.gd`、套件窗口及关卡目录、节点呈现、台本标题、白盒素材卡片。
- 任务、机关、关卡及 NPC 图开启两层方格与画布边框；原吸附开关、步长、缩放、画布位置和连接表不被样式函数改写。
- 为任务节点的自动换行绑定文字设置最小宽度，避免缩放／初次布局时出现过高空白节点。节点位置及图资源不重排。
- 不修改运行脚本、配表格式、场景结构或用户资源。既有试玩窗口显隐规则保留。
- 与修改前记录的 55 个已有场景、资源及 XLSX 文件逐一比较 SHA-256，全部一致，见 [校验记录](resource_integrity.json)。

## 检查结果

Godot 4.7.1；headless 先检查，随后使用 macOS Metal 4.0 / Forward+ 实际渲染。

| 检查 | 结果 | 日志 |
|---|---:|---|
| 套件编辑器 headless | 54 / 54 | [日志](editor_headless.log) |
| 套件实际渲染与布局 | 62 / 62 | [日志](editor_metal.log) |
| 事件任务及 XLSX 运行 | 49 / 49 | [日志](task_runtime.log) |
| 节点类型、端口、运行显示与数据不变性 | 139 / 139 | [日志](node_presentation.log) |
| 机关运行 | 48 / 48 | [日志](mechanism_runtime.log) |
| 敌人运行 | 45 / 45 | [日志](enemy_runtime.log) |
| NPC 画布编辑、连线、撤销和场景绑定 | 42 / 42 | [日志](enemy_canvas.log) |
| 五类仓库素材向原生三维视口拖放 | 5 / 5 | [日志](native_drag.log) |
| 实际 F5／F6 试玩与工作窗口焦点 | 15 / 15 | [日志](play_focus.log) |

渲染检查覆盖六个模块的 1504 × 1000 窗口、1100 × 760 窄窗口、四列／三列卡片、详情操作、新建任务弹窗及各仓库页面。NPC 专项使用其文档规定的 `scenes/enemy_editor/guard_blueprint_sample.tscn` 启动。测试进程退出时仍有既有的 `Plugin is not attached to debugger` 清理日志；运行及渲染过程中没有新的脚本错误。Windows 系统窗口及字体未在本机实际渲染。

## 预览

- [我的关卡](我的关卡.png)、[窄窗口](我的关卡_窄窗口.png)
- [任务图](任务图.png)、[机关图](机关.png)、[NPC 图](敌人.png)、[关卡图](关卡编辑.png)
- [事件与任务](事件与任务.png)、[台本](台本.png)、[新建任务](新建任务.png)
- [白盒仓库](仓库_Layout%20白盒.png)

实际渲染命令：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/lanyi/branch --editor -- --godot-level-editor-suite-test --capture --capture-dir=res://docs/godot_level_editor_suite/visual_refresh_2026-11-15
```

保存当前编辑内容后，重新打开项目可完整重建主题及窗口。节点图缩放和滚动继续使用原生操作；图过大时可使用已有的适合画布／适应图按钮。
