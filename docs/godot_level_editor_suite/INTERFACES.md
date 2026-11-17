## 插件目录与原生场景合同 · 2026-11-17

插件本体、示例素材和运行依赖统一到 `addons/godot_level_editor/`；各模块代码在其中的 `modules/`。作者地图、配表与个人资源迁入 `content/`，已有稳定 ID 与 UID 保留；路径迁移表见 `tools/release/layout-migration.json`。

地图采用 Godot 原生文件系统、场景树、保存与 F6，保留轮盘、白盒、点线面和场景对象绑定。独立窗口“关卡”只显示当前场景的常驻图，旧“我的关卡”卡片／删除流程不再是当前入口。原生保存通过 native_level_registry 登记任务所需 ID，地图路径允许插件目录以外的项目目录。

主插件负责内部模块生命周期和缺省输入／配表初始化；运行服务使用 GLELightZones、GLENoiseBus、GLESaveSystem。用户主场景、已有输入和作者作品不由插件更新覆盖。下面的旧路径和目录入口仅记录当时合同；当前布局与实际验证见 [迁移记录](../cleanup/plugin_2026-11-17/validation.md) 和 [安装指南](../wiki/plugin-install.md)。

> 当前关卡接口（2026-11-16）：关卡编辑使用整关常驻逻辑图，素材添加由三维轮盘负责；“接受任务”接取首项后自动串行后续任务。此前阶段移除的是旧房间接驳图。详见文末常驻逻辑合同与验证。

2026-11-16 用户确认移除原生“关卡摆放”旧侧栏及其专属入口／卡片代码；轮盘、点线面、步长、检查器、原生复制和保存保持。此前有关“白盒侧栏保持原位”的段落仅记录当时状态，当前合同及实测见 [侧栏移除验证](../level_editor/placement_dock_removed_2026-11-16/validation.md)。

## 启动与页面按需初始化 · 2026-11-16

工程清理与本机验证副本的归档规则见 [2026-11-16 清理记录](../cleanup/project_hygiene_2026-11-16/validation.md)。本轮保留套件目录、元数据缓存、全部用户资源与迁移接口，清除的文档图片 `.import` 位于已排除的 `docs/` 下，不影响封面缓存或游戏资源导入。

`plugin._enter_tree()` 只注册套件入口、天空导出与关卡缩略图服务，不创建独立窗口和全部页面。四个原生后端、轮盘／视口工具、调试器、机关原生保存保护仍按原有启动顺序注册；原生保存与 F5/F6 不因窗口尚未创建而触发 UI 初始化。

`show_window()` 和 `open_tab(name)` 首次请求时建立窗口与九个导航目标，初始显示工作台。`_ensure_page(title)` 首次访问时创建该页面或托管已有后端 Control，此后复用同一实例。`tabs` 的分类子项是页面容器；`task_graph` 仍指向原台本模块后端，`level_panel/event_panel/sky_panel` 和 `asset_panels` 仅在对应页面准备后可用。跨模块调用应先 `open_tab`，需要检查完整布局的工具可显式调用 `prepare_all_pages()`。保存、退出和缩略图回调均兼容未访问的空页面；关卡变化只更新已经初始化的事件表，未访问的事件表首次读取最新工作簿。

天空先于关卡打开时，直接读取关卡目录元数据以显示当前关卡中文名，不为此初始化关卡界面；后续优先复用已初始化的关卡目录。

既有专项命令通过 `TEST_ARGUMENTS` 显式准备全部页面以兼容其直接访问；`--startup-lazy-test` 则沿正常按需路径验证，不能加入该预热名单。原生已打开的机关场景／NPC 定义在首次创建目录包装器时同步，不依赖下一次切换信号。首次访问某分类仍有一次初始化成本，重复访问继续沿用导航缓存。

`asset_workspace` 在 `.godot/godot_level_editor_suite/{mechanisms,npcs}_catalog.json` 保存纯目录元数据（不保存 Resource / Texture），保留源目录项顺序。首次创建目录时先检查版本、分类、行结构和所有输入内容指纹；一致则不加载定义／模型，变更或缓存损坏则从源资源重建。指纹包含目录实现脚本，避免新代码复用旧元数据；手动“刷新”始终从源资源读取并更新缓存。缓存可删除重建，不改游戏资源和工作簿，不纳入导出。

测量工具 `tools/godot_level_editor_suite/run_startup_profile.py` 在独立副本中注入计时，记录插件注册、窗口准备、首轮稳定帧与首次访问各页的耗时，不向生产脚本插入计时代码。功能、性能与实际渲染检查见 [启动验证](startup_2026-11-16/validation.md)。

## 删除关卡与场景文件 · 2026-11-16

用户确认改为删除关卡记录和对应 `.tscn`。`level_warehouse._ask_delete` 冻结待删除行，确认框明确显示名称、ID、场景路径及系统废纸篓去向；取消清理目标，不改数据，默认聚焦“取消”。确认通过 `_confirm_delete` 调用 `delete_selected(id, expected_path)`；对话框打开后切换选择不改变目标，磁盘目录中的路径变化则要求重新确认。

