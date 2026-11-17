> 2026-11-17 当前角色资源统一在 `addons/godot_level_editor/assets/characters/quaternius_base/`。玩家快照已转换为 `adapted_human.tscn`，显式引用同目录贴图；脚本位于插件的 `scripts/actors/`。下文旧路径为原专项记录。

# 当前角色资源

更新：2026-11-16。

基础玩家使用 `assets/characters/quaternius_base/adapted_human.scn` 的正常比例骨骼角色。原始模型、动画、贴图、来源和许可保留在该目录，供重新导入和替换；两个动画 GLB 均属于源资源，不能只因没有直接场景引用而删除。

- `scenes/humanoid_player.tscn`：当前正常比例玩家。
- `scenes/player.tscn`、`scripts/player.gd`：玩家继承的基础角色场景与控制逻辑。
- `scripts/actors/humanoid_player.gd`：移动与动画节奏参数。
- `scripts/actors/character_model.gd`：模型装载、身高匹配、可配置材质染色与物理帧动画。
- `tools/characters/build_humanoid.gd`：从保留的模型和动画源重建适配角色。

可复用 NPC 使用 `scenes/npcs/v1_*.tscn` 和 `resources/enemies/samples_v1/`；模型、许可和导入快照位于 `assets/characters/npc_samples_v1/`。内部角色组件 `addons/enemy_editor/runtime/npc_actor.tscn` 与 `scripts/stealth/guard_ai.gd` 仍用于 NPC 运行和兼容，不作为旧守卫素材卡片重新展示。步骤见 [NPC 素材与动画](../wiki/guides/npc-samples.md)。

时间线、分身和能量玩法已移除。角色快照只用于状态保存、编辑器操作和复位；染色接口仍可用于角色外观与状态表现。历史清理与本轮保留依据见 [清理索引](../cleanup/README.md)。
