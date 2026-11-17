"""Keep existing module records readable without mixing them into user search."""

import re
import posixpath
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
REPOSITORY = "https://github.com/Lanyi021102/GodotLevelEditor/blob/main/"


def on_pre_build(config):
    # MkDocs preserves hidden files while cleaning. Keep the generated copy of
    # documentation images out of Godot's importer, including during rebuilds.
    site = Path(config["site_dir"])
    site.mkdir(parents=True, exist_ok=True)
    (site / ".gdignore").touch(exist_ok=True)


def on_page_markdown(markdown, page, config, files):
    uri = page.file.src_uri
    if uri == "index.md" or uri.startswith("wiki/"):
        return markdown

    page.meta.setdefault("search", {})["exclude"] = True
    # Links out of docs point to source files on GitHub, rather than nonexistent
    # generated HTML pages. Links between existing module docs stay local.
    def source_link(match):
        label, target = match.groups()
        if ":" in target or target.startswith(("#", "/")):
            return match.group(0)
        path, _, fragment = target.partition("#")
        resolved = (Path(page.file.abs_src_path).parent / path).resolve()
        try:
            document_path = resolved.relative_to(DOCS)
            attachment = files.get_file_from_path(document_path.as_posix())
            if attachment is None or attachment.inclusion.is_excluded():
                return f"{label}（历史附件未随站点提供：`{path}`）"
            return match.group(0)
        except ValueError:
            try:
                relative = resolved.relative_to(ROOT)
            except ValueError:
                return match.group(0)
            return f"[{label}]({REPOSITORY}{relative.as_posix()}" + (f"#{fragment}" if fragment else "") + ")"

    markdown = re.sub(r"(?<!!)\[([^\]]+)\]\(([^\s)]+)\)", source_link, markdown)
    notice = (
        '!!! note "专项资料与阶段记录"\n'
        '    本页保留模块说明、接口或阶段验证，可能同时包含历史条款。'
        '当前操作先看 [Wiki 首页](' + posixpath.relpath("index.md", posixpath.dirname(uri) or ".") + ')；'
        '功能边界以模块最新覆盖说明与实际实现为准。\n\n'
    )
    return notice + markdown
