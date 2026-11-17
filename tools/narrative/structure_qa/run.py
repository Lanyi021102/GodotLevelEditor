#!/usr/bin/env python3
"""Run the authoring/F6 scenario in an already prepared isolated QA project."""
import argparse
import re
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--migrated", action="store_true")
    args = parser.parse_args()
    if "GLEStructureNarrative" not in (args.project / "project.godot").read_text():
        parser.error("dedicated GLEStructureNarrative project/user directory required")
    # Godot's Run Instances dialog caches these settings during editor startup.
    # Set them in the isolated host before launch, not just before F6.
    settings = args.project / "project.godot"
    text = re.sub(r'^run/main_run_args=.*\n', '', settings.read_text(), flags=re.M)
    run_args = "--ignore-error-breaks" if args.visual else "--headless --ignore-error-breaks"
    if "[editor]\n" in text:
        text = text.replace("[editor]\n", f'[editor]\nrun/main_run_args="{run_args}"\n', 1)
    else:
        text += f'\n[editor]\nrun/main_run_args="{run_args}"\n'
    settings.write_text(text)
    command = ["/Applications/Godot.app/Contents/MacOS/Godot"]
    if not args.visual:
        command += ["--headless"]
    flag = "--narrative-migrated-qa" if args.migrated else "--godot-level-editor-narrative-smoke" if args.smoke else "--narrative-structure-qa"
    command += ["--path", str(args.project), "--editor", "res://qa_boot.tscn", "--", flag]
    args.log.parent.mkdir(parents=True, exist_ok=True)
    playing_flag = args.project / "qa_playing.flag"
    playing_flag.unlink(missing_ok=True)
    with args.log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 125
        try:
            while process.poll() is None and time.monotonic() < deadline:
                if args.visual and sys.platform == "darwin":
                    target_pid = process.pid
                    if playing_flag.exists():
                        target_pid = None
                        for line in subprocess.check_output(["ps", "-axo", "pid=,command="], text=True).splitlines():
                            parts = line.strip().split(None, 1)
                            if len(parts) == 2 and parts[1].startswith("/Applications/Godot.app/Contents/MacOS/Godot ") and f"--editor-pid {process.pid}" in parts[1]:
                                target_pid = int(parts[0]); break
                    if target_pid is None:
                        time.sleep(0.15)
                        continue
                    script = f'''tell application "System Events"
if exists (application process "loginwindow") then
if frontmost of application process "loginwindow" then return "LOCKED"
end if
if exists (first application process whose unix id is {target_pid}) then
set targetProcess to first application process whose unix id is {target_pid}
if not frontmost of targetProcess then set frontmost of targetProcess to true
end if
end tell'''
                    focus = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=3)
                    if focus.stdout.strip() == "LOCKED":
                        output.write("\nNARRATIVE_STRUCTURE_BLOCKED: desktop locked\n")
                        output.flush()
                        return 2
                time.sleep(0.15)
            if process.poll() is None:
                return 2
            log = args.log.read_text()
            return 0 if process.returncode == 0 and "NARRATIVE_STRUCTURE:" in log and "0 failures" in log and "SCRIPT ERROR" not in log else 1
        finally:
            playing_flag.unlink(missing_ok=True)
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
