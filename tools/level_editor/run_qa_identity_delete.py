#!/usr/bin/env python3
"""Verify QA-02/QA-10 in a complete disposable project with private user data."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--before-dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="godot-qa-level-"))
    project = scratch / "project"; project.mkdir()
    original_books = {p.name: digest(p) for p in (root / "content/tables").glob("*.xlsx")}
    for name in ["addons", "addons/godot_level_editor/assets", "content/resources", "content/scenes", "addons/godot_level_editor/scripts", "tools", "content/tables"]:
        shutil.copytree(root / name, project / name, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for name in ["project.godot", "icon.svg"]:
        shutil.copy2(root / name, project / name)
    if args.before_dir:
        for name in ["addons/godot_level_editor/modules/godot_level_editor/plugin.gd", "addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd", "addons/godot_level_editor/modules/godot_level_editor_suite/level_warehouse.gd"]:
            shutil.copy2(args.before_dir / name, project / name)
    config = project / "project.godot"
    config.write_text(config.read_text().replace('config/name="GodotLevelEditor"', 'config/name="QA-Level-' + scratch.name + '"'))
    plugin = project / "addons/godot_level_editor/modules/godot_level_editor/plugin.gd"
    source = plugin.read_text()
    old = 'load("res://tools/level_editor/editor_smoke.gd")'
    if source.count(old) != 1:
        raise RuntimeError("Isolated test-hook target changed; refusing to patch")
    plugin.write_text(source.replace(old, 'load("res://tools/level_editor/test_qa_identity_delete.gd")').replace("await smoke.run(self)", "await smoke.new().run(self)"))
    manifest = {"source": str(root), "project": str(project), "private_user_name": "QA-Level-" + scratch.name, "baseline": str(args.before_dir) if args.before_dir else None}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2))
    # Import and test are sequential; neither uses the original .godot directory.
    command = [args.godot, "--headless", "--editor", "--path", str(project), "--quit"]
    with (output / "import.log").open("w") as log:
        imported = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    import_text = (output / "import.log").read_text()
    if imported.returncode or "SCRIPT ERROR:" in import_text:
        print("Import failed; see", output / "import.log"); return 2
    command = [args.godot] + ([] if args.render else ["--headless"]) + ["--editor", "--path", str(project), "--", "--godot-level-editor-level-smoke"]
    if args.render:
        command.append("--qa-capture=" + str(output / "native_duplicate.png"))
    (output / "command.json").write_text(json.dumps(command, ensure_ascii=False, indent=2))
    with (output / "checks.log").open("w") as log:
        checked = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=100)
    script_errors = "SCRIPT ERROR:" in (output / "checks.log").read_text()
    current_books = {p.name: digest(p) for p in (root / "content/tables").glob("*.xlsx")}
    manifest["source_workbooks_unchanged"] = current_books == original_books
    manifest["exit_code"] = checked.returncode
    manifest["script_errors"] = script_errors
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    print("Evidence:", output)
    print("Disposable project:", project)
    print("Original workbooks unchanged:", manifest["source_workbooks_unchanged"])
    print("Test exit:", checked.returncode)
    return (checked.returncode or (4 if script_errors else 0)) if manifest["source_workbooks_unchanged"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
