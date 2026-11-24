#!/usr/bin/env python3
"""Package the actual addon directory. The content directory is never read."""
from __future__ import annotations
import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import zipfile

SOURCE = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ROOT = "res://addons/godot_level_editor"
USER = "res://content"
BUILTIN_TEMPLATES = {"empty_level.tscn"}


def run(command: list[str], log: Path, marker: str | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 180
        while process.poll() is None:
            content = log.read_text(errors="replace")
            if "SCRIPT ERROR:" in content or re.search(r"^ERROR:", content, re.M) or time.monotonic() > deadline:
                process.terminate()
                break
            time.sleep(0.25)
        try:
            status = process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            status = process.wait()
    content = log.read_text(errors="replace")
    if status or (marker and marker not in content) or "SCRIPT ERROR:" in content or re.search(r"^ERROR:", content, re.M):
        errors = "\n".join(line for line in content.splitlines() if "ERROR" in line or "at:" in line or "RESULT" in line)
        raise RuntimeError(f"Command failed ({status}); see {log}\n{errors[-4500:]}")


def build(version: str, godot: str, output: Path) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    addon = SOURCE / "addons/godot_level_editor"
    files = sorted(path for path in addon.rglob("*") if path.is_file() and path.suffix not in {".import", ".log", ".tmp", ".bak"} and path.name != ".DS_Store" and not any(part in {".godot", "__pycache__"} for part in path.parts))
    manifest = {"version": version, "godot": subprocess.check_output([godot, "--version"], text=True).strip(), "maps_included": False, "source_paths": [], "files": {}}
    archive_path = output / f"GodotLevelEditor-{version}.zip"
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for file in files:
            relative = str(file.relative_to(addon))
            # Personal assets may be present beside the built-in template.
            if relative.startswith("templates/") and relative.removeprefix("templates/") not in BUILTIN_TEMPLATES:
                continue
            if any(not part.isascii() for part in Path(relative).parts[:-1]):
                raise RuntimeError("Plugin directories must use English names: " + relative)
            if relative == "manifest.json": continue
            data = file.read_bytes()
            if relative == "plugin.cfg": data = re.sub(rb'version="[^\"]+"', ('version="' + version + '"').encode(), data)
            archive.writestr("addons/godot_level_editor/" + relative, data)
            manifest["source_paths"].append(str(file.relative_to(SOURCE)))
            manifest["files"][relative] = hashlib.sha256(data).hexdigest()
        archive.writestr("addons/godot_level_editor/manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    archive_path.with_suffix(".zip.sha256").write_text(digest + "  " + archive_path.name + "\n")
    print(f"Built {archive_path} ({archive_path.stat().st_size / 1024 / 1024:.1f} MiB)", flush=True)
    return archive_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    config = configparser.ConfigParser()
    config.read(SOURCE / "addons/godot_level_editor/plugin.cfg")
    parser.add_argument("--version", default=config["plugin"]["version"].strip('"'))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--output", type=Path, default=SOURCE / "dist")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", args.version): parser.error("Version must be X.Y.Z or X.Y.Z-prerelease")
    build(args.version, args.godot, args.output.resolve())
