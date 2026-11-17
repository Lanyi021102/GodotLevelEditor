#!/usr/bin/env python3
"""Install the built ZIP into an empty project; verify initial use and update."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import zipfile
from build import HERE, ROOT, USER, run


def verify(archive_path: Path, godot: str, output: Path, visual: bool = False) -> None:
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        if any(not name.startswith("addons/godot_level_editor/") or ".." in Path(name).parts for name in names):
            raise RuntimeError("ZIP contains files outside its addon directory")
        if any(any(not part.isascii() for part in Path(name).parts[:-1]) for name in names):
            raise RuntimeError("ZIP contains a non-English directory name")
        manifest = json.loads(archive.read("addons/godot_level_editor/manifest.json"))
        for name, digest in manifest["files"].items():
            if hashlib.sha256(archive.read("addons/godot_level_editor/" + name)).hexdigest() != digest:
                raise RuntimeError("Manifest mismatch: " + name)
        forbidden = ("scenes/levels/", "resources/levels/", "resources/level_previews/", "resources/task_graphs/", "resources/level_editor/", "tools/", "docs/", "scripts/levels/")
        for source in manifest["source_paths"]:
            name = source.removeprefix("addons/godot_level_editor/")
            if name.startswith(forbidden): raise RuntimeError("Map/private development content: " + name)
            if name.startswith("scenes/level_editor/rooms/") and name != "scenes/level_editor/rooms/trigger_room.tscn": raise RuntimeError("Complete room in package: " + name)
        with tempfile.TemporaryDirectory(prefix="godle-install-") as temporary:
            project = Path(temporary)
            archive.extractall(project)
            (project / "project.godot").write_text('''config_version=5
[application]
config/name="Plugin Installation Check"
run/main_scene="res://host.tscn"
[autoload]
NoiseBus="*res://host.gd"
[editor_plugins]
enabled=PackedStringArray()
[input]
move_forward={"deadzone": 0.2, "events": [Object(InputEventKey,"physical_keycode":4194320)]}
[rendering]
renderer/rendering_method="gl_compatibility"
''')
            (project / "host.gd").write_text("extends Node\n")
            (project / "host.tscn").write_text('[gd_scene format=3]\n[node name="Host" type="Node"]\n')
            shutil.copyfile(HERE / "release_smoke.gd", project / "release_smoke.gd")
            shutil.copyfile(HERE / "play_smoke.gd", project / "play_smoke.gd")
            run([godot, "--headless", "--path", str(project), "--editor", "--import"], output / "install-import.log")
            settings = project / "project.godot"
            settings.write_text(settings.read_text().replace('enabled=PackedStringArray()', 'enabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg")'))
            run([godot, "--headless", "--path", str(project), "--editor", "--", "--release-smoke"], output / "install-editor.log", "RELEASE_SMOKE_RESULT")
            run([godot, "--headless", "--path", str(project), "--script", "res://play_smoke.gd"], output / "play.log", "RELEASE_PLAY_OK")
            content = project / "content"
            before = {str(path.relative_to(content)): hashlib.sha256(path.read_bytes()).hexdigest() for path in content.rglob("*") if path.is_file()}
            # Upgrade replaces only the addon, exactly as documented.
            shutil.rmtree(project / "addons/godot_level_editor")
            archive.extractall(project)
            run([godot, "--headless", "--path", str(project), "--editor", "--import"], output / "update-import.log")
            run([godot, "--headless", "--path", str(project), "--editor", "--", "--release-smoke", "--release-reopen"], output / "update-editor.log", "RELEASE_SMOKE_RESULT")
            for name, digest in before.items():
                if hashlib.sha256((content / name).read_bytes()).hexdigest() != digest:
                    raise RuntimeError("Update overwrote user content: " + name)
            if visual:
                run([godot, "--path", str(project), "--editor", "--rendering-method", "forward_plus", "--", "--release-smoke", "--release-reopen", "--release-visual"], output / "visual.log", "RELEASE_SMOKE_RESULT")
                for name in ("release-editor.png", "release-npcs.png"):
                    shutil.copyfile(project / name, output / name)
            (output / "summary.json").write_text(json.dumps({"archive": archive_path.name, "manifest_files": len(manifest["files"]), "user_files_preserved": len(before), "initial_install": "passed", "update": "passed"}, indent=2) + "\n")
        # A truly empty host should be usable by pressing the normal F5 button.
        with tempfile.TemporaryDirectory(prefix="godle-default-") as temporary:
            project = Path(temporary)
            archive.extractall(project)
            settings = project / "project.godot"
            settings.write_text('config_version=5\n[application]\nconfig/name="Default Play Check"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
            run([godot, "--headless", "--path", str(project), "--editor", "--import"], output / "default-import.log")
            settings.write_text(settings.read_text() + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg")\n')
            run([godot, "--headless", "--path", str(project), "--editor", "--quit-after", "120"], output / "default-setup.log", "RELEASE_DEFAULT_READY")
            run([godot, "--headless", "--path", str(project), "--quit-after", "120"], output / "default-f5.log")
            shutil.copyfile(HERE / "play_smoke.gd", project / "play_smoke.gd")
            run([godot, "--headless", "--path", str(project), "--script", "res://play_smoke.gd", "--", "--release-default"], output / "default-player.log", "RELEASE_PLAY_OK")
            if visual:
                run([godot, "--path", str(project), "--rendering-method", "forward_plus", "--script", "res://play_smoke.gd", "--", "--release-default", "--release-capture"], output / "default-visual.log", "RELEASE_PLAY_OK")
                shutil.copyfile(project / "default-play.png", output / "default-play.png")
        summary = json.loads((output / "summary.json").read_text())
        summary["default_f5_and_controllable_player"] = "passed"
        summary["visual"] = "passed" if visual else "not run"
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("RELEASE_VERIFY_OK", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, default=HERE.parents[1] / "dist/verification")
    parser.add_argument("--visual", action="store_true")
    arguments = parser.parse_args()
    verify(arguments.archive.resolve(), arguments.godot, arguments.output.resolve(), arguments.visual)
