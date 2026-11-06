# 当前角色资源

更新：2026-11-02。

当前使用 assets/characters/quaternius_base/adapted_human.scn 的正常比例骨骼角色。原始模型、动画、贴图、来源及许可信息继续保留在该目录，支持后续重新导入和替换。

- scenes/humanoid_player.tscn：当前玩家及分身场景。
- scripts/actors/humanoid_player.gd：移动与动画节奏参数。
- scripts/actors/character_model.gd：模型装载、身高匹配、材质与物理帧动画。
- scenes/guard.tscn：共用模型的守卫。
- tools/characters/build_humanoid.gd：从保留的源资源重建适配角色。

身份染色用于辨别分身与敌人；移除了依赖旧环境美术的光圈、描边材质与样板画面。
