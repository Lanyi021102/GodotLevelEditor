# 玩家 3C 接口

- `modules/godot_level_editor_player/preset.gd` 定义玩家预设资源。能力、镜头及控制放在 `values`，动作槽名称放在 `clip_overrides`，按键覆盖放在 `bindings`，可选外观和兼容动画包使用 `model_scene` 和 `animation_scene`。省略字段使用默认值，运行时从 `settings()` 读取校验后的独立字典。
- 作者预设保存在 `res://content/resources/player_presets/player_*.tres`。改名保留路径，复制产生独立文件。草稿独立编辑，保存已有文件前检查其内容哈希。关卡根的 `player_preset` 通过原生场景持有唯一资源引用，绑定纳入场景撤销与重做。
- 空工程尚未创建玩家预设目录时，预设库按空列表显示；首次保存预设再创建目录。安装检查覆盖首次打开玩家页面，不要求作者预先制作资源。
- 主会话 `main.gd` 在玩家和 CameraRig 的 `_ready()` 之前读取当前 World 的预设。打开原生关卡 F6 和主入口共用此路径。空引用走原有默认角色和镜头，预设运行数据不写回资源或场景。
- `player_input.gd` 为每个角色注册独立 InputMap 动作并在退出时释放。走跑、跳跃、交互等走现有玩家节点、世界碰撞和交互合同。翻越与抓边先检测目标及胶囊路径，过程中通过物理碰撞推进。攀爬用 `godot_level_editor_climbable` 组的 Area3D 和 `CollisionShape3D` 盒子，检测玩家碰撞层 2。
- `animations.gd` 提供附加的 `moves` 库。Quaternius 的 Sprint、Roll、Interact 从既有 CC0 源重定向到默认角色。Climb 与 StepOver 从 CMU 的两段动捕裁剪并重定向。Vault 和 Mantle 使用本项目的白盒骨骼关键帧。实际位移由控制器实现。自定义模型从自己的 AnimationPlayer 选片段。
- 旧关卡 ID、默认玩家组、LevelAgent、台本输入锁定与已有镜头接口保留。操作见[玩家指南](../wiki/guides/player.md)，实测见[验证记录](player_presets_validation.md)。
