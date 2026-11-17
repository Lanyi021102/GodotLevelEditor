# QA 边界缺陷修复与文档同步 · 2026-11-16

## 范围与状态含义

本轮对应功能 QA 报告中的 QA-01～QA-10。模块修复分别由机关、关卡、台本、任务和天空窗口负责；本记录与 Wiki 同步由公共文档窗口维护。

QA-01～QA-10 的修复已取得模块专项与总控独立整合验证。下表分别列出两类依据，具体检查与源码快照见后文；同一套专项覆盖多条缺陷，不逐条重复累计断言。原报告的 1308 项回归统计及 Wiki V1 交付时的 74 项机关检查均不是本轮修复后的通过数。

结论对应本轮修复快照。随后新增的门规格、NPC 素材等并行需求不并入本轮十项修复的验收范围，也不以其进行中的状态撤销本轮已记录结果。

总控汇总 `integration/acceptance_summary.json` 确认十项修复完成，独立验收去重后为 **16 组、634 项全部通过**。模块的 headless／Metal 重跑不再次加到该总数；13 个关键修复源码与验收快照哈希一致，差异为空。

## 修复与验收表

| 编号 | 范围与修复合同 | 模块专项 | 总控独立整合依据 |
|---|---|---|---|
| QA-01 / P1 | 原生保存检查磁盘冲突与图有效性；拒绝时保留文件和草稿，成功时成对写盘 | 机关编辑通过 | 最终机关保存器复测通过 |
| QA-02 / P1 | 原生复制分配独立根 object_id 与 instance_id；存量歧义显式报错 | 真实原生 Duplicate、撤销重做、保存重开通过 | 最终导入、关卡放置与共享套件通过 |
| QA-03 / P2 | 台本首次保存写入并记住 XLSX 路径，成功后清除未保存状态 | 台本文件专项通过 | 共享套件编辑与最终运行通过 |
| QA-04 / P2 | 合法 XLSX 走工作簿读取，旧 tres 保留迁移；失败保留当前库 | 与 QA-03 共用台本专项，通过 | 共享套件编辑与最终运行通过 |
| QA-05 / P2 | 剪贴板保存复制时的节点、连线、位置和绑定组件快照 | 机关编辑通过 | 最终机关编辑复测通过 |
| QA-06 / P2 | 所属关卡保存／启动前检查失效 NPC / Room，兼容外关卡和当前任务对象 | 绑定与真实保存入口通过 | 绑定专项、通用任务与最终套件运行通过 |
| QA-07 / P2 | 当前状态无匹配转换的纯自定义动作正常失败并保留原因 | 机关运行通过 | 机关缺陷运行回归通过 |
| QA-08 / P2 | 自定义进入 pressed 遵守 reset_after，恢复不重放事件 | 机关运行通过 | 机关缺陷运行回归通过 |
| QA-09 / P2 | HDRI 导入锁定草稿替换／保存，结果归原草稿，失败恢复操作 | 天空导入与运行通过 | 天空运行回归通过 |
| QA-10 / P2 | 事件表读取失败停止删除，任务引用保护继续生效 | 读表失败、引用与正常删除分支通过 | 最终导入、共享套件编辑通过 |

## 操作说明入口

