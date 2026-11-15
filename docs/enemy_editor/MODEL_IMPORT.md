# NPC 模型、骨骼与可选动画

更新：2026-11-15。

## 使用

1. 打开 GodotLevelEditor → NPC → 我的NPC，新建或打开一个 NPC，进入 NPC编辑。
2. 在“模型与动画”页点击“导入模型…”，选择 GLB、glTF、FBX，或项目内的 `.tscn` / `.scn`。模型自带骨架会自动识别；可以选择骨架，查看骨骼树、勾选“显示骨骼”。拖动预览旋转，滚轮缩放。
3. 如需单独导入骨架，点击“导入骨骼…”。它必须与已有蒙皮的模型匹配：骨骼名称、顺序、父子层级及绑定姿态一致；不匹配时保留原草稿并提示。此功能不自动为静态模型制作蒙皮。
4. 动画不是必填。待机、走路、跑步初始均为“无（T Pose）”，模型自带动画也不会自动启用。可以选择已有片段，或用“添加动画来源…”导入其他文件，再为各动作选择片段。预览按钮只播放对应选择；选择“无”时返回静止姿态。
5. 点击“保存”。需要放入关卡时，点击“生成 NPC 素材…”，默认写入 `scenes/npcs/`，随后可在关卡的“常驻 NPC”仓库找到。已有 NPC 也可通过原“绑定到所选守卫”接口绑定定义。

模型保留原材质、贴图，可设置身高。常见人形骨骼会把双臂展开为 T Pose；无法识别双臂的特殊骨架保持原始绑定姿态，预览会明确显示“静止姿态（未识别人形手臂）”。没有骨架的静态模型可以导入，但不能添加骨骼动画。

外部动画按骨骼名称匹配，修正局部绑定姿态与骨长；不支持任意命名体系之间的自动骨骼映射。缺少目标骨骼或片段时拒绝绑定。现有移动行为继续决定待机、走路与跑步的选择，未配置的动作始终静止，不回退到旧默认动画。

## 文件与兼容

- 外部原始素材复制到 `assets/characters/npc_imports/<名称_随机后缀>/`，不覆盖用户素材。glTF 一并复制同目录内引用的二进制与贴图；FBX 收集同目录贴图及 `textures` / `.fbm` 子目录。项目外的 Godot 场景须先连同依赖放入项目。
- 导入器使用 Godot GLTFDocument / FBXDocument 生成包含网格、蒙皮、骨架和动画的 `.scn` 快照；贴图嵌入快照。原文件保留在同一素材目录的 `source/`，用 `.gdignore` 避免重复导入。重新导入会生成新副本；后续修改原始模型后须重新导入并保存 NPC。
- EnemyDefinition 增加可空的 `appearance` 资源；旧定义没有该字段时保持原角色与动画。图 schema、状态与端口 ID 不变。
- 模型、骨架和动画来源以 PackedScene 引用保存，成为标准资源依赖。编辑、撤销、重做、冲突保护和另存均包含外观数据。
- 生成的场景引用同一个 NPC 定义；原生三维编辑时由工具模型组件显示外观，运行时由 GuardAI 使用私有定义创建相同外观。此功能不新增友善／对话行为。

## 验证

测试均在独立临时项目副本运行，未给用户关卡或默认入口放置示例 NPC。入口：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path <项目副本> res://tools/enemy_editor/test_npc_visual.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path <项目副本> -- --test-npc-appearance
/Applications/Godot.app/Contents/MacOS/Godot --editor --path <项目副本> -- --test-npc-appearance --capture
```

最终通过项数、回归结果与实际截图见 [验证记录](model_import_2026-11-15/validation.md)。
