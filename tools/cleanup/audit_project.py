#!/usr/bin/env python3
"""Read-only inventory for project hygiene; never deletes unreferenced assets."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIRS = ["addons", "addons/godot_level_editor/assets", "content/resources", "content/scenes", "addons/godot_level_editor/scripts", "tools"]
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".gdshader", ".godot", ".json"}


def tree_size(path):
    if path.is_symlink():
        return path.lstat().st_size
    if path.is_file():
        return path.stat().st_size
    return sum(p.lstat().st_size for p in path.rglob("*") if p.is_file() or p.is_symlink())


def opened_resources():
    path = ROOT / ".godot/editor/editor_layout.cfg"
    if not path.exists():
        return []
    result = []
    for line in path.read_text().splitlines():
        if line.startswith(("open_scenes=", "open_scripts=")):
            result.extend(re.findall(r'"(res://[^"\n]+)"', line))
    return sorted(set(result))


def audit():
    refs = defaultdict(set)
    strict_missing = []
    files = [ROOT / "project.godot"]
    for folder in SOURCE_DIRS:
        files.extend(p for p in (ROOT / folder).rglob("*") if p.is_file() and p.suffix in TEXT_SUFFIXES)
    literal = re.compile(r'res://[^\s"\'<>\)\],;]+')
    for path in files:
        try:
            source = path.read_text()
        except (OSError, UnicodeError):
            continue
        relative = path.relative_to(ROOT).as_posix()
        for target in literal.findall(source):
            refs[target.split("::")[0]].add(relative)
        required = re.findall(r'\b(?:preload|load)\(\s*["\'](res://[^"\']+)["\']\s*\)', source) if path.suffix == ".gd" else re.findall(r'^\[ext_resource[^\n]*\bpath="(res://[^"]+)"', source, re.M)
        for target in required:
            if not (ROOT / target[6:]).exists():
                strict_missing.append({"source": relative, "target": target})
    opened = opened_resources()
    temporary = []
    pattern = re.compile(r'^(?:\.canvas_(?:test|fixture)_|\.reference_fixture_|native_drag_probe_|quick_add_probe_).+\.(?:tscn|tres)$')
    for path in (ROOT / "tools").rglob("*"):
        if path.is_file() and pattern.match(path.name):
            name = path.relative_to(ROOT).as_posix()
            temporary.append({"path": name, "bytes": path.stat().st_size, "opened": "res://" + name in opened, "literal_referrers": sorted(refs["res://" + name])})
    imports = [p.relative_to(ROOT).as_posix() for p in (ROOT / "docs").rglob("*.import") if p.is_file()]
    projects = []
    if (ROOT / ".validation").exists():
        roots = []
        for project in sorted((ROOT / ".validation").rglob("project.godot"), key=lambda p: len(p.parts)):
            folder = project.parent
            if any(folder.is_relative_to(old) for old in roots):
                continue
            roots.append(folder)
            projects.append({"path": folder.relative_to(ROOT).as_posix(), "bytes": tree_size(folder)})
    return {
        "source": str(ROOT),
        "opened_resources": opened,
        "validation_project_copies": projects,
        "document_import_sidecars": imports,
        "temporary_scenes": temporary,
        "missing_required_literal_paths": strict_missing,
        "limits": "A missing literal is not proof of a missing runtime dependency, and no incoming literal is not proof an authored asset is unused. Dynamic paths, XLSX records and binary resources require separate checks. No deletion is performed.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = audit()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({
        "project_copy_count": len(result["validation_project_copies"]),
        "project_copy_bytes": sum(p["bytes"] for p in result["validation_project_copies"]),
        "document_import_count": len(result["document_import_sidecars"]),
        "temporary_scene_count": len(result["temporary_scenes"]),
        "protected_open_scene_count": sum(p["opened"] for p in result["temporary_scenes"]),
        "missing_literal_count": len(result["missing_required_literal_paths"]),
        "output": str(args.output) if args.output else None,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