- 机关：[保存与剪贴板说明](../../wiki/reference/mechanisms.md#save-and-copy)、[自定义动作与复位](../../wiki/reference/mechanisms.md#custom-actions)。
- 关卡：[复制与删除规则](../../wiki/guides/levels.md#copy-delete)。
- 台本：[首次保存和手动打开](../../wiki/faq.md#dialogue-files)。
- 任务：[缺失 NPC 引用排查](../../wiki/faq.md#missing-npc)。
- 天空：[HDRI 导入期间的操作](../../wiki/faq.md#hdri-import)。

本次只补充现有页面文字和接口合同，保留任务图切换、任务 HUD、Logo 及其他聊天已加入的内容；没有更改页面布局、导航或样式。

## 用户资源现状单列

原 QA 报告记录 `scenes/mechanisms/sliding_door.tscn` 的内嵌图存在悬空 `delay.trigger`，且与同名外部图不一致。这是报告时的用户资源配置现状，不计入上述十类代码缺陷，本轮公共文档不修改该资源、不推断其制作意图，也不将其写成已修复。

相关回归若被此资源阻断，应记录原始失败及所用副本的配置差异，不能把调整副本后的结果直接当作原工作树通过。排查提示不要求用户删除该节点。

## 模块专项验证

输入报告为 `QA报告.txt`，位于本机 `Documents/Codex/QA/2026-11-16-GodotLevelEditor/`。分工、验收计划、各模块结果及日志放在项目 `.validation/qa-fixes-2026-11-16/`，这些本地路径不是网站附件链接。

下列为模块在独立副本中的结果，公共文档窗口核对已有日志与模块摘要，没有将这些检查冒充为本窗口执行。

| 模块 | 最终专项结果 | 相对上述本地证据根目录的来源 |
|---|---|---|
| 机关：QA-01 / 05 / 07 / 08 | 编辑 headless 35 / 35、Metal 35 / 35；缺陷运行 27 / 27；既有运行 48 / 48、编辑 24 / 24、Metal 选择 25 / 25 | `mechanism/editor_final.log`、`editor_metal_final.log`、`runtime.log`、`regression_*.log` |
| 关卡：QA-02 / 10 | headless 56 / 56、Metal 原生编辑器 57 / 57；最终副本无 compat 临时补丁 | `level/result.txt`、`fixed-headless/checks.log`、`fixed-metal-final/checks.log` 及各自 manifest |
| 台本：QA-03 / 04 | headless 45 / 45、Metal 48 / 48；含旧资源迁移、失败保留草稿及真实文件回读 | `dialogue/result.txt`、`headless/headless.log`、`render/` |
| 任务：QA-06 | 绑定运行 11 / 11、真实保存入口 2 / 2；所属任务的隐藏 NPC 与外关卡延后检查通过 | `task/result.txt`、`qa-runtime.log`、`qa-editor.log` |
| 天空：QA-09 | headless 53 / 53、Metal 53 / 53、运行 32 / 32；`test_results.json` 全部 true | `sky/result.txt`、`qa09_headless.log`、`qa09_metal.log`、`runtime_headless.log` |

天空最终增加了恢复／生命周期断言，以最终日志的 53 项为准，不沿用早期 52 项计数。非法 EXR 的预期解码错误位于 `QA09_EXPECTED_BAD_INPUT` 标记之间，失败后恢复断言通过；真实磁盘满与真实 120 秒超时未进行长时间测试。

机关的修复边界由 `mechanism/source.sha256`、`snapshot_verified.txt` 及 `qa-fix-source-snapshot.tar.gz` 留存。初次 Metal 的 35 项中 4 项失败转录保存在 `metal_failure_history.txt`，后续通过不抹去该记录；最终修正了首次扫描后 saver 优先级，并在保存钩子内再次确保优先级。

机关模块副本曾对归属外类型推断加注解，这些调整在模块结果中保留说明；正式整合以总控修正后的源码重新导入和测试为准。原生保存拒绝的 API 返回仍可能是 OK，且无效另存未生成文件时 Godot 可能输出文件 stat 提示；通过项验证的是文件未被覆盖、草稿仍在，并不表示获得了完整的原生错误码否决能力。

HUD 最新模块结果采用 `task/hud-verified.log` 和 `hud-verified-render.log`，分别 18 / 18，源码与副本哈希记录在 `hud-verified-source.json`。旧 `hud-final.log` 的 2 项失败保留为早期证据，不再用于最终结论；其等待夹具改为按游戏 process_delta 累计，保留全部断言与墙钟保护。任务输入夹具改为独立按下／释放事件并等待实际帧推进，没有删除断言或修改产品输入逻辑。

## 总控独立整合验证

总控在独立快照执行共享回归，并对中间失败项使用修正后的保存器、显式类型与可靠输入夹具重新运行。`integration/final_results.json` 中下列五项均退出 0、脚本错误 0、失败断言 0：

| 最终检查 | 结果 | 来源 |
|---|---|---|
| 工程导入与编译 | 通过 | `integration/import_final.log` |
| 机关编辑与原生保存拒绝／成功配对 | 35 / 35 | `integration/mechanism_editor_final.log` |
| 关卡轮盘与物件放置 | 84 / 84 | `integration/quick_add_final.log` |
| 共享事件／任务运行 | 49 / 49 | `integration/suite_runtime_final.log` |
| 任务列表 | 18 / 18 | `integration/task_tracker_final.log` |

其他已通过整合组分别为：套件编辑 78 / 78、场景引用拖放 34 / 34、任务绑定 11 / 11、通用任务节点 90 / 90、常驻关卡逻辑 34 / 34、机关缺陷运行 27 / 27、既有机关运行 48 / 48、天空运行 32 / 32、当前白盒 12 / 12、实例属性 22 / 22、独立关卡试玩 15 / 15。来源为 `integration/editor_results.json`、`runtime_results.json` 中成功项及对应同名日志；最终重跑替代的旧项不重复累计。

总控另行复测台本文件 45 / 45，来源为 `integration/dialogue-final/headless_recheck.log`，与上表及上述其他组共同构成 16 个去重检查组。显示主题新增 `ui_motion.gd` 依赖后，最小台本 runner 曾漏复制该 helper；总控只在临时副本补齐后验证，属于测试入口依赖问题。台本窗口已在正式 runner 加入依赖，并于 `dialogue/final-entry/headless.log` 再次取得 45 / 45，该模块重跑不重复计入独立总数。

`integration/mechanism_fixes_editor.log`、`quick_add.log`、`suite_runtime.log` 等中间日志保留原失败结果，不能与 `*_final` 互换，也不能把最初退出码为 0 但存在脚本错误的关卡检查当成通过。总控测试源码哈希以 `integration/final-source-manifest.json` 为边界，后续并行功能更新需另行验证。

## 本轮公共文档检查

`python3 tools/wiki/wiki.py check` 已在当前工作区最终执行通过：14 个 Wiki 页面、829 次本地链接／锚点／资源目标检查、36 次图片引用检查、115 条搜索索引记录，错误数为 0。计数包含其他窗口已加入的页面和内容；不是 829 个互不重复的功能测试。

日志保存在 `.validation/qa-fixes-2026-11-16/wiki/wiki-check.log`。原专项文档的一处旧自动分组锚点仍有信息提示；没有计为本次新指南通过项，也没有为消除提示改写其他窗口的历史记录。

显示 FAQ 的 `display_refresh_2026-11-16/validation.md` 已由显示窗口写入真实检查与截图，本窗口核对目标存在，保留原链接与显示操作文字，没有生成占位文档。

本轮公共文档修改未改变网页布局、导航、样式或截图，因此没有另做浏览器视觉复测。没有运行或重复计入各模块的 Godot 功能回归，不提交、推送或发布网站。
