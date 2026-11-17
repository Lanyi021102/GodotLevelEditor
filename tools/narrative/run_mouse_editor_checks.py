#!/usr/bin/env python3
"""Run native-window input checks in an isolated project copy on macOS."""
import argparse
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--npc", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("this launcher manages macOS foreground focus")
    command = ["/Applications/Godot.app/Contents/MacOS/Godot", "--path", str(args.project.resolve()), "--editor", "--", "--godot-level-editor-suite-test", "--task-switch", "--live-wire"]
    if args.npc:
        command.append("--npc-wire")
    args.log.parent.mkdir(parents=True, exist_ok=True)
    with args.log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        # Activating a scene or inspecting a bound component can focus the native
        # editor. Keep this test process active while its own Window.grab_focus()
        # selects the tool window. Never address the user's other Godot processes.
        script = f'''tell application "System Events"
if exists (application process "loginwindow") then
    if frontmost of application process "loginwindow" then return "LOCKED"
end if
if exists (first application process whose unix id is {process.pid}) then
    set targetProcess to first application process whose unix id is {process.pid}
    if not frontmost of targetProcess then set frontmost of targetProcess to true
end if
end tell'''
        deadline = time.monotonic() + 85
        try:
            while process.poll() is None and time.monotonic() < deadline:
                focus = subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True, text=True, timeout=3)
                if focus.stdout.strip() == "LOCKED":
                    output.write("\nMOUSE CHECK BLOCKED: desktop is locked\n")
                    output.flush()
                    process.terminate()
                    process.wait(timeout=5)
                    return 2
                time.sleep(0.12)
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
                return 2
            return process.returncode
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
