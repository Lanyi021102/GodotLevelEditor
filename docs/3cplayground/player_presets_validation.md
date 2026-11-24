# 玩家 3C 验证 · 2026-11-24

使用 Godot 4.7.1，在临时工程副本执行以下检查。测试关卡、预设和存档写入副本。

| 检查 | 结果 | 覆盖 |
|---|---:|---|
| `--script res://tools/3c/test_player_preset.gd` | 27 项通过 | 同一原生关卡切换两份外部预设，禁用跳跃/跑步/交互，二段跳、蹲姿碰撞和起身检查，实际台阶/翻越/上台/攀爬/翻滚，第一人称与镜头 FOV，外部动作重定向及 CMU 关键帧驱动实际骨骼 |
| `--editor -- --godot-level-editor-suite-test --player-editor-test` | 13 项通过 | 能力开关、保存、复制、关卡引用、撤销/重做、F6 前的场景序列化、攀爬区与动画播放器 |
| `res://tools/3c/test_3c.tscn` | 12 项通过 | 现有白盒移动、跳跃、交互、复位、进度。副本中的测试存档路径指向可写目录 |
| `res://tools/camera/test_third_person.tscn` | 24 项通过 | 现有越肩镜头、换肩、视口与碰撞、输入和台本兼容 |
| `python3 tools/wiki/wiki.py check` | 通过 | 中英文导航、链接、图片引用与搜索 |

**动作来源** 梯子攀爬和跨步越障已从在线 BVH 下载，SHA-256 及转换方法见 [动作素材](../../addons/godot_level_editor/assets/characters/player_motion/README.md)。Quaternius 第 2 套标准包的二进制未能通过当前连接传入。翻越、抓边上台采用项目白盒关键帧。

**实际呈现** Headless 验证动作预览播放器与运行时骨骼。当前环境启动有界面的 Metal 和 OpenGL 编辑器均在初始化显示前退出，实际窗口像素呈现未完成检查。

**名称检查** 用户界面与双语指南统一使用“玩家”“玩家预设”“应用到当前关卡”“抓边上台”和“攀爬区”。预设改名保留资源路径。
