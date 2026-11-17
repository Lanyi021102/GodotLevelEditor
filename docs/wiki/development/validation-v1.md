---
search:
  exclude: true
---

# Wiki V1 验证记录

本页记录 2026-11-16 的本版文档检查。已有机关、任务和关卡专项测试记录仍保留其原始日期，不作为本次复测结果。

## 修改范围

新增 `mkdocs.yml`、`requirements-wiki.txt`、`docs/index.md`、`docs/wiki/`、`tools/wiki/`、`打开Wiki.command` 和 `.github/workflows/wiki.yml`。根 README、AGENTS 及 `.gitignore` 仅增加 Wiki 入口与维护约定。

本任务不修改游戏脚本、场景、图资源、配表或用户关卡。工作区已有其他聊天的未提交更改，未合并为本版 Wiki 的功能改动。

## 检查结果

| 检查 | 实际结果 |
|---|---|
| MkDocs 严格构建 | 通过，13 个 Wiki 页面；原有专项资料继续生成 |
| 当前 Wiki 的链接、锚点、图片与搜索范围 | `tools/wiki/check.py` 通过，无失效的当前指南链接 |
| 桌面浏览器 | Chromium，1440 × 1050；首页、机关教程与图片正常，无页面横向溢出 |
| 手机尺寸浏览器 | Chromium，390 × 844；首页正常，折叠菜单可进入快速开始，无页面横向溢出 |
| 中文搜索 | “按钮开门”8 页、“出生点”4 页、“任务不启动”10 页、“另存为”6 页；检查时的结果数，后续内容更新会变化 |
| 浏览器脚本与资源 | 无页面脚本错误，教程图片全部加载 |
| Python 与启动脚本 | Python 编译检查、`zsh -n 打开Wiki.command` 通过 |
| 工程 headless 导入 | 独立副本 Godot 4.7.1 导入成功；退出仍有 1 条 ObjectDB 泄漏提示，未宣称修复 |
| 教程机关运行 | 独立副本 `tools/mechanisms/whitebox_v1/test_runtime.tscn`，74 项检查、0 失败 |

本次只复测了导入与机关运行，不将历史任务、NPC、天空或其他专项检查算成本次通过项。没有手动覆盖用户关卡来演示教程。

## 预览与证据

[桌面首页](../assets/wiki-home-desktop.png) · [中文搜索](../assets/wiki-search-desktop.png) · [手机首页](../assets/wiki-home-mobile.png)

本地复测日志、机器检查结果与其他截图保存在 `.validation/wiki-v1/`，不作为网站正文的第二份来源。

内置浏览器连接超时，本次实际页面检查改用独立 Playwright / Chromium。文档构建依赖与浏览器测试环境各自隔离，不加入游戏运行依赖。

## 已知边界

原有专项文档保留阶段记录，其中一处旧自动分组锚点仍有构建信息提示。部分旧日志或 JSON 附件未随站点提供，构建时显示为历史附件文字；它们不进入当前 Wiki 搜索，也不作为新指南的有效链接计数。

Wiki 的可编辑源文件和自动发布工作流在当前工程工作区中。本次静态发布使用独立 `gh-pages` 分支；若要从 `main` 自动更新，需提交源文件与工作流并切换 Pages 来源，见 [预览与发布](publishing.md)。
