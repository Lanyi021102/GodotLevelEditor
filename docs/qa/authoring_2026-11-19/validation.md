# 0.2.0-preview 制作流程验证

2026-11-19，macOS，Godot 4.7.1。测试使用插件空工程和开发工程的独立副本。工作台流程在运行前后核对源工程中每个 `content/` 文件的 SHA-256。

## 入口和目录

| 环境 | 结果 | 实际覆盖 |
|---|---|---|
| 插件空工程，headless | 18/18 | 工作台按需加载、新建继承关卡、原生另存、继续上次关卡、分别进入原生场景与常驻逻辑、素材来源与空选中、点击事件行添加任务 |
| 开发工程副本，Metal Forward+ | 27/27 | 上述操作，另检查 8 个天空预设的真实缩略图尺寸、图像差异及实际窗口画面 |
| 插件空工程，原生结构回归 | 37/37 | 继承、另存、关卡与图身份、重开、运行、移动与清理路径 |

事件行检查通过窗口输入队列送入鼠标按下和释放。三次运行均未改变源工程作品。Godot 4.7.1 关闭编辑器时出现既有的调试器分离提示，详见运行器对该单条诊断的处理。

[工作台截图](workbench.png) · [天空预设截图](sky-library.png) · [工作台操作](../../wiki/guides/workbench.md)

## 两个可以自己做的练习

- [让按钮打开指定的门](../../wiki/tutorials/button-door.md#wire-button)。隔离工程两次运行同一张关卡，第一次只有门 A 打开，重新绑定后只有门 B 打开。[两次运行的状态记录](../../level_editor/measurement_2026-11-19/button-door.txt)
- [和居民交谈后进入区域](../../wiki/guides/npc-samples.md#first-conversation-task)。在关卡里允许巡逻 NPC 交谈，用 F 启动对白和接取任务，再进入目标触发区域。该专项在 headless 和 Metal 各通过 17 项，也检查了两名居民和交互点相邻时提示与实际目标的一致性。[NPC 运行记录与截图](../../enemy_editor/conversation_2026-11-19/validation.md)

## 原生视口与台本

白盒尺寸和表面拾取在 headless 与 Metal 各通过 59 项，轮盘与放置通过 118 项。[测距截图、步骤与结果](../../level_editor/measurement_2026-11-19/validation.md)

对白面板通过 59 项，任务工具栏与节点定位通过 34 项，任务节点执行通过 94 项。使用 openpyxl 生成含附加工作表、批注、样式、数字和公式的工作簿，修改对白后逐项对比压缩包，只有目标工作表的 XML 有变化。从另一张地图发起任务试玩，Godot 启动任务所属地图；收到运行调试数据后，点击等待记录可以定位节点。旧格式对白兼容性另查 34 项通过。[数据保存与任务试玩验证](../../narrative_editor/authoring_2026-11-19/validation.md)

## 运行与安装包

10 组运行场景共通过 423 项。覆盖事件与配表、天空、触发区域、关卡常驻逻辑、NPC 定义与交谈、独立机关、旋转门、对白模式和任务节点。旧版台本缺少对话模式列的回归在修复表头只读问题后重新通过。

本地安装包 `GodotLevelEditor-0.2.0-preview.zip` 含 523 个插件文件及清单。已比对 ZIP 和工作区插件文件的 SHA-256。在独立宿主中全新安装通过 56 项，替换插件后通过 49 项，已有的 4 个作品文件哈希一致。Metal 编辑器安装检查通过 50 项。另在空工程启用后运行默认 F5，并检查了角色控制和实际画面。

双语 Wiki 检查覆盖 42 页。另用 Chromium 实际打开中英文快速开始、两个练习、工作台和天空指南，共 10 个页面视图。中文在 1360 像素桌面宽度、英文在 390 像素移动宽度验证，练习锚点存在，新截图正常载入，页面无横向溢出。

## 复测命令

在项目根目录运行：

```sh
python3 tools/qa/run_structure_flow.py --authoring --consumer --output /tmp/gle-authoring-consumer
python3 tools/qa/run_structure_flow.py --authoring --render --output /tmp/gle-authoring-visual
python3 tools/qa/run_structure_flow.py --consumer --output /tmp/gle-structure-consumer
python3 tools/wiki/wiki.py check
```

上述流程的输入来自 Godot 输入队列或测试工具。测量与缩略图的图形检查在 macOS 完成。
