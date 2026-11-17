# 构建和发布插件

源码目录就是可分发的插件本体，不在打包时改写路径。作者作品在 `content/`，不进入安装 ZIP。文档和开发测试也不进入 ZIP。

## 本地构建

```bash
python3 tools/release/build.py --version 0.1.0 --godot /path/to/godot
python3 tools/release/verify.py dist/GodotLevelEditor-0.1.0.zip --godot /path/to/godot
```

有图形环境时可给验证命令加 `--visual`，生成实际编辑窗口截图。`dist/` 已忽略，不提交生成的 ZIP。

验证会在临时空工程中安装，只启用主插件，检查内置素材、原生场景另存与关卡 ID、角色／相机／HUD 试玩及全部示例的运行加载，再替换插件模拟更新，比较用户作品的文件哈希。日志位于 `dist/verification/`；不会打开或修改作者工程。

## GitHub 自动流程

- 普通源码提交：保持正常代码工作流，不创建 Release。
- Actions → Plugin package → Run workflow：输入 X.Y.Z 版本号，仅生成安装包和验证日志的 Actions artifacts。
- 推送 `plugin-vX.Y.Z` 标签：构建和验证成功后自动创建 GitHub Release，上传安装 ZIP 与 SHA-256。

```bash
git tag plugin-v0.1.0
git push origin plugin-v0.1.0
```

先把要发布的源码提交并推送，再打标签。标签对应的源码必须完整；工作区中未提交的改动不会进入 GitHub 构建。失败时不会发布安装附件，日志留在该次 Actions。

Releases 下方的 Source code 是 GitHub 自动生成的源码快照，包含 `content/`，与不含地图的安装 ZIP 不同。

## 包内合同

ZIP 只含 `addons/godot_level_editor/`。脚本 UID 随包保留，Godot 导入缓存与 `.import` 侧文件由安装工程生成。`manifest.json` 记录实际引擎版本、文件清单和 SHA-256。插件代码 MIT，第三方素材的许可与来源证据随包保留。
