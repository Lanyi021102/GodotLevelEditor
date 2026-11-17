#!/usr/bin/env python3
"""Capture the released plugin in an isolated project; never edit author maps."""
import argparse
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/release"))
from build import run

parser = argparse.ArgumentParser()
parser.add_argument("--godot", required=True)
parser.add_argument("--archive", type=Path, default=ROOT / "dist/GodotLevelEditor-0.1.0.zip")
parser.add_argument("--output", type=Path, default=ROOT / "exports/promo_2026-11-17")
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="godle-media-") as temporary:
    project = Path(temporary)
    with zipfile.ZipFile(args.archive) as archive:
        archive.extractall(project)
    settings = project / "project.godot"
    settings.write_text('config_version=5\n[application]\nconfig/name="GodotLevelEditor"\n[rendering]\nrenderer/rendering_method="forward_plus"\n')
    shutil.copyfile(Path(__file__).with_name("capture.gd"), project / "release_smoke.gd")
    shutil.copyfile(Path(__file__).with_name("play.gd"), project / "media_play.gd")
    run([args.godot, "--headless", "--path", str(project), "--editor", "--import"], output / "import.log")
    settings.write_text(settings.read_text() + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg")\n')
    run([args.godot, "--path", str(project), "--editor", "--resolution", "1504x960", "--", "--release-smoke", "--media-output=" + str(output)], output / "editor.log", "MEDIA_EDITOR_OK")
    run([args.godot, "--path", str(project), "--script", "res://media_play.gd", "--", "--media-output=" + str(output)], output / "play.log", "MEDIA_PLAY_OK")
archive_path = output / "GodotLevelEditor-promo-images.zip"
with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
    for image in sorted(output.glob("*.png")):
        archive.write(image, image.name)
print("MEDIA_CAPTURE_OK", output)
print("MEDIA_ARCHIVE", archive_path)
