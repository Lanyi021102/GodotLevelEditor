# GodotLevelEditor 项目约定

- 以 README.md、docs/tools/BLUEPRINT_TOOLCHAIN.md 和各模块 INTERFACES.md 为当前依据，先读取本任务相关文件。
- 2026-11-02 用户确认清理历史演示与旧风格，随后指定保留白模空岛氛围作为光照 V1。保留全部编辑器、可编辑 HUD、正常比例角色、基础试玩，以及 scenes/lighting/cloud_island_v1.tscn 和对应光照资源；其他历史演示不恢复。
- 光照 V1 是后续效果迭代的保留基线，说明与原始参考见 docs/lighting/cloud_island_v1/README.md。
- 默认入口 scenes/main.tscn，大世界关卡源位于 scenes/levels，房间素材位于 scenes/level_editor/rooms，机关源位于 scenes/mechanisms；保留用户制作的资源。
- 2026-11-12 用户确认转为个人白盒编辑器：删除时间暂停、回溯／快进、分身、轨迹、能量和能力解锁；保留全部编辑器及其运行组件，清除主入口预设玩法。组件 tl_capture/tl_restore 仅用于状态保存、复位与编辑器操作，不恢复时间线。保留用户制作的资源、光照基线和基础角色操作。
- 公共变动记录接口与验证结果；多个聊天协调文件归属。先用 headless 检查与相关测试，涉及视觉时再实际渲染检查。