继续先成功读取事件工作簿并检查任务引用，再读取最新关卡目录，校验目标在 `scenes/levels` 内且为规范 `.tscn` 路径。`_scene_dependents` 递归检查项目中可扫描 `.tscn/.tres/.scn/.res` 的显式资源依赖，排除隐藏目录、`.gdignore` 及目录软链接，支持 UID 解析；发现引用时列出来源并拒绝删除。代码中的动态字符串加载不属于此依赖检查。

原生未保存场景和当前关卡图草稿阻止删除；已保存的打开标签先关闭，避免之后保存时重建已删除文件。最新目录先写入成功才调用 `OS.move_to_trash` 移走单个场景，失败恢复目录行；回滚失败单独报告。成功后在 `user://level_archive/<id>.json` 记录原行，更新原生文件系统及目录，发出一次 `levels_changed`。稳定 ID 不回收，外部图、NPC、机关、台本及图片不连带删除。缩略图队列在捕获前重新检查目录，跳过已删除关卡。

操作见 [关卡指南](../wiki/guides/levels.md#copy-delete)，检查与真实确认框见 [删除验证](level_delete_2026-11-16/validation.md)。本节覆盖旧版“仅移除目录、保留场景”的行为。

## 保存后更新关卡缩略图 · 2026-11-16

套件 `plugin.gd` 在进入树时创建 `level_preview.gd` 服务，监听原生 `EditorPlugin.scene_saved(scene_path)`。只匹配 `levels.xlsx` 中登记的关卡场景；场景保存成功后才请求生成，不额外保存场景。`level_warehouse.level_created(scene_path)` 在新场景与目录写入均成功后触发同一请求。退出插件时 `dispose()` 取消生成和队列。

服务按场景路径合并待处理请求、串行渲染；生成期间再次保存时丢弃旧结果，继续处理最新磁盘内容。私有 `SubViewport` 使用独立 World3D，禁用副本处理与原场景天空、灯光、雾及二维覆盖，隐藏 Room 编辑边框和 Label3D，保留实体模型。实际可见 MeshInstance3D、MultiMeshInstance3D、CSGShape3D 的变换包围盒确定取景；固定方向 `(1.1, 1.0, 1.4)` 的正交相机按八角投影与 16:9 比例留边，输出 1024×576 PNG。原场景、图与原生相机保持。

PNG 临时文件成功写入后替换 `resources/level_previews/<level_id>.png`。发布前重读最新工作簿，确认 ID 与场景仍匹配，只在路径改变时更新 `preview_path`，保留其他元数据。自定义旧图片不删除。失败通过 `preview_failed(scene_path, reason)` 和 Godot 警告报告，不阻止场景保存；headless 不请求图像或改写预览。

`preview_updated(level_id, scene_path, preview_path, texture)` 交给 `level_warehouse.apply_level_preview` 局部更新现存卡片和当前详情，不重建目录。`level_card.set_preview` 清除该路径旧缓存并阻止迟到的原生预览回调覆盖新图；详情使用相同保护。其他素材卡片、导航、搜索、选择、布局与内容哈希缓存继续兼容。既有 `--capture-level-previews` 工具复用同一服务，需实际图形渲染。

操作见 [关卡指南](../wiki/guides/levels.md#level-thumbnail)，检查与实际图像见 [本轮验证](level_preview_2026-11-16/validation.md)。

## 页面切换性能 · 2026-11-16

- 一级导航使用 `asset_workspace.ensure_catalog()` 复用现有卡片；窗口已经显示并具有焦点时，`open_tab` 不再重复 show、grab_focus 或刷新旧页面导航，程序化调用仍可唤回失焦窗口。`select_navigation` 仅在选中状态实际变化时切换字重，保留既有按钮与图标动画。
- `filesystem_changed` 标记目录待检查。隐藏目录／编辑页延后处理，显示目录或返回“我的…”页时才检查；连续通知合并，相关场景、定义或封面内容没有变化时不重载。`reload_catalog()` 继续作为手动刷新、创建与保存后的强制读取入口。
- 指纹包含本分类 `.tscn/.tres`、已知外部图定义及封面。内容哈希可识别同秒、同文件大小的修改；不因无关脚本／截图修改而重建目录。实际资源变化后仍读取磁盘元数据，保留草稿与资源切换保护。
- 普通机关场景通过 `SceneState` 读取根脚本和图定义，不为列目录实例化整份场景；外部定义单独忽略缓存读取，普通场景不再使用 `CACHE_MODE_IGNORE_DEEP` 重载全部模型／贴图依赖。继承场景保留深度读取与实例化回退以保证嵌入定义和覆盖项最新，组件场景不收录。
- `level_card.preview_texture(path)` 为关卡／机关／NPC 卡片与详情共用解码纹理，以图片内容哈希失效。缓存最多 64 张，插件退出时清空；单张最长边 768 像素，适配当前卡片／详情的 Retina 显示。文件删除或读取失败返回 null，维持原占位／资源预览流程。
- `display_adapter` 延后绑定动态按钮时使用弱引用；同帧已释放或已移出窗口的按钮跳过处理，避免重建图／表格时的失效对象参数错误。

测试入口 `--editor -- --navigation-performance-test` 在副本中采样七类导航，各重复 12 次，并验证新增、修改、删除、继承场景和图片缓存失效；`--baseline` 只采样，`--capture` 保存实际页面截图。耗时区分同步回调与等待下一帧，不把它们混为完整显示延迟。实测见 [切换性能验证](navigation_performance_2026-11-16/validation.md)。

## 文档图片导入边界 · 2026-11-16

`docs/.gdignore` 排除文档目录的 Godot 扫描／资源导入；`tools/wiki/hooks.py:on_pre_build` 在 MkDocs 输出目录自动生成同名标记，重建网站期间继续保留。文档截图不是游戏资源，不可通过 `ResourceLoader` 作为场景依赖；现有截图工具的 `FileAccess`／`Image.save_png` 路径及工作台系统打开 Wiki 的路径继续可用。`assets/`、`resources/` 和插件图标不排除，保留游戏贴图与素材预览的正常导入和 `.godot/` 缓存。目录卡片加载逻辑本次不改。

说明见 [常见问题](../wiki/faq.md#image-import)，本次检查见 [验证记录](import_filter_2026-11-16/validation.md)。

## QA 删除保护与任务绑定检查合同 · 2026-11-16

- QA-10：`level_warehouse.delete_selected()` 仅在事件工作簿成功读取后检查任务引用；读取有错误或目录为空时停止删除，保留关卡目录并显示读取错误。被任务引用仍拒绝删除，无引用且读表成功才可继续删除；用户确认后的实际文件删除行为见本页“删除关卡与场景文件”。
- QA-06：事件接取／启动前和当前任务 runner 附加前，共用台本模块 `runtime/task_bindings.gd` 检查所属关卡中的 NPC / Room 绑定。缺失目标记录错误并拒绝该图运行；任务不在当前关卡时沿用暂停／续接，不用当前关卡对象误判外关卡引用。合法的当前任务对象即使尚未显示，也不能仅凭可见性判为缺失。
- 拒绝启动时通过 `task_binding_errors`、`accept_task` 的原因和 `task_graph_rejected` 信号公开错误，HUD 显示“无法开始任务”及具体目标。服务 `valid` 仍表示工作簿和宿主有效，不能把单个任务引用错误扩展为所有合法任务不可用。
- 任务图与工作簿格式、稳定 ID 和任务顺序保持。现有任务 HUD、完成动画及其他窗口已落地的显示改动继续保留。

模块专项与总控独立整合检查已通过，分别采用最终日志与源码快照，见 [本轮 QA 记录](../qa/bugfix_2026-11-16/validation.md)；中间测试副本及其旧失败记录保留追溯。

# 浅色界面覆盖说明 · 2026-11-15

## Retina、导航图标与布局更新 · 2026-11-16

### 宋体与字段身份配色

`resources/ui/songti_font.gd` 统一解析本机宋体／Songti，正文与导航分别保留原有字号、400／700 字重和 MSDF 设置。字体集合先选择字形面再提供数据，避免本机 Songti.ttc 的首个 Black 字形面及其较小中文字库被缓存为常规体；符号使用独立回退字体补齐。系统字体只在本机读取，不复制进工程。项目默认字体和 HUD 主题使用同一宋体资源，轮盘与曲线文字继承编辑器字体。现有布局、颜色、导航动画和图语义保持。

`identity_colors.gd` 仅在事件表第 3 列“所属关卡”和台本第 1 列“NPC 姓名”绘制实色填充标签，按文字实际宽度收紧。色板采用蓝、青、紫色系，包含深色与浅色填充；`text_color(background)` 按线性相对亮度比较白字与深灰字的对比度，选取较清晰的一种，并通过单元格原生文字色覆盖保证选中行仍可读。原生 Tree 继续绘制文字、选中行，并裁切滚动内容；只读单元格切换为 `CELL_MODE_CUSTOM` 时保留原文字，字体、字号、字重保持。以关卡稳定 ID 或完整 NPC 姓名决定颜色；同标识同色，多关卡事件使用排序后的 ID 集合。色板有限，较多标识时允许复用。不会更改配表的名字、角色颜色或运行时台词配色。实际检查与截图见 [实色标签验证](filled_labels_2026-11-16/validation.md)。

共享主题的 `PopupMenu`、`PopupPanel`、`TooltipPanel` 和 `AcceptDialog` 外层面板完整绘制浅色背景与直角外沿，派生文件／确认弹窗沿用；内部按钮和页面卡片圆角保持。`display_adapter` 在窗口加入树时同步配置 Popup 的原生／Viewport 不透明背景，覆盖引擎同帧生成并打开的 tooltip、动态右键菜单、下拉菜单和颜色选择器，不依赖项目透明窗口开关或系统合成支持。不修改游戏窗口背景、模态／焦点策略或资源数据。各类弹出层实际渲染检查见同一验证记录。

### 工作台与图标手势

一级导航最左侧新增“工作台”，使用 Open Room 标志的单色版本 `navigation/home.svg`，不改变原生插件入口的品牌图标。`home_panel.gd` 提供本项目本机偏好（自动／100%–300% 界面缩放、动画开关、恢复默认）、在线／本地 Wiki 和制作入口。`ui_scale=0` 为自动，非零值优先于系统及原生编辑器比例；与 `animations_enabled` 一起仅写 EditorSettings 项目 metadata，不写场景或工作簿。缩放变更立即重排，`display_adapter.scale_changed` 更新当前比例显示。

`navigation_icon.gd` 为一级 Button 保留原 icon 的布局占位，将其图形层交给鼠标忽略的 TextureRect 显示；正文和按钮的几何保持。按功能分别提供轻浮、弹动、齿轮转动、对话摇摆、人物点动、天空飘动和网格弹性。`select_navigation` 的状态变化触发一次进入／退出手势；pressed 单独支持重复点击当前页，同一帧去重。快速切换取消旧 Tween，结束归位；隐藏窗口和禁用动画时停止并复位，单色随选中状态同步。

操作见 [工作台指南](../wiki/guides/workbench.md)，检查和实际动图见 [导航动效验证](navigation_motion_2026-11-16/validation.md)。

`display_adapter.gd` 对独立窗口统一设置 `content_scale_factor`，默认读取窗口所在屏幕的系统缩放；手动选择的 Godot 编辑器缩放优先。Mac Retina 2×、普通屏 1×及分数缩放只应用一次，字体、间距、图标与命中区域共享同一逻辑坐标。`dpi_changed`、重新聚焦与跨屏检测更新比例，窗口尺寸限制在屏幕可用区域；弹窗包括新建的子 Window 同步缩放，不改运行场景或 HUD。

基础字号为 16 逻辑像素。套件正文、GraphNode 标题、导航字重和 RichTextLabel 使用 MSDF 系统字体，GraphEdit 放大时保持文字边缘清晰。原生图 zoom／scroll／端口、节点 ID 与图数据不改变。一级导航使用 `assets/branding/navigation/` 单色 SVG，图标在上、文字在下；同一透明图标按状态着色，选中使用白色。

`ui_motion.gd` 提供按钮悬停、焦点、按下及选中状态的私有 StyleBox 过渡，以及分层淡入。隐藏／退出树清理 Tween，快速切换不累积。动画不移动命中区域，不增加 GraphNode 子控件；节点选中仍使用原有边框与阴影反馈。新建与动态按钮仅绑定一次。

关卡目录增加标题、数量和搜索，自适应卡片列数及预览比例；缺失预览使用内存生成的白盒示意图。详情正文可滚动，底部操作固定可见。台本以实际字体测量 ID 与姓名列宽，保留完整文字提示，另有选中对白的换行阅读区；搜索无匹配时不允许编辑隐藏的旧选择。现有目录 CRUD、XLSX 编辑、保存与撤销接口保持。

使用说明见 [界面显示](../wiki/faq.md#display-scaling)，实际检查与截图见 [显示更新验证](display_refresh_2026-11-16/validation.md)。

2026-11-15 资源导航更新：关卡、机关、NPC 一级按钮均回到各自“我的…”目录。`asset_workspace.gd` 通过 `asset_panels["机关"/"敌人"]` 托管机关和 NPC 的两层页面，原模块面板仅移动到 `editor_host`，图格式、撤销归属、保存与运行逻辑保持。`open_tab("机关"/"敌人")` 保留程序化页面导航；一级按钮额外切回目录。二级栏及分隔线按当前分类互斥显示。

目录读取机关组合 `.tscn` 与 NPC `EnemyDefinition .tres`，路径作为目录项键，不引入配表或新资源 ID。单击只更新选择；双击／进入编辑打开资源；编辑页签只恢复已打开的资源，不加载仅被选中的卡片。NPC 新增 `definition_opened(path)` 在成功载入后发出，目录仅在目标实际打开后进入编辑，沿用已有草稿确认。机关切换前调用原保存接口，保存冲突阻止切换；原生场景切走时回到目录。目录重载使用不复用缓存的资源读取，保存后更新名称与统计。

模块新增 `library_actions: Array[Button]`：仅在套件托管期间隐藏编辑栏的新建／打开／示例入口，禁用套件时恢复；新建通过目录使用原 Store 写入，拒绝覆盖同名文件。`level_card` 增加可选 `new_title`、`metadata`、`fallback_icon`，现有关卡数据和交互保持兼容。资源没有预览时显示类型示意图。接口与验证见 [资源导航记录](asset_navigation_2026-11-15/validation.md)。

套件采用冷灰工作区、白色面板和蓝色强调。此说明覆盖下文历史的米白页头、蓝金渐变卡片与缩放动效约定。现有数据、运行接口、模块归属、撤销与原生三维视口边界不变。

- 一级导航为实蓝选中底和白字，二级页签为透明底、蓝字及底部指示线；中间分隔线只在关卡／任务子导航可见时显示。页头移除重复产品名；原生系统窗口标题保留。`navigation(button, height, primary)` 默认一级，关卡及任务子导航传入 `primary=false`。仅呈现调整，原有 `open_tab`、按钮映射与互斥选中保持。
- `select_navigation(Button, selected)` 统一维护互斥状态、选中字重和短时动画；调用者继续使用原页面映射。`navigation` 本身不监听会重复触发切换的 pressed 信号。`tab_motion` 对子页淡入只连接一次。图节点选中动效只复制 `panel_selected` 的 StyleBox 并动画其阴影，不增加 GraphNode 子控件，不改变端口索引、类别填色、运行绿色边框或图资源。连续选中取消旧 Tween，隐藏的导航及卡片复位。
- `editor_style.gd` 集中提供主题、导航及 `graph_canvas(GraphEdit)`；`workspace(Control)` 在模块进入套件窗口时统一应用画布与表格样式。
- `graph_canvas` 开启双层方格显示，设置画布边框及线条外观；不修改 `snapping_enabled/snapping_distance`、zoom、scroll_offset 或连接表。主网格间距仍由 Godot 原生规则决定。
- 关卡目录缩窄时减少列数，详情栏保持可见；卡片悬停仅改变边框及阴影，不改变缩放或命中区域。现有点击选择、双击进入、素材拖放和参数修改继续使用原调用。
- 节点正文改为白色；职责分类色、端口 ID、顺序、类型和颜色保留，选中边框使用蓝色，运行活动边框继续使用绿色。
- 白盒素材卡片按继承主题显示浅色；Godot 原生深色侧栏保持深色呈现。运行场景、HUD、关卡、机关、台本和 XLSX 内容未修改。
- 验证与截图见 [2026-11-15 视觉更新验证](visual_refresh_2026-11-15/validation.md)。

# GodotLevelEditor 窗口与事件任务接口 · 2026-11-12

2026-11-16 轮盘 V2：素材选择与放置归属原生关卡插件，独立窗口使用下文“常驻关卡逻辑与任务接取”合同，不再重复提供五类仓库。鼠标侧键短按切换轮盘；NPC、机关、Room 提供常驻／任务二级菜单和原生实例检查器。事件执行器注册 `godot_level_editor_task_directors` 组，供实例适配器按 world、level_id 和 task_states 判断任务对象存在性；不另建任务状态来源，不改工作簿 schema。详见 [轮盘 V2](../level_editor/quick_add_v2_2026-11-15/README.md)。

## 插件归属

轮盘预览复用（2026-11-16）：原生轮盘的素材库和最近使用调用套件 `level_card.preview_texture`，NPC 读取与我的 NPC 相同的定义 metadata 预览路径，机关读取我的机关使用的同名预览 PNG。路径来源、缓存内容哈希与更新保持同一语义，不复制图片或增设缩略图数据源。详见 [验证](../level_editor/asset_thumbnails_2026-11-16/validation.md)。

`addons/godot_level_editor_suite/plugin.gd` 是统一入口。四个已有 EditorPlugin 作为模块保留原生注册和调试／撤销接口，加入 godot_level_editor_suite_modules 分组并通过 godot_level_editor_module 标识。启用套件后隐藏各模块主界面入口，统一窗口托管其 Control；不复制定义或场景数据。

窗口为 Window(force_native=true, transient=false)，主题从 EditorInterface.get_editor_theme 合并原生资源后覆盖套件配色、字号和样式。面板暂时移动时用 godot_level_editor_reparenting 标记保护 _exit_tree 的撤销历史清理；关闭窗口仅隐藏，禁用插件时将模块控件恢复原父级。图端口和资源格式保持兼容。

2026-11-15 试玩窗口更新：F5/F6 保留工作窗口现有可见性，_build 和运行开始只隐藏未提交弹窗以解除模态焦点。_make_visible 在启动及运行期间不调用 show_window，不自动抢焦点或切换页面。手动关闭后保持关闭，显式菜单仍可打开；编辑数据和撤销历史保留。play_focus_test 分别实际启动 F5 主场景和 F6 用户关卡，headless 与 Metal 均通过 15 项。

2026-11-13 导航改版：镜像三维页及 level_workspace.gd 已删除，Godot 原生视口与白盒侧栏保持原位。外层 TabContainer 隐藏内置标签，托管七个页面；六个矩形按钮对应关卡、任务、机关、台本、NPC、其他。任务包含事件与任务、任务图两个子页。open_tab 继续使用原子页名称，关卡图映射到关卡编辑的图子页。选中状态由 tab_changed 更新，中蓝 #5b93bf、深蓝 #132d68、白色文字、米白 #fff0d8 页头。初始尺寸 1504×1000，之后保存用户尺寸。

文件归属：套件、工作簿适配器和事件执行器在 addons/godot_level_editor_suite；台本继续在 addons/godot_level_editor_narrative；原有 level/mechanism/enemy 模块仅改统一窗口接入、移动保护和呈现简化。原有房间、机关、光照、基础玩家和空白主入口保持。

## 工作簿接口

`runtime/xlsx.gd` 使用 ZIPReader/ZIPPacker 和 XMLParser 读写标准 OOXML 工作簿，不依赖 Excel、Python、Node 或第三方运行包。read_book 返回 {sheets, errors}；records 检查必需表头；write_book 写临时文件后替换目标。

支持 sharedStrings、inlineStr、文本／数值直接值、Unicode、转义、前导零和分表。遇到公式、丢失工作表／表头或错误版本拒绝运行，不静默降级到 CSV。

`event_catalog.gd` 配表 schema 2：

- 事件页：event_id, name, display_name, notes, order, start_type, start_key。
- 任务页：task_id, event_id, name, display_name, notes, order, graph_path, level_id。
- 配置页：version, next_event_id, next_task:<event_id>。

event_id >=1001；任务 ID 拼接所属事件 ID 和至少三位后缀。ID 不随排序、撤销或删除回退重用。任务到事件的关系通过 event_id 明确存储。程序名与显示名分别存储；顺序必须为非负且在各自作用域唯一。

台本 XLSX 页结构见 narrative_editor/INTERFACES.md。图资源引用 dialogue_xlsx，默认 res://配表/dialogues.xlsx。task_definition.table_file/load_dialogue 只读 XLSX。

## 事件执行器

Room 触发区域更新（2026-11-16）：`_connect_world` 连接 Room 的 `player_entered/player_exited`，分别广播 `room_enter/room_exit` 到常驻 runner 和当前有效任务 runner。`task_actions.condition` 为 `room_active` 读取实际 `Room.is_active()`，没有独立影子状态。任务生命周期通过实例适配器关闭检测并清除状态；重新启用检测时可以处理已经位于箱内的玩家。完整合同与测试见 [Room 触发区域](../level_editor/room_triggers_2026-11-16/validation.md)。

`event_director.gd`：world_path 指定世界，workbook 指定事件工作簿。start_type 支持 manual / room_enter / event_received / game_start。start_event 接受事件 ID 或程序名，publish_event(key) 投递具名事件。

一个事件只配置一个当前任务执行器，不把未来任务加入触发队列；不同事件按稳定 ID 顺序推进。现有 event_runner 仍负责每图 64 个事件／帧、队列限制、具名端口和实际动作。任务完成先标记，等当前事件批次清空后才切换到下一任务，避免丢失同一批次的后续动作。

图的 task_start/task_complete 参数绑定当前任务 ID。event_hold 和 event_complete 是显式事件级控制；自动结束被 hold 取消时，最后一个任务图仍保留接收事件能力，便于稍后触发完成节点。

无效或缺失任务图不会伪造完成，当前任务等待配置。空事件没有未完成任务，开始后立即完成。

信号：event_started/event_completed/task_started/task_completed/objective_changed。HUD 使用显示名。ShowDialog 读取 XLSX 并继续使用 comment 边界；对话打开后临时隐藏目标与名牌，结束恢复。未接入默认空白 main。

capture_progress 返回 version/workbook/events/tasks/active/dialogues，active 包含 index/hold/objective/runner 状态。restore_progress 校验作用域和已知 ID，在错误时不改写当前状态，正常恢复不重发完成信号。原 main.gd 的 Narrative/Tasks 保存桥兼容此接口。

export_plugin.gd 将配表目录的 XLSX、事件引用的任务图以及任务资源引用的工作簿加入导出，不依赖 CSV 或目标设备上的表格软件。

## UI 约束与验证

2026-11-12 用户明确要求：不增加格式说明、空运行消息、常驻教学文字或节点分类前缀；分类只保留颜色。保存失败等实际操作结果仍可显示，详细说明使用 tooltip。

验证入口和实际通过项目见 README。旧测试入口已指向当前工作流；不再测试已删除的时间线／分身系统，也不把其恢复。

## 改名与兼容 · 2026-11-13

应用名、插件目录、脚本类、节点名称、玩家／交互分组、调试通道和配表引用路径同步改名。Godot UID 与用户编辑数据的稳定 ID 保留；数据格式不升版。branch 作为条件节点 kind 和局部条件状态键保留，其含义为条件分支，与产品名无关。Git 远程与外部备份地址保持真实有效，未对远程服务改名。

三类图不再创建隐藏的 PortDirections 占位行，端口从实际第一行开始。具名端口、连接索引、顺序、类型和颜色不变；避免 Godot 在隐藏行后计算端口时出现越界。验证包括 139 项节点呈现检查和 Metal 实际渲染。

## 关卡仓库与任务所属关卡 · 2026-11-13

level_catalog.gd 读取配表/levels.xlsx：关卡页 level_id/name/display_name/scene_path，以及可选 notes/preview_path；旧四列可读，可选值补空。配置页 version=1、next_level_id。关卡 ID 是固定数字文本，关卡名唯一；场景都位于 scenes/levels/。世界脚本导出 level_id，world_id 继续作为既有运行实例／存档作用域，旧资源中的 world_id 不重编号。LevelCatalog 的 for_world 优先读取 level_id，再按场景路径匹配。

level_warehouse.gd 分为“我的关卡”卡片目录和“关卡编辑”；编辑中包含五个常驻仓库及“关卡图”子页。新关卡创建地面、玩家出生 Marker、图定义与保留光照，写场景和工作簿；元数据写入失败则清理本次新文件。编辑关卡信息只改元数据，不改 ID 或资源路径。素材卡片提供标准 {type:files, files:PackedStringArray}，已放置项引用真实 Node，原生视口负责放置及场景撤销。重复拖放时只为新实例修正同作用域的重复 room_id/object_id/instance_id，已载入场景的 ID 不改写。

room.uses_topology 默认 true 保持旧房间连通检查；permanent_room.tscn 显式 false，是大世界常驻检测区，不要求房间连线。空世界允许没有 Room。主入口 _initialize_world 读取 role=player 的 spawn_marker，设置 player.global_transform、spawn_transform 和相机；没有 Marker 时保持旧入口位置。

任务 schema 2 的 level_id 必填且只能引用 levels.xlsx 中的一行。事件没有关卡字段。add_task(event_id, level_id) 是显式双参数接口，next_task_id 只预览编号；新建弹窗验证通过后才分配。事件与任务 Tree 新增所属关卡列；任务显示一个中文名，事件动态聚合子任务关卡，不保存另一份事件绑定。复制保留关卡并分配新任务 ID。旧任务迁移：报到任务属于连续世界，其余无法判断的旧任务按用户选择属于当前白盒。

EventDirector 当前任务必须与 current_level_id 匹配才创建／推进执行器并接收触发。bind_world(new_world) 断开旧信号，保存当前图状态，连接新关卡 Room/NPC 并按所属关卡恢复；不进行场景传送。跨关卡事件的下一任务可处于 active 等待，但在错误关卡不执行。capture_progress/restore_progress 保留暂停执行器的状态。启动试玩时主插件窗口保持原状态，新建任务／关卡等弹窗隐藏以解除模态焦点。

levels.xlsx、events.xlsx、引用的关卡、任务图与资源依赖都纳入导出插件。表格在游戏中直接读取，运行时无表格软件依赖。当前默认白盒入口仍不接入示例任务。

验证：49 项任务运行检查（包含跨关卡隔离及续接），52 项套件编辑检查（实际渲染额外验证卡片尺寸，共 53 项），11 项实际试玩窗口焦点检查，5 类原生视口放置检查；原有关卡／机关／敌人／相机／白盒材质回归通过。所有工作簿更改及界面已渲染检查。

## 界面动效边界 · 2026-11-13

editor_style.gd、level_card.gd 的 Tween 只作用于编辑器 Control 的透明度、缩放及阴影。页面／详情淡入 0.18 秒，卡片悬停 0.17 秒；新操作结束前一 Tween，卡片隐藏时复位。圆角 shader 只裁切 UI 图片透明度，不改变图片颜色。静态缩略图保存在 resources/level_previews；捕获工具只渲染临时场景副本。游戏节点、角色和环境均不接入这些动效。

## 独立关卡试玩 · 2026-11-15

world.gd 在非编辑器模式 deferred 检查 current_scene == self 且没有 main 会话，满足时创建 scenes/level_editor/play_session.tscn。该组件复用 main.gd；main 新增 world_path，默认 World 保持原主入口兼容，试玩组件设为 .. 指向当前关卡。只创建一个现有玩家、第三人称镜头、LevelAgent 及 HUD，persist_progress=false；不改变场景根、布局、ID 或存盘内容。出生点及掉落复位沿用原逻辑。嵌入主游戏或其他宿主的世界不自动创建会话。导出显式包含试玩组件及其依赖。

关卡卡片可保存备注及 preview_path；删除前检查任务引用。2026-11-16 用户确认删除也移走对应场景文件，具体合同见本页顶部“删除关卡与场景文件”，`user://level_archive` 继续保存元数据。节点正文改为浅色，分类色继续在标题和端口表达，选中使用金色边框，不增加前缀或说明行。工具栏按需换行，避免把原生窗口撑宽。

## 箱庭关卡当前合同 · 2026-11-15

关卡目录的一行与一份大关卡场景对应，箱庭内部布局直接在原生 3D 视口搭建，不使用房间接驳图。level_warehouse.pages 仅包含出生点、Layout 白盒、常驻 Room、常驻机关、常驻 NPC 五类仓库。suite 不再 _adopt(level.panel)，旧 open_tab("关卡图") 重定向关卡编辑并保持当前仓库分类。模块仍保留旧图的资源及运行兼容；启用套件时不再由原关卡插件接管图资源编辑。

原生侧栏删除接驳点卡片、起始房间与节点图按钮；新建 Room 不参与拓扑，world.validate 对纯检测区不再要求 start_room_id。旧用户场景及拓扑资源不自动迁移。任务、机关与 NPC 逻辑图、运行事件信号和所有稳定 ID 保持。验证见 [箱庭工作流](sandbox_levels_2026-11-15/validation.md)。

## 天空页与关卡信息 · 2026-11-15

统一窗口增加“天空”导航及独立预设面板。关卡信息新增预设选择，详情显示引用名称；绑定保存在 `.tscn` 的世界根 sky_preset，levels.xlsx 格式不变。新关卡默认 V2 天空模板；旧关卡不自动迁移。关闭工作窗口及开始试玩结束临时预览，草稿保存与场景保存分开。天空导出插件补齐预设及导入 HDRI 依赖。完整合同与验证见 [天空接口](../sky_editor/INTERFACES.md) 和 [验证](../sky_editor/validation/validation.md)。


## 通用任务节点 · 2026-11-15

任务图新增通用穿着／背包／角色状态检查、变量、等待、并行与汇合、子目标、失败、检查点、子图等 33 种节点，并开放 16 种已有节点。当前事件执行器连接场景、角色数据和运行调试；节点参数、进度恢复、同关卡检查点与兼容边界见 [通用任务节点](../narrative_editor/task_nodes_2026-11-15/README.md)。原有用户资源、配表和默认白盒入口保持。

## 常驻关卡逻辑与任务接取 · 2026-11-15

level_warehouse 不再创建 pages/inventories 或提供素材拖放；logic_panel 托管当前 world.level_logic。关卡目录、关卡信息和天空绑定保留。套件保存全部与原生场景保存接入图数据保存，原生保存钩子不会递归请求保存场景。

event_director 增加 accept_task(task_id)->{ok,reason}，仅接取当前关卡事件的首项任务，接取后沿用既有串行任务及跨关卡续接；重复、失效、非首项或错误关卡的任务返回失败。level_runner 与 active[event].runner 独立运行，常驻 NPC 的允许交互状态与当前任务需求取并集；对话共用同一播放器。保存进度额外记录常驻图 ID、变量、等待及执行状态，不改变旧配表 schema 或稳定 ID。详见 [常驻关卡图](../level_editor/level_logic_2026-11-15/README.md)。

## 新增关卡物件自动分类 · 2026-11-16

新增 NPC、Room、机关、白盒统一放到根下对应的空 Node3D 管理容器，由关卡插件负责原生撤销和稳定 ID。新建关卡的初始白盒地面也进入 `Whitebox`；已有用户关卡不自动整理。目录及列表继续引用实际实例，不新增配表字段。world／Room 的对象读取兼容透明容器，内部预制件仍保留自己的作用域。详细合同与检查见 [关卡接口](../level_editor/INTERFACES.md#新增物件自动分类--2026-11-16) 和 [自动分类验证](../level_editor/content_groups_2026-11-16/validation.md)。

同日父节点统一英文命名：NPC → `NPCs`、Room → `Rooms`、机关 → `Mechanisms`、关卡白盒 → `Whitebox`。现有带分类 metadata 的容器继续按职责识别；已保存的旧中文容器名称及其子路径同步改名，稳定 ID、变换和业务节点名称保持。


## 任务图连续切换 · 2026-11-16

套件 edit_task 在未保存图与目标不同路径时调用 task_panel.confirm_graph_switch(continuation)，并显示任务图页的保存／放弃／取消弹窗；保存失败保留当前图及错误，成功后才打开目标。重复打开相同路径不重新加载资源、不清空撤销历史。文件打开使用 CACHE_MODE_IGNORE，遵循同一保护并在成功打开独立文件后清除旧 bound_task_id。目标资源类型检查通过后才更新任务绑定；配表、图资源格式及运行接口不变。验证见 [切换修复验证](../narrative_editor/task_switch_2026-11-16/validation.md)。


## 运行任务列表 · 2026-11-16

event_director.objective_label 现在指向 HUD 内的 TaskTracker Control，保留 text 状态投影。task_completed 驱动独立的完成动画队列，_hud 只同步事件／任务显示名；逻辑推进不等待 UI。restore_progress 校验成功后 reset 旧动画；对话继续隐藏／恢复该控件。已有进度格式、目标状态信号不变。源、可调参数与验证见 [HUD 说明](../hud/README.md)。

## 品牌图标 · 2026-11-16

新标志 Open Room 以等轴蓝色开放房间、顶面留白、侧面门洞和两节点连线表达白盒空间制作与逻辑编辑。应用图标使用根目录 `icon.svg`（128 × 128）；`project.godot` 继续引用原路径。`assets/branding/mark.svg` 为 16 × 16 的透明紧凑标志，套件 `plugin.gd` 通过 `BRAND_ICON` 预载，`_get_plugin_icon()` 按编辑器缩放从该 SVG 建立图像纹理，替换原生顶部入口的默认拼图图标。

顶部图标按 `EditorInterface.get_editor_scale()` 从 SVG 栅格化，2 倍界面使用 32 × 32 纹理，避免 headless 导入得到的 16 × 16 缓存在 Retina 编辑器中显示过小；SVG 读取失败时回退到预载纹理。

Wiki 页头与 favicon 共用 `docs/wiki/assets/logo.svg`，与根目录应用图标保持一致；后续更新标志时同步两份资源。独立窗口导航、产品名、模块接口和用户资源保持原有约定。检查与显示记录见 [Logo 验证记录](logo_2026-11-16/validation.md)。


## 任务列表纯文字显示 · 2026-11-16

TaskTracker 移除事件和任务左侧的青色菱形及其占位，保留事件／任务两级文字、缩进和完成动画。仅调整 task_tracker_line 的图标绘制与 Text 左边距；字体由当前样式维护。实际验证见 [任务列表验证](../hud/task_tracker_2026-11-16/validation.md)。

## 旧 NPC 素材清理 · 2026-11-16

NPC 素材目录不再包含旧守卫副本；内部兼容定义移出 `resources/enemies/` 扫描范围。轮盘默认放置真实人物模型，旧最近使用路径若已不在素材目录则跳过。 验证见 [清理记录](../enemy_editor/legacy_cleanup_2026-11-16/validation.md)。
