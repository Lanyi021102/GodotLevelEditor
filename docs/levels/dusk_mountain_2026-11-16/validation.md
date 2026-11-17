# 黄昏山居验证 · 2026-11-16

Godot 4.7.1，macOS Apple M4；先运行 headless 编辑器扫描，再运行本关端到端与相关组件回归，最后使用 Metal Forward+ 实际渲染检查。

## 命令

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path /Users/lanyi/branch --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch res://tools/dusk_mountain/test.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch res://tools/level_editor/test_level_logic.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch res://tools/mechanisms/whitebox_v1/test_runtime.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/lanyi/branch res://tools/dusk_mountain/preview.tscn
```

## 验证范围

结果：**本关端到端 63 项 / 0 失败；常驻关卡逻辑回归 34 项 / 0 失败；机关回归 74 项 / 0 失败**。完整输出分别保存在 `end_to_end_test.txt`、`permanent_logic_test.txt`、`mechanisms_test.txt`。`git diff --check` 通过。

headless 编辑器扫描未出现脚本／资源错误；退出仍有改动前已存在的 1 个 ObjectDB 实例泄漏警告。本关实际启动、流程测试和渲染运行无该警告。

端到端脚本载入磁盘上的实际关卡、八张任务图和三个配表，自动接入正式玩家、镜头、HUD、常驻执行器与任务执行器。通过真实玩家的距离交互、实际 Area3D 进入、真实机关动画和背包授予推进；不直接设置任务完成状态或伪造完成事件。远距离路段使用测试传送定位；石阶、升降台、后院平台到后门、室内楼梯另外通过正式玩家的真实移动与碰撞验证。

检查未接任务、未激活后续敌人、重复击败、同组未清空、升降机到位但未入屋、门运动未结束、重复取钥匙等情况。双敌组以相反顺序交互，确认顺序无关。最终检查八项任务及整个事件均完成。

最后一个阶段还暂时移除背包钥匙再与门锁交互，确认没有钥匙时门保持锁定且任务不完成；恢复钥匙后正常解锁。任务结束后 HUD 保留完成提示。

原有配表通过工作表名称匹配后逐行对比构建前副本：`levels.xlsx`、`events.xlsx`、`dialogues.xlsx` 的全部既有作者行保留，计数器允许单调增加。工作表在 ZIP 内的物理编号可能变化，不以 sheet 文件编号比较内容。

## 渲染

使用实际 Godot Metal Forward+ 渲染保存 `01_spawn.png`、`02_overview.png`、`03_house.png`、`04_interior.png`，检查远处小房子、黄昏光照、院门落石、后院升降机和室内空间。截图来自实际关卡，无外部图片拼接。

这是白盒关卡：敌人为交互占位体；没有新增战斗 AI、美术模型或新角色能力。
