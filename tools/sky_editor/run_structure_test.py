#!/usr/bin/env python3
"""Exercise sky UI/save/binding in private development and plugin-only projects."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import signal

from run_qa_import_test import ROOT, run


def hashes(folder):
    return {str(path.relative_to(folder)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in folder.rglob("*") if path.is_file()}


def prepare(output, scenario):
    project = output / scenario
    if project == ROOT or ROOT.is_relative_to(project):
        raise SystemExit("Refusing source project as test path")
    marker = project / ".sky-structure-copy"
    if project.exists() and not marker.exists():
        raise SystemExit(f"Unmarked test path: {project}")
    if project.exists():
        shutil.rmtree(project)
    project.mkdir(parents=True, exist_ok=True)
    marker.write_text("Disposable sky structure QA copy")
    shutil.copytree(ROOT / "addons/godot_level_editor", project / "addons/godot_level_editor",
                    dirs_exist_ok=True, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    shutil.copytree(ROOT / "tools/sky_editor", project / "tools/sky_editor",
                    dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__"))
    if scenario == "development":
        shutil.copytree(ROOT / "content", project / "content", dirs_exist_ok=True)
        # Development maps can reference their own test actor/HUD scripts.
        shutil.copytree(ROOT / "tools", project / "tools", dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("__pycache__", "node_modules"))
    (project / "project.godot").write_text('''config_version=5
[application]
config/name="Sky structure QA"
config/features=PackedStringArray("4.7", "Forward Plus")
config/use_custom_user_dir=true
config/custom_user_dir_name="CodexQA/GodotLevelEditor/structure-sky-20261117-%s"
%s
[editor_plugins]
enabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg")
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
''' % (scenario + "-" + hashlib.sha256(str(project).encode()).hexdigest()[:8], 'run/main_scene="res://content/scenes/main.tscn"' if scenario == "development" else ""))
    return project


def redirect(project, script):
    plugin = project / "addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd"
    source = (ROOT / "addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd").read_text()
    plugin.write_text(source.replace('"res://tools/sky_editor/editor_test.gd"',
                                     f'"res://tools/sky_editor/{script}.gd"'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--output", type=Path, default=ROOT / ".validation/structure-qa-2026-11-17/sky")
    parser.add_argument("--scenario", choices=["development", "blank", "both"], default="both")
    parser.add_argument("--metal", action="store_true")
    parser.add_argument("--regression", action="store_true")
    parser.add_argument("--standard-entry", action="store_true", help="also exercise the normal editor_test.gd entry")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    before = hashes(ROOT / "content")
    (output / "source-content-before.json").write_text(json.dumps(before, indent=2))
    results = {}
    scenarios = ["development", "blank"] if args.scenario == "both" else [args.scenario]
    for scenario in scenarios:
        project = prepare(output, scenario)
        logs = output / (scenario + "-logs")
        logs.mkdir(exist_ok=True)
        redirect(project, "editor_test" if args.standard_entry else "structure_test")
        code, log = run(args.godot, project, logs / "import.log", ["--headless", "--editor", "--import", "--quit"])
        results[scenario + "/import"] = code == 0 and "SCRIPT ERROR" not in log
        options = (["--editor"] if args.metal else ["--headless", "--editor"]) + ["--", "--sky-editor-test", f"--sky-structure-scenario={scenario}"]
        if args.metal:
            options.append(f"--sky-structure-capture={logs}")
        code, log = run(args.godot, project, logs / "flow.log", options)
        prefix = "SKY_EDITOR_RESULT" if args.standard_entry else "SKY_STRUCTURE_RESULT"
        results[scenario + "/flow"] = code == 0 and prefix in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
        if args.regression:
            redirect(project, "ui_test")
            options = (["--editor"] if args.metal else ["--headless", "--editor"]) + ["--", "--sky-editor-test"]
            if args.metal:
                options.append(f"--sky-ui-capture={logs}")
            code, log = run(args.godot, project, logs / "ui.log", options)
            results[scenario + "/ui"] = code == 0 and "SKY_UI_RESULT" in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
            redirect(project, "qa_import_test")
            options = (["--editor"] if args.metal else ["--headless", "--editor"]) + ["--", "--sky-editor-test"]
            if args.metal:
                options.append(f"--qa09-capture={logs}")
            code, log = run(args.godot, project, logs / "hdri.log", options)
            results[scenario + "/hdri"] = code == 0 and "QA09_IMPORT_RESULT" in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
            code, log = run(args.godot, project, logs / "runtime.log", ["--headless", "res://tools/sky_editor/runtime_test.tscn"])
            results[scenario + "/runtime"] = code == 0 and "failures=0" in log and "SCRIPT ERROR" not in log
    after = hashes(ROOT / "content")
    results["source_content_unchanged"] = before == after
    (output / "source-content-after.json").write_text(json.dumps(after, indent=2))
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results), flush=True)
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    def stop_owned_test(signum, _frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, stop_owned_test)
    raise SystemExit(main())
