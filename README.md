# Branch

俯视角解谜与潜行箱庭项目，使用 Godot 4.7.1。当前剧本方向为轻松、王道的“时间管理局”冒险：特工使用分身与时间能力，在不同时间线回收错位道具并安全撤离。具体方案见 [当前游戏设计](docs/GDD.md) 与 [剧本建议稿](docs/narrative/TIME_BUREAU_STORY.md)；任务中枢、异物回收与撤离系统尚未实现。

当前入口：`scenes/main.tscn`。它组合关卡编辑器制作的连续世界、正常比例角色、共享 HUD 和回溯/分身会话。场景采用中性白盒、灰阶 HUD 与晴日微缩光照 V2：暖色日光、冷色补光、柔和阴影、岛下云层与轻微景深。现有材质保持原样，光照 V1 继续独立保留。后续美术通过可替换资源制作。

默认白盒与 3C 测试物体使用 [米制网格材质](docs/whitebox_grid/README.md)：1 m 粗线、0.5 m 中线、0.1 m 细线，缩放后保持真实尺度。

当前房间与 3C 岛面底板向下加厚到 3.6 m，行走面保持原高度；岛外空白区域显示流动云雾。景深仅在运行游戏时启用，编辑关卡时保持清晰。已有编辑器会话若持有旧资源，保存后重新打开项目刷新。

## 运行与编辑

用 Godot 打开本目录，F5 运行当前项目；F6 运行选中的关卡或组件。也可双击 `启动项目.command`。

| 制作内容 | 编辑入口 |
|---|---|
| 房间、白盒与世界节点图 | 顶部“关卡与世界”、右侧“关卡摆放” |
| 机关组件与节点图 | 机关编辑器 |
| 敌人状态机 | 敌人状态机编辑器 |
| HUD 布局 | `scenes/hud.tscn` 的 2D 视口 |
| HUD 样式 | `resources/ui/hud_theme.tres` |

当前关卡源位于 `scenes/level_editor/`，机关源位于 `scenes/mechanisms/`，敌人定义位于 `resources/enemies/`。用户自建房间和机关继续保留。

## 操作

WASD 移动；Shift 跑步；空格跳跃；Q/E 单按回退/快进 1 秒，长按连续浏览，松开保持暂停；T 继续；R 把回退点之后的录像固定成分身；F 交互。左上角按钮暂停/继续，右键拖动和滚轮调整相机。能量玩法已移除。

3C 测试：打开 `scenes/3cplayground.tscn` 后 F6。包括跑道、高低箱、跳台、窄梁与拉杆门。调参与固定分身规则见 [3C Playground](docs/3cplayground/README.md)。

世界持续进度保存到 `user://branch_world_progress.json`，录像与分身不写入长期存档。

## 文档

- [Git 与 Mac / Windows 双机协作](docs/tools/GIT_COLLABORATION.md)
- [工具共同规范](docs/tools/BLUEPRINT_TOOLCHAIN.md)
- [关卡与世界](docs/level_editor/README.md)
- [机关](docs/mechanism_editor/README.md)
- [敌人](docs/enemy_editor/README.md)
- [HUD](docs/hud/README.md)
- [角色源资源](docs/character_import/README.md)
- [白模空岛光照 V1](docs/lighting/cloud_island_v1/README.md)
- [晴日微缩光照 V2](docs/lighting/sunlit_miniature_v2/README.md)
- [当前游戏设计与实现边界](docs/GDD.md)
- [时间管理局剧本建议稿](docs/narrative/TIME_BUREAU_STORY.md)
- [潜行、社会互动与三类关卡调研](docs/research/STEALTH_SYSTEMS_2026-11-05.md)
- [首案白盒设计建议](docs/narrative/FIRST_CASE_WHITEBOX.md)
- [清理及验证记录](docs/cleanup/README.md)

角色源资源的许可与来源信息保存在 `assets/characters/quaternius_base/`。编辑器节点的分类色表示节点职责，保留其操作含义。
