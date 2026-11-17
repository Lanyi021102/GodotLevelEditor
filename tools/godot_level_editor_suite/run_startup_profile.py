#!/usr/bin/env python3
"""Profile startup in a disposable copy, without instrumenting project sources."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def wrap(path, name, declaration=None, arguments="", result=None):
    source = path.read_text()
    match = re.search(r"^(static )?func " + re.escape(name) + r"\([^\n]*", source, re.M)
    if match is None:
        return
    signature = declaration or match.group()
    original = "_startup_original_" + path.parent.name + "_" + path.stem + "_" + name.lstrip("_")
    source = source[:match.start()] + match.group().replace("func " + name + "(", "func " + original + "(", 1) + source[match.end():]
    label = path.name + ":" + name
    call = original + "(" + arguments + ")"
    body = "\n" + signature + "\n\tvar startup_tick := Time.get_ticks_usec()\n"
    body += ("\tvar startup_value: " + result + " = " if result else "\t") + call + "\n"
    body += '\tprint("STARTUP_SCOPE ", JSON.stringify({"scope": "' + str(path.parent.name) + "/" + label + '", "ms": (Time.get_ticks_usec() - startup_tick) / 1000.0, "at_ms": Time.get_ticks_msec()}))\n'
    if result:
        body += "\treturn startup_value\n"
    if name == "_build_workspace":
        body += '\tif _built and not has_meta("startup_profile_finished"):\n\t\tset_meta("startup_profile_finished", true)\n\t\t_startup_profile_finish.call_deferred()\n'
    path.write_text(source + body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--open-workspace", action="store_true")
    args = parser.parse_args()
    output = Path(args.output).resolve()
    project = output / "project"
    if project.exists():
        raise SystemExit("Choose a fresh output directory: " + str(project))
    project.mkdir(parents=True)
    for name in ["addons", "addons/godot_level_editor/assets", "content/resources", "content/scenes", "addons/godot_level_editor/scripts", "tools", "content/tables", ".godot"]:
        if (ROOT / name).exists():
            shutil.copytree(ROOT / name, project / name)
    for name in ["project.godot", "icon.svg", "icon.svg.import"]:
        shutil.copy2(ROOT / name, project / name)
    (project / "docs").mkdir()
    (project / "docs/.gdignore").touch()
    for folder in ["enemy_editor", "godot_level_editor_mechanisms", "godot_level_editor", "godot_level_editor_narrative", "godot_level_editor_suite"]:
        wrap(project / "addons/godot_level_editor/modules" / folder / "plugin.gd", "_enter_tree")
    for relative in ["enemy_editor/editor_panel.gd", "enemy_editor/appearance_panel.gd", "godot_level_editor/graph_panel.gd", "godot_level_editor_mechanisms/editor_panel.gd", "godot_level_editor_narrative/dialogue_panel.gd", "godot_level_editor_narrative/task_panel.gd", "godot_level_editor_suite/level_warehouse.gd", "godot_level_editor_suite/asset_workspace.gd", "godot_level_editor_suite/event_panel.gd", "godot_level_editor_sky/panel.gd"]:
        wrap(project / "addons/godot_level_editor/modules" / relative, "_ready")
    for relative, name in [("godot_level_editor_suite/plugin.gd", "_build_workspace"), ("godot_level_editor_suite/asset_workspace.gd", "reload_catalog"), ("godot_level_editor_suite/level_warehouse.gd", "reload_catalog"), ("godot_level_editor_sky/panel.gd", "_update_references"), ("godot_level_editor_sky/panel.gd", "reload_library")]:
        wrap(project / "addons/godot_level_editor/modules" / relative, name)
    wrap(project / "addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd", "theme", result="Theme")
    wrap(project / "addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd", "workspace", arguments="root")
    wrap(project / "addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd", "_adopt", arguments="control, name_text, target")
    suite_source = (project / "addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd").read_text()
    wrap(project / "addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd", "_asset_workspace", arguments="title, module, host" if "host: Control = null" in suite_source else "title, module")
    wrap(project / "addons/godot_level_editor/resources/ui/songti_font.gd", "_source", arguments="weight", result="Dictionary")
    plugin = project / "addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd"
    # Schedule from plugin registration so the normal lazy startup is measured
    # even when no independent window is requested.
    source = plugin.read_text().replace('print("STARTUP_SCOPE ", JSON.stringify({"scope": "godot_level_editor_suite/plugin.gd:_enter_tree"', '_startup_profile_finish.call_deferred()\n\tprint("STARTUP_SCOPE ", JSON.stringify({"scope": "godot_level_editor_suite/plugin.gd:_enter_tree"')
    source = source.replace('\t\t_startup_profile_finish.call_deferred()', '\t\tpass')
    plugin.write_text(source + '''
func _startup_profile_finish() -> void:
	for i in 10: await get_tree().process_frame
	print("STARTUP_READY ", JSON.stringify({"at_ms": Time.get_ticks_msec(), "content/resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}))
''' + ('''	var startup_open := Time.get_ticks_usec()
	show_window()
	print("STARTUP_OPEN ", JSON.stringify({"ms": (Time.get_ticks_usec() - startup_open) / 1000.0}))
	for startup_title in ["关卡", "机关", "敌人", "任务图", "台本", "天空"]:
		var startup_visit := Time.get_ticks_usec()
		open_tab(startup_title)
		print("STARTUP_VISIT ", JSON.stringify({"page": startup_title, "ms": (Time.get_ticks_usec() - startup_visit) / 1000.0}))
		for i in 3: await get_tree().process_frame
''' if args.open_workspace else '') + '''
	get_tree().quit()
''')
    records = []
    for run in range(args.runs):
        start = time.monotonic()
        command = [args.godot] + ([] if args.render else ["--headless"]) + ["--editor", "--path", str(project)]
        lines, events, scopes = [], {}, []
        # The engine's own --quit-after provides a fallback if profiling fails.
        command += ["--quit-after", "180"]
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
            for raw in process.stdout:
                elapsed = (time.monotonic() - start) * 1000
                lines.append(f"{elapsed:10.3f} {raw}")
                if "正在初始化插件" in raw: events["plugins_begin_ms"] = elapsed
                if "正在启动文件扫描" in raw: events["plugins_end_ms"] = elapsed
                if raw.startswith("STARTUP_SCOPE "): scopes.append(json.loads(raw.removeprefix("STARTUP_SCOPE ")))
                if raw.startswith("STARTUP_READY "): events["ready_ms"] = elapsed
                if raw.startswith("STARTUP_OPEN "): events["workspace_open"] = json.loads(raw.removeprefix("STARTUP_OPEN "))
                if raw.startswith("STARTUP_VISIT "): events.setdefault("page_visits", []).append(json.loads(raw.removeprefix("STARTUP_VISIT ")))
            code = process.wait(timeout=180)
        record = {"run": run + 1, "exit_code": code, "wall_ms": (time.monotonic() - start) * 1000, "events": events, "scopes": scopes}
        records.append(record)
        (output / f"run_{run + 1}.log").write_text("".join(lines))
        print(json.dumps({key: value for key, value in record.items() if key != "scopes"}), flush=True)
        if code or "ready_ms" not in events or any("SCRIPT ERROR:" in line for line in lines):
            (output / "measurements.json").write_text(json.dumps(records, indent=2))
            return 1
    (output / "measurements.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
