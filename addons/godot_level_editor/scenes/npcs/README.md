# NPC 素材

可复用的 NPC 场景放在此目录，关卡仓库的常驻 NPC 页面会读取。

首批13个示例为 `v1_*.tscn`，在三维轮盘 NPC → 已有素材中按中文名称选择，也可直接拖入关卡。定义在 `resources/enemies/samples_v1/`，原始模型与许可在 `assets/characters/npc_samples_v1/`。当前使用步骤见 [NPC素材与动画](../../docs/wiki/guides/npc-samples.md)。

NPC 目录与轮盘仅列出当前可复用场景；默认放置 `v1_human_medium_male.tscn`。旧胶囊和守卫入口已移除，内部角色组件位于 `addons/enemy_editor/runtime/npc_actor.tscn`，不作为素材卡片。
