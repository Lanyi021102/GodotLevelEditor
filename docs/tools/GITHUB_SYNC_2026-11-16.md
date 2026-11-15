# GodotLevelEditor · GitHub 同步验证

日期：2026-11-16。

将原私有仓库 `Lanyi021102/branch` 改名为 [Lanyi021102/GodotLevelEditor](https://github.com/Lanyi021102/GodotLevelEditor)，与 `project.godot` 的项目名称一致。继续使用原仓库、`main` 分支、提交历史和既有标签；本地目录仍为 `/Users/lanyi/branch`。本地 `origin` 已更新为新地址。

此次同步包含当前脚本、编辑器插件、用户关卡与机关、NPC、资源、XLSX 配表和项目文档。按现有 `.gitignore` 排除 Godot 缓存、本机凭据、日志和导出产物；没有修改运行时接口或场景表现。README 和双机协作文档新增当前仓库地址。

## 独立副本检查

从当前全部非忽略文件生成 Git tree，并导出到临时目录，不携带 `.godot/`。验证使用 Godot `4.7.1.stable.official.a13da4feb`，原项目内容不受导入及测试写入影响。

| 检查 | 结果 |
|---|---|
| `--headless --editor --import --quit` | 退出码 0，无脚本或资源导入错误 |
| 默认入口 `--headless --quit-after 120` | 退出码 0，无错误 |
| `tools/runtime/test_current_world.tscn` | 12 项通过，0 失败 |
| `tools/godot_level_editor_suite/runtime_test.tscn` | 49 项通过，0 失败 |
| `tools/level_editor/test_standalone_play.tscn` | 15 项通过，0 失败 |

共 76 项运行检查通过。无缓存导入退出时仍有 1 条 ObjectDB 实例泄漏警告；上述运行检查没有错误。本次只更新仓库信息，不涉及视觉修改，未新增渲染验收。

源文件最大约 7.3 MiB；同步范围未发现 GitHub 凭据或私钥特征，普通 Git 可上传，无需新增 LFS 配置。另一台电脑应更新远程地址后拉取，并自行进行设备端试玩。
