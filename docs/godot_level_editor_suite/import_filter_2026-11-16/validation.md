# 文档图片导入优化验证

日期：2026-11-16。Godot：4.7.1.stable.official.a13da4feb。

## 原因与修改范围

用户确认等待发生在 Godot 的“导入／重新导入资源”进度条。检查时 `docs/` 有 208 张图片、约 66.01 MiB；本机生成的 `site/` 有 209 张图片、约 66.01 MiB。文档截图和网站副本均不需要成为 Godot 资源；此前文档目录出现在 Godot 文件系统缓存中。Git 忽略 `site/` 并不能排除 Godot 扫描。

- 新增 `docs/.gdignore`，跳过文档扫描与导入，保留全部原始截图及已有 sidecar。
- MkDocs `on_pre_build` 在输出目录生成 `.gdignore`；本项目固定版本的 MkDocs 清理函数保留隐藏文件，因此构建期间也保留排除标记。
- 保留全部游戏资源、素材预览、插件图标和 `.godot/` 缓存。本次不调整素材目录卡片加载、游戏渲染、场景、配表和用户资源。
- 同步套件 INTERFACES、Wiki FAQ、发布指南与版本记录。现有中文产品名与操作术语保持，没有新增装饰前缀。

## 实测

1. `python3 tools/wiki/wiki.py check` 通过：16 页当前 Wiki、978 个本地链接、43 个图片引用、131 条搜索记录，错误为零；网站图片仍正常构建，`site/.gdignore` 存在。
2. `Godot --headless --editor --path /Users/lanyi/branch --import` 退出码 0，无脚本或资源错误。更新后的 `filesystem_cache10` 不包含 `res://docs/` 和 `res://site/`，仍包含 `assets/` 与 `resources/`。
3. 用现有 `resources/mechanisms/whitebox_v1/previews/button.png` 的字节分别创建 docs、site、resources 三处临时 PNG，重新执行 headless 导入。docs/site 两处均不生成 `.import`；resources 正常生成有效 `.import`，导入日志没有 ERROR。检查后仅移除本次探针及其导入产物。
4. 探针清理后再执行 headless 导入和 Wiki 检查。清理后的首次扫描曾出现一条 `get_dependencies: Method/function failed`，未提供文件路径；随后加 `--verbose` 复查退出码 0、没有 ERROR，也没有图片重新导入，未能复现该条错误。Wiki 检查再次通过，本地 `.godot/` 缓存保留。

Godot 退出仍报告 1 个 ObjectDB 实例泄漏警告（verbose 指向 UndoRedo）；没有将此警告计为图片导入失败。没有测量用户此前整次等待耗时，因此不承诺具体秒数或加速倍率。首次打开、真实素材更新或缓存清除后仍需要导入游戏资源。

本次只改变资源扫描边界和文档说明，不涉及界面布局，无新增渲染截图。
