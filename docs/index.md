---
title: GodotLevelEditor 使用与维护手册
hide:
  - toc
---

<div class="wiki-hero" markdown="1">

<p class="wiki-eyebrow">GODOT LEVEL EDITOR · WIKI</p>

# 从第一个白盒关卡开始

<p class="wiki-lead">面向零代码基础的关卡设计新人：在 Godot 原生视口搭建空间，用节点连接逻辑，使用内置角色直接试玩。</p>

<div class="wiki-meta"><span>插件 0.1.0</span><span>Godot 4.7.1</span><span>中文 / English</span><span>2026-11-17</span></div>

<div class="wiki-actions" markdown="1">

[下载插件](https://github.com/Lanyi021102/GodotLevelEditor/releases/latest){ .md-button .md-button--primary }
[安装与更新](wiki/plugin-install.md){ .md-button }
[开始制作关卡](wiki/getting-started.md){ .md-button }

</div>
</div>

![Godot 原生视口中的白盒关卡](wiki/assets/readme/01_whitebox_editor.png)

## 我想做什么

| 目标 | 从这里进入 |
|---|---|
| 搭建可试玩的白盒空间 | [关卡与轮盘操作](wiki/guides/levels.md) |
| 添加按钮、门和升降台 | [使用独立机关](wiki/tutorials/button-door.md) · [机关速查](wiki/reference/mechanisms.md) |
| 放置 13 个示例 NPC | [NPC 模型与动画](wiki/guides/npc-samples.md) |
| 配置任务、对白和交互 | [功能地图](wiki/features.md) · [台本对话模式](wiki/guides/dialogues.md) |
| 调整阳光、天空与雾 | [天空与环境](wiki/guides/sky.md) |
| 查询快捷键或解决问题 | [术语与快捷键](wiki/reference/glossary.md) · [常见问题](wiki/faq.md) |
| 修改或扩展功能 | [开发维护索引](wiki/development/index.md) |

## 插件与你的工程

插件本体在 `addons/godot_level_editor/`。地图、任务图、Excel 配表属于你自己的工程，默认存放在 `content/`；更新插件不会覆盖这些文件。文件夹统一使用英文名称。

空工程尚未设置主场景时，首次启用插件会创建空白起始场景。按 F5 或普通播放按钮即可操控内置角色。已有工程的主场景与输入绑定继续保留。

## 编辑器如何分工

地图使用 Godot 原生文件系统、场景树、检查器、保存和 F6 试玩；轮盘、白盒、点线面工具扩展原生 3D 视口。GodotLevelEditor 独立窗口编辑常驻关卡逻辑、机关、NPC、任务、台本和天空。

![机关节点与实时预览](wiki/assets/readme/03_mechanism_graph.png)

当前插件包含五种独立机关、13 个示例 NPC、玩家、镜头、HUD 和光照资源。安装 ZIP 包含空白关卡模板，不含作者地图与个人任务、对白数据。页面截图用庭院只用于展示。

!!! tip "语言与搜索"
    页面顶部可切换中文和 English。英文指南保留关键中文界面名称，便于对照。搜索收录两种语言的当前指南；原始技术接口和有日期的历史验证记录从维护索引进入。
