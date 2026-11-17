#!/usr/bin/env python3
"""Validate the sky UI in a private Godot project and user-data directory."""
import argparse
import json
from pathlib import Path
import re
import shutil
from run_qa_import_test import ROOT, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--output", type=Path, default=ROOT / ".validation/sky-ui-2026-11-16")
    parser.add_argument("--metal", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve(); project = output / "project"
    if project == ROOT or ROOT.is_relative_to(project): raise SystemExit("Refusing source project as test path")
    marker = project / ".sky-ui-copy"
    if project.exists() and not marker.exists(): raise SystemExit("Unmarked test path")
    project.mkdir(parents=True, exist_ok=True); marker.write_text("Disposable sky UI test copy")
    for name in ["addons/godot_level_editor", "content", "tools"]:
        shutil.copytree(ROOT / name, project / name, dirs_exist_ok=True, ignore=shutil.ignore_patterns("node_modules", "__pycache__", ".godot"))
    for name in ["project.godot", "icon.svg"]: shutil.copy2(ROOT / name, project / name)
    config = project / "project.godot"
    text = re.sub(r"(?m)^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n", "", config.read_text())
    config.write_text(text.replace("[application]\n", '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="CodexQA/GodotLevelEditor/sky-ui-20261116"\n', 1))
    plugin = project / "addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd"
    original = plugin.read_text()
    plugin.write_text(original.replace('"res://tools/sky_editor/editor_test.gd"', '"res://tools/sky_editor/ui_test.gd"'))
    results = {}
    code, log = run(args.godot, project, output / "import.log", ["--headless", "--editor", "--import", "--quit"])
    results["import"] = code == 0 and "SCRIPT ERROR" not in log
    code, log = run(args.godot, project, output / "ui_headless.log", ["--headless", "--editor", "--", "--sky-editor-test"])
    results["ui_headless"] = code == 0 and "SKY_UI_RESULT" in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
    code, log = run(args.godot, project, output / "runtime.log", ["--headless", "res://tools/sky_editor/runtime_test.tscn"])
    results["runtime"] = code == 0 and "failures=0" in log and "SCRIPT ERROR" not in log
    if args.metal:
        code, log = run(args.godot, project, output / "ui_metal.log", ["--editor", "--", "--sky-editor-test", f"--sky-ui-capture={output}"])
        results["ui_metal"] = code == 0 and "SKY_UI_RESULT" in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
    plugin.write_text(original.replace('"res://tools/sky_editor/editor_test.gd"', '"res://tools/sky_editor/qa_import_test.gd"'))
    code, log = run(args.godot, project, output / "import_regression.log", ["--headless", "--editor", "--", "--sky-editor-test"])
    results["import_regression"] = code == 0 and "QA09_IMPORT_RESULT" in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
    plugin.write_text(original)
    code, log = run(args.godot, project, output / "editor_contract.log", ["--headless", "--editor", "--", "--sky-editor-test"])
    results["editor_contract"] = code == 0 and "SKY_EDITOR_RESULT" in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(results)
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
