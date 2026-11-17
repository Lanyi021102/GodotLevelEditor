#!/usr/bin/env python3
"""Check current Wiki pages against the generated site's actual URLs and IDs."""

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.links = []
        self.ids = set()
        self.feed(path.read_text(encoding="utf-8"))

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if "id" in values:
            self.ids.add(values["id"])
        attribute = "href" if tag in ("a", "link") else "src"
        if tag in ("a", "link", "img", "script") and values.get(attribute):
            self.links.append((tag, values[attribute]))


def check(site):
    errors, checked, images = [], 0, 0
    parsed = {}
    sources = [ROOT / "docs/index.md"] + sorted(p for p in (ROOT / "docs/wiki").rglob("*.md") if not p.stem.endswith(".en"))
    pages_checked = 0
    for source in sources:
        relative = source.relative_to(ROOT / "docs")
        for locale in ("zh", "en"):
            translated = source if locale == "zh" else source.with_name(source.stem + ".en.md")
            label = str(relative) if locale == "zh" else "en/" + str(relative)
            if not translated.exists():
                errors.append(f"缺少英文页面：{relative}")
                continue
            prefix = Path() if locale == "zh" else Path("en")
            built = site / prefix / relative.with_suffix("") / "index.html"
            if relative.name == "index.md":
                built = site / prefix / relative.parent / "index.html"
            if not built.exists():
                errors.append(f"缺少页面：{built.relative_to(site)}")
                continue
            pages_checked += 1
            page = parsed.setdefault(built, Page(built))
            if locale == "en" and 'lang="en"' not in built.read_text(encoding="utf-8"):
                errors.append(f"英文页面语言标记错误：{label}")
            for tag, url in page.links:
                parts = urlsplit(url)
                if parts.scheme or parts.netloc:
                    continue
                path = unquote(parts.path)
                if path.startswith("/"):
                    mount = "/GodotLevelEditor/"
                    path = path[len(mount):] if path.startswith(mount) else path.lstrip("/")
                    target = site / path
                else:
                    target = built.parent / path if path else built
                target = target.resolve()
                if target.is_dir():
                    target /= "index.html"
                try:
                    target.relative_to(site)
                except ValueError:
                    errors.append(f"{label}：链接越出站点：{url}")
                    continue
                checked += 1
                images += tag == "img"
                if not target.is_file():
                    errors.append(f"{label}：缺少目标：{url}")
                    continue
                fragment = unquote(parts.fragment)
                if fragment and target.suffix == ".html":
                    destination = parsed.setdefault(target, Page(target))
                    if fragment not in destination.ids:
                        errors.append(f"{label}：缺少锚点：{url}")
    search_count = 0
    expected = {"wiki/getting-started/", "wiki/features/", "wiki/guides/levels/", "wiki/tutorials/button-door/", "wiki/faq/", "wiki/development/"}
    for locale in ("zh", "en"):
        prefix = Path() if locale == "zh" else Path("en")
        search_file = site / prefix / "search/search_index.json"
        shared = not search_file.is_file()
        if shared:
            search_file = site / "search/search_index.json"
        if not search_file.is_file():
            errors.append(f"缺少 {locale} 搜索索引")
            continue
        index = json.loads(search_file.read_text(encoding="utf-8"))
        documents = index.get("docs", [])
        # static-i18n shares the root index across locales by default.
        if shared or locale == "zh":
            documents = [item for item in documents if urlsplit(item["location"]).path.startswith("en/") == (locale == "en")]
        search_count += len(documents)
        locations = {urlsplit(item["location"]).path.removeprefix("en/") for item in documents}
        for location in locations:
            if location and not location.startswith("wiki/"):
                errors.append(f"{locale} 旧专项资料误入主搜索：{location}")
        for location in expected - locations:
            errors.append(f"{locale} 搜索未收录：{location}")
        text = " ".join(item.get("title", "") + item.get("text", "") for item in documents)
        text = text.replace("\u200b", "").replace(" ", "").lower()
        keywords = ["按钮", "出生点", "任务", "另存为"] if locale == "zh" else ["button", "spawn", "task", "whitebox"]
        for keyword in keywords:
            if keyword not in text:
                errors.append(f"{locale} 搜索缺少关键词：{keyword}")
        if not index.get("config", {}).get("lang"):
            errors.append(f"{locale} 搜索索引未配置语言")
    return {"ok": not errors, "languages": ["zh", "en"], "wiki_pages": pages_checked, "checked_local_links": checked, "image_references": images, "search_records": search_count, "errors": errors}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", type=Path, default=ROOT / "site")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    result = check(args.site.resolve())
    output = json.dumps(result, ensure_ascii=False, indent=2)
    print(output)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(output + "\n", encoding="utf-8")
    sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
