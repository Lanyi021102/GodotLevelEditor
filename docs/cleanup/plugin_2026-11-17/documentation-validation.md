# 双语文档与宣传原图验证 · 2026-11-17

## 本次范围

- README.md / README.en.md 成对提供语言链接、功能介绍与真实截图；明确面向零代码基础的关卡设计新人，方便制作和试玩白盒关卡。
- Wiki 当前 21 页分别提供中文与英文，共 42 个生成页面；原始专项接口和历史记录保留原文，并显示说明。英文指南对照关键中文界面标签，不改技术 ID、路径和工作表名。
- 中文原网址保留，英文位于 /en/，顶部语言菜单在首页和具体文章之间保持对应页面。
- Pages 来源从旧 gh-pages 分支切换为 GitHub Actions；文档改动由既有 Wiki 工作流构建、检查和部署。

## 原图来源

用已发布的 dist/GodotLevelEditor-0.1.0.zip 在临时工程解包，运行：

```sh
python3 tools/readme_media/capture.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

脚本在临时工程创建庭院，捕获原生编辑窗口、轮盘、机关图、NPC 库、任务图与天空编辑器；试玩部分直接读取实际 SubViewport 渲染帧，按目标尺寸重新渲染，未做图片合成、重绘或添加宣传文案。任务示例 start → delay → task_complete 调用实际图校验通过。庭院和示例配表均为临时内容，不写入作者地图或安装包。

11 张 PNG 的尺寸、大小和 SHA-256 见 media-manifest.json。公共图片源位于 docs/wiki/assets/readme/；本地输出 exports/promo_2026-11-17/，ZIP 只包含这 11 张 PNG，不含日志或说明文件。

完整捕获最终输出 MEDIA_EDITOR_OK、MEDIA_PLAY_OK，进程退出成功。保留已知退出时 1 个 ObjectDB 实例警告；本次不声称修复引擎退出问题。

## 检查

- python3 tools/wiki/wiki.py check：严格构建及 42 个双语页面的链接、锚点、图片和当前指南搜索检查通过，详细结果见 wiki-check.json。
- 浏览器实际检查中文首页及英文首页、文章语言切换、真实截图显示。英文 whitebox 搜索返回 7 个结果，中文“出生点”返回 4 个结果。
- 英文安装页实机浏览器截图：wiki-english.jpg。
- 原创宣传图片不叠加说明；沿用实际短名称，不增加装饰前缀。英文说明使用描述性翻译，未改插件中文 UI、稳定 ID 或作者资源。
- 本次文档／媒体改动不改变已发布插件；安装、更新和玩家操作的验证继续以本目录 validation.md 与 Release CI 结果为依据。
