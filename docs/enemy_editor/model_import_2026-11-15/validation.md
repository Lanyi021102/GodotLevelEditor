# NPC 模型导入验证 · 2026-11-15

环境：Godot 4.7.1，macOS，headless 与 Metal 4.0 / Forward+。功能测试在 `/tmp/branch-npc-import-lMxPiK` 独立副本执行；当前工作目录另做最终 headless 编辑器启动检查，无脚本错误。

| 检查 | 结果 | 日志 |
|---|---|---|
| 新增外观运行：骨骼、双臂 T Pose、关闭自动播放、可选动画、外部动作、骨架匹配、保存重读、资源依赖、GuardAI 接入及旧场景兼容 | 15 通过 / 0 失败 | [runtime.log](runtime.log) |
| 新增编辑操作：导入、撤销重做、无效资源保护、骨架替换、动作选择、保存、生成 NPC、原生三维模型及项目外 glTF 包导入 | 19 通过 / 0 失败 | [editor_headless.log](editor_headless.log) |
| Metal 实际渲染及 1100 × 760 窄窗口 | 21 通过 / 0 失败 | [editor_metal.log](editor_metal.log) |
| 原有 NPC 运行与状态机 | 45 通过 / 0 失败 | [enemy_runtime.log](enemy_runtime.log) |
| 原有行为图、撤销、保存、场景绑定、巡逻与调试呈现 | 42 通过 / 0 失败 | [enemy_canvas.log](enemy_canvas.log) |
| 套件导航、目录、草稿保护及既有编辑器接入 | 78 通过 / 0 失败 | [suite.log](suite.log) |
| 当前项目 headless 编辑器启动 | 无解析或脚本错误 | [main_parse.log](main_parse.log) |

实际截图已经人工检查：模型网格和原贴图正常，65 根骨骼可叠加显示，双臂水平展开，无动画选择为 T Pose。左右预览与参数栏在最小窗口保留，参数可滚动。

- [模型与骨骼](模型与骨骼.png)
- [窄窗口](窄窗口.png)

素材验证使用项目已有 Quaternius glTF、GLB 动画库及 `.scn` 模型；未下载或替换用户角色。FBX 入口使用 Godot FBXDocument，本次没有额外 FBX 实物样例。特殊骨架无法识别双臂时保留原始静止姿态并提示，不冒充 T Pose；不执行自动蒙皮或任意骨骼命名映射。

新增模型依赖为可导出的原生资源引用，已检查保存依赖；未进行独立打包发布测试。测试不修改用户关卡、角色、配表或默认入口。生成的 NPC 继承其行为图，本次不增加友善或对话规则。

退出时仍有项目此前已有的 `Plugin is not attached to debugger` 和 1 个 ObjectDB 实例泄漏诊断；此前资源导航检查日志也存在相同信息。此次功能检查无新增脚本错误，最终渲染没有重复 reimport 任务错误。
