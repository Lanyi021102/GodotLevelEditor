# 第一版示例 NPC 素材来源

本批于2026-11-16按具体的原作者 CC0 发布挑选，供工程内制作示例与继续编辑。使用步骤见 [当前 Wiki 指南](https://lanyi021102.github.io/GodotLevelEditor/wiki/guides/npc-samples/)。

| 内容 | 原作者与来源 | 许可依据 |
|---|---|---|
| 哥布林男女、休闲居民男女 | Quaternius：[Animated Characters Pack](https://opengameart.org/content/animated-characters-pack) | 作者于2021年发布页明确 CC0；原始档案无独立许可文件，保留发布证据与下载哈希 |
| 健壮人形男女 | Quaternius：[Universal Base Characters Standard](https://quaternius.itch.io/universal-base-characters) | 该档案附带原始 CC0 Standard 许可；只取免费包确有的两种身体 |
| 健壮人形共享动画 | Quaternius：[Universal Animation Library](https://quaternius.itch.io/universal-animation-library) | 复用项目已有 CC0 Standard 文件及许可，43片段，保留在 `../quaternius_base/` |
| 奶牛、马、巴哥犬、绵羊 | Quaternius：[LowPoly Animated Farm Animal Pack](https://opengameart.org/content/lowpoly-animated-farm-animal-pack) | 2018年作者发布页及原包 CC0 许可 |
| 雪怪、仙人掌怪、独眼怪 | Quaternius：[Textured Cute Monster Pack](https://opengameart.org/content/textured-cute-monster-pack) | 2021年作者 CC0 发布及具体下载记录 |

作者当前总许可页不等同于以上旧版具体文件的许可。本批的下载、原始文件哈希、骨骼及原动作清单见 `humans/selection.json` 与 `creatures/selection.json`；人形和生物各自目录保留其许可依据。完整ZIP不收入工程。

## 文件

- `humans/source/`：6个人形的精选原始 FBX / glTF、二进制与贴图。
- `creatures/animals/source/`、`creatures/monsters/source/`：4动物与3怪物的精选原始 FBX 和必要贴图。
- `imported/`：由原生 Godot 文档导入器生成的可直接加载 `.scn` 快照，保留骨架、蒙皮、动作和原材质。源目录由 `.gdignore` 排除重复导入。
- `resources/enemies/samples_v1/`：定义、机器可读目录和真实缩略图。
- `scenes/npcs/v1_*.tscn`：可重复放置的实例源场景。

示例高度是编辑器中的可调初始值；小体型使用独立的幻想哥布林身体，没有用付费 Teen 或把同一身体缩放充当全部体型。Pug、Sheep 只有 Idle / Jump；其余角色也仅绑定来源确有的动作。

导入准备修复了原 glTF 的两处贴图文件名引用，并为旧人形 FBX Idle 缺失的右臂旋转通道补上中立下垂姿态；修改仅在导入快照中。三怪物的原贴图按已有 UV 显式恢复。原始模型文件保留。

重新生成工具：`tools/enemy_editor/npc_samples_v1/build_samples.tscn`，输入是同目录的 `sources.json`。工具默认拒绝覆盖已有样例，显式 `--replace-generated` 只用于重建这批有归属标记的生成资源；日常修改应另存个人定义和场景。
