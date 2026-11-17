# 预览与发布

Wiki 使用 MkDocs、Material 主题与 static-i18n 双语路由。所有正文保存在项目中，运行游戏不需要安装这套文档依赖。

## 本地打开

macOS 双击工程根目录的 **打开Wiki.command**。首次使用会在工程内 `.venv-wiki` 安装固定版本的文档依赖，需要网络；之后启动本地预览并打开浏览器。

Windows 或终端使用者，在工程根执行：

```sh
python3 tools/wiki/wiki.py setup
python3 tools/wiki/wiki.py serve --open
```

Windows 上可将 `python3` 替换为 `py -3`。默认本地地址是 `http://127.0.0.1:8765/GodotLevelEditor/`；以终端打印的实际地址为准。保存 Markdown 后页面自动更新。停止预览时在该终端按 Ctrl+C。

若端口被占用，可以执行 `python3 tools/wiki/wiki.py serve --port 8766 --open`。

## 构建和检查

```sh
python3 tools/wiki/wiki.py build
python3 tools/wiki/wiki.py check
```

`build` 生成 `site/`；`check` 会先重新构建，再检查当前 Wiki 的页面链接、锚点、图片资源和中英文搜索索引。生成网站应通过 HTTP 服务访问，直接双击 HTML 不等同于完整预览。

`docs/.gdignore` 让 Godot 跳过文档资源导入；构建钩子也会在输出目录生成 `.gdignore`，避免网站中的图片副本再次触发导入。保留这些标记；它们不影响 Wiki 图片、截图写入和网站构建。文档图片不要作为游戏场景的 `load/preload` 依赖，实际游戏资源应放在 `addons/godot_level_editor/assets/` 或 `content/resources/`。

## GitHub Pages 发布

当前 Pages 来源为 **GitHub Actions**，由 `main` 中的 Markdown 自动构建。早期 `gh-pages` 分支为旧站点产物，当前不再作为发布来源。

项目提供 `.github/workflows/wiki.yml`：

- Pull Request 改动 Wiki 时，执行构建和链接检查。
- 推送到 `main` 的相关文档改动通过检查后，上传并发布 Pages 网站。
- 也可在 GitHub Actions 中手动运行 **Wiki** 工作流。

仓库 **Settings → Pages → Build and deployment → Source** 已设置为 **GitHub Actions**。提交并推送相关文档后，发布任务会运行。本地构建成功不代表线上网站已经更新。

中文网址为 `https://lanyi021102.github.io/GodotLevelEditor/`，英文在其 `/en/` 下；页面顶部可切换语言。只有 GitHub 的部署结果成功并返回网址后，才可将它作为已发布链接分享。

仓库换名、托管地址变更时，更新 `mkdocs.yml` 的 `site_url`、`repo_url`，以及 `tools/wiki/hooks.py` 的源码链接基址。

## 发布哪些内容

发布产物包含本 Wiki、原有专项 Markdown 及其文档附件。旧资料不加入 Wiki 主导航与搜索，但会通过维护索引链接提供查阅。

发布前检查 `docs/` 中新增资料是否适合对外提供。游戏存档、环境变量和本机 Python 环境不属于文档产物。

## 依赖与后续维护

`requirements-wiki.txt` 固定 MkDocs、主题和中文分词依赖版本。需要升级时先在独立环境安装，再执行构建、链接检查与浏览器检查。全站使用系统字体，正文和搜索不依赖在线字体或额外搜索服务。

官方资料：[MkDocs 入门](https://www.mkdocs.org/getting-started/) · [Material 搜索配置](https://squidfunk.github.io/mkdocs-material/setup/setting-up-site-search/) · [GitHub Pages 自定义工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。
