# Branch 项目约定

- 以 README.md、docs/tools/BLUEPRINT_TOOLCHAIN.md 和各模块 INTERFACES.md 为当前依据，先读取本任务相关文件。
- 2026-11-02 用户确认清理历史演示与旧风格，随后指定保留白模空岛氛围作为光照 V1。保留三套编辑器、可编辑 HUD、正常比例角色、共享玩法，以及 scenes/lighting/cloud_island_v1.tscn 和对应光照资源；其他历史演示不恢复。
- 光照 V1 是后续效果迭代的保留基线，说明与原始参考见 docs/lighting/cloud_island_v1/README.md。
- 默认入口 scenes/main.tscn，关卡与机关源分别位于 scenes/level_editor 和 scenes/mechanisms；保留用户制作的资源。
- 通用回溯、分身、感知、机关与存档仍为当前依赖，不能仅因代码编写时间较早而删除。
- 公共变动记录接口与验证结果；多个聊天协调文件归属。先用 headless 检查与相关测试，涉及视觉时再实际渲染检查。
