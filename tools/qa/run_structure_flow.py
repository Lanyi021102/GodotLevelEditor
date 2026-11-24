#!/usr/bin/env python3
"""Exercise native authoring in a disposable project or addon-only consumer."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULE = Path("addons/godot_level_editor/modules/godot_level_editor_suite")
TEST = Path("tools/qa/structure_flow_test.gd")


def hashes():
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (ROOT / "content").rglob("*") if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--consumer", action="store_true")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--authoring", action="store_true", help="Check workbench, catalogs, row actions and sky previews")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    project = Path(tempfile.mkdtemp(prefix="godot-structure-qa-"))
    before = hashes()
    shutil.copytree(ROOT / "addons", project / "addons")
    test = TEST.with_name("authoring_test.gd") if args.authoring else TEST
    (project / test.parent).mkdir(parents=True)
    shutil.copy2(ROOT / test, project / test)
    if args.consumer:
        settings = '''config_version=5
[application]
config/name="Structure Consumer QA"
[editor_plugins]
enabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
'''
    else:
        shutil.copytree(ROOT / "content", project / "content")
        shutil.copytree(ROOT / "tools", project / "tools", dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        shutil.copy2(ROOT / "icon.svg", project / "icon.svg")
        settings = (ROOT / "project.godot").read_text()
    settings = settings.replace("[application]", '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="CodexQA/' + project.name + '"')
    (project / "project.godot").write_text(settings)
    plugin = project / MODULE / "plugin.gd"
    hook = 'await load("res://tools/godot_level_editor_suite/startup_test.gd").new().run(self)'
    source = plugin.read_text()
    if source.count(hook) != 1:
        raise RuntimeError("Private startup hook changed")
    plugin.write_text(source.replace(hook, 'await load("res://' + str(test) + '").new().run(self)'))
    result = dict(project=str(project), consumer=args.consumer, render=args.render)
    (output / "result.json").write_text(json.dumps(result, indent=2))
    try:
        with (output / "import.log").open("w") as log:
            imported = subprocess.run([args.godot, "--headless", "--editor", "--path", str(project), "--import", "--quit"], stdout=log, stderr=subprocess.STDOUT, timeout=150)
        if imported.returncode or "SCRIPT ERROR:" in (output / "import.log").read_text():
            raise RuntimeError("Private project import failed")
        command = [args.godot] + ([] if args.render else ["--headless"])
        command += ["--editor", "--path", str(project), "--", "--startup-lazy-test", "--qa-output=" + str(output)]
        with (output / "checks.log").open("w") as log:
            tested = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=150)
        log = (output / "checks.log").read_text()
        # Godot 4.7.1 emits this debugger teardown error even on an untouched
        # editor baseline. Keep it in raw logs and distinguish it explicitly.
        errors = [line for line in log.splitlines() if line.startswith("ERROR:") and line != "ERROR: Plugin is not attached to debugger."]
        marker = "AUTHORING FLOW:" if args.authoring else "STRUCTURE FLOW:"
        result.update(exit=tested.returncode, passes=log.count("[PASS]"), failures=log.count("[FAIL]"), script_errors=log.count("SCRIPT ERROR:"), engine_errors=errors, finished=marker in log)
    finally:
        result["source_content_unchanged"] = hashes() == before
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    uid = test.with_suffix(".gd.uid")
    if (project / uid).exists() and not (ROOT / uid).exists():
        shutil.copy2(project / uid, ROOT / uid)
    print(json.dumps(result, indent=2))
    return int(bool(result.get("exit") or result.get("failures") or result.get("script_errors") or result.get("engine_errors") or not result.get("finished") or not result["source_content_unchanged"]))


if __name__ == "__main__":
    raise SystemExit(main())
