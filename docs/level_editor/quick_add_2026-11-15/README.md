# 原生 3D 快速添加轮盘 · 2026-11-15

打开 `scenes/levels/` 的关卡或房间源场景，在 Godot 原生 3D 工具栏点击 **添加轮盘**。六个固定方向为玩家出生点、Layout 白盒、常驻 Room、常驻机关、常驻 NPC、最近使用。

- 点击呼出后，指向分类并滚轮切换素材，点击扇区或中心缩略图进入放置。
- 快捷模式：长按反引号键（Esc 下方）或鼠标侧键，指向分类后松开进入放置；在中心空区松开取消。工具栏下拉菜单可设置按键组合或恢复默认键。
- 点击 **全部** 查看当前分类的缩略图列表，按名称搜索。房间、机关、NPC 从现有素材目录发现，白盒保留全部 16 种形状。
- **放入** 明确选择当前关卡或某个 Room。Room 自身始终放到当前关卡；房间源场景内不再嵌套 Room。
- 选择后显示蓝色半透明预览，鼠标指向实际网格表面；没有表面时投射到 Y=0 工作平面。白盒按外包尺寸贴住命中表面，坐标按 0.1 m 吸附。R 每次旋转 15°，Shift+R 反向旋转。
- 左键放置，保持当前素材以便连续添加；右键或 Esc 结束。中键和 Alt 视角导航继续交给原生视口。新增物件可以使用 Godot 原生检查器、变换工具和撤销／重做。
- 若已有 role=player 的出生标记，放置操作移动该标记并结束；属于不可编辑房间子实例的出生点会提示打开源房间或启用可编辑子节点，不静默修改它。
- 最近使用只记录成功放置的 12 个不同素材。浏览、切分类及取消不创建对象或撤销记录。

## 实现及并行文件归属

本次负责 `addons/godot_level_editor/asset_catalog.gd`、`radial_menu.gd`、`radial_tool.gd`、`tools/level_editor/test_quick_add.gd` 和本目录。现有关卡 `plugin.gd` 仅局部接入工具栏、输入、覆盖绘制、清理及测试入口，并使 Room 的起始 ID 撤销与新增动作一致；`level_warehouse.gd` 仅替换素材枚举来源。其他聊天对箱庭关卡导航、旧关卡图隐藏、天空等模块的并行修改继续保留，未修改其实现。

预览实例属于编辑器 SubViewport，不属于用户关卡，停用处理、碰撞、灯光、环境、摄像机和 3D 音频；生成的预览材质为实例覆盖。选择素材的鼠标按下不会穿透成一次放置。正式放置重新实例化原 `.tscn`，只分配新的根作用域标识，保留内部局部对象标识、机关图引用、用户参数及源文件。运行玩法、角色及光照资源不由轮盘改写。

## 验证入口

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path /Users/lanyi/branch -- --quick-add-test
/Applications/Godot.app/Contents/MacOS/Godot --editor --path /Users/lanyi/branch -- --quick-add-test --capture-quick-add
```

结果与截图见 [validation.md](validation.md)。
