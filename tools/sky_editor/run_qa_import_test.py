#!/usr/bin/env python3
"""Run QA-09 against a private project/cache; never launch the working project."""
import argparse
import json
from pathlib import Path
import re
import shutil
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / ".validation/qa-fixes-2026-11-16/sky"


def run(binary, project, log, args, timeout=180):
    with log.open("w") as stream:
        process = subprocess.Popen([binary, "--path", str(project), *args], stdout=stream,
                                   stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=timeout)
        except BaseException:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait()
            raise
    print(f"{log.name}: exit={code}", flush=True)
    return code, log.read_text(errors="replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--baseline", action="store_true", help="also prove the regression on HEAD's panel")
    parser.add_argument("--metal", action="store_true", help="render locked/completed controls after headless checks")
    options = parser.parse_args()
    output = options.output.resolve()
    project = output / "project"
    if project == ROOT or ROOT.is_relative_to(project):
        raise SystemExit("Refusing to use the source project or its parent as a test copy")
    output.mkdir(parents=True, exist_ok=True)
    marker = project / ".qa09-test-copy"
    if project.exists() and not marker.exists():
        raise SystemExit(f"Refusing to overwrite an unmarked directory: {project}")
    project.mkdir(exist_ok=True)
    marker.write_text("Disposable QA-09 project; source is " + str(ROOT))
    for name in ["addons/godot_level_editor", "content", "tools"]:
        shutil.copytree(ROOT / name, project / name, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns(".godot", "__pycache__", "node_modules"))
    for name in ["project.godot", "icon.svg"]:
        if (ROOT / name).exists(): shutil.copy2(ROOT / name, project / name)
    settings = project / "project.godot"
    text = re.sub(r"(?m)^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n", "", settings.read_text())
    text = text.replace("[application]\n", '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="CodexQA/GodotLevelEditor/sky-QA09"\n', 1)
    settings.write_text(text)
    # Only the private harness redirects the existing test entry. Product suite/plugin.gd is untouched.
    plugin = project / "addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd"
    plugin.write_text(plugin.read_text().replace(
        '"res://tools/sky_editor/editor_test.gd"', '"res://tools/sky_editor/qa_import_test.gd"'))
    panel = project / "addons/godot_level_editor/modules/godot_level_editor_sky/panel.gd"
    fixed = (ROOT / "addons/godot_level_editor/modules/godot_level_editor_sky/panel.gd").read_text()
    results = {}
    if options.baseline:
        panel.write_text(subprocess.check_output(
            ["git", "show", "HEAD:addons/godot_level_editor_sky/panel.gd"], cwd=ROOT, text=True))
        run(options.godot, project, output / "baseline_import.log", ["--headless", "--editor", "--import", "--quit"])
        code, log = run(options.godot, project, output / "baseline.log",
                        ["--headless", "--editor", "--", "--sky-editor-test", "--qa09-baseline"])
        results["baseline_detected"] = code != 0 and "QA09_BASELINE_RESULT" in log and "[FAIL]" in log
    panel.write_text(fixed)
    code, log = run(options.godot, project, output / "import_headless.log", ["--headless", "--editor", "--import", "--quit"])
    results["import"] = code == 0 and "SCRIPT ERROR" not in log
    code, log = run(options.godot, project, output / "qa09_headless.log",
                    ["--headless", "--editor", "--", "--sky-editor-test"])
    results["headless"] = code == 0 and "QA09_IMPORT_RESULT" in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
    code, log = run(options.godot, project, output / "runtime_headless.log",
                    ["--headless", "res://tools/sky_editor/runtime_test.tscn"])
    results["runtime"] = code == 0 and "failures=0" in log and "SCRIPT ERROR" not in log
    if options.metal:
        code, log = run(options.godot, project, output / "qa09_metal.log",
                        ["--editor", "--", "--sky-editor-test", f"--qa09-capture={output}"])
        results["metal"] = code == 0 and "QA09_IMPORT_RESULT" in log and "[FAIL]" not in log and "SCRIPT ERROR" not in log
    (output / "test_results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results), flush=True)
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    def stop_owned_test(signum, _frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, stop_owned_test)
    raise SystemExit(main())
