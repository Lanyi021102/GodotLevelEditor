#!/usr/bin/env python3
"""Run dialogue-mode integration tests in a separate project and user-data scope."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--render', action='store_true')
parser.add_argument('--project', type=Path, help='Reuse a previously created isolated snapshot')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
project = args.project or Path(tempfile.mkdtemp(prefix='gle-dialogue-modes-'))
if args.project is None:
    for name in ['addons', 'addons/godot_level_editor/scripts', 'content/scenes', 'content/resources', 'addons/godot_level_editor/assets', 'tools', 'content/tables']:
        shutil.copytree(root / name, project / name, ignore=shutil.ignore_patterns('__pycache__', '*.log'))
    shutil.copy2(root / 'icon.svg', project / 'icon.svg')
    settings = (root / 'project.godot').read_text()
    settings = re.sub(r'config/name="[^"]*"', 'config/name="GodotDialogueModesQA"', settings, count=1)
    settings = re.sub(r'enabled=PackedStringArray\([^\n]*\)', 'enabled=PackedStringArray()', settings, count=1)
    (project / 'project.godot').write_text(settings)
    with (output / 'import.log').open('w') as log:
        imported = subprocess.run([args.godot, '--headless', '--editor', '--path', str(project), '--quit'], stdout=log, stderr=subprocess.STDOUT, timeout=180)
    if imported.returncode:
        raise SystemExit(imported.returncode)
elif project.resolve() == root:
    raise SystemExit('Refusing to run these tests in the original project.')
(output / 'project_path.txt').write_text(str(project) + '\n')
command = [args.godot] + ([] if args.render else ['--headless']) + ['--path', str(project), 'res://tools/narrative/test_dialogue_modes.tscn']
if args.render: command += ['--', '--capture-dir=' + str(output)]
(output / 'command.txt').write_text(subprocess.list2cmdline(command) + '\n')
path = output / ('render.log' if args.render else 'runtime.log')
with path.open('w') as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=90)
text = path.read_text(errors='replace'); print(text)
if 'DIALOGUE MODES:' not in text or '[FAIL]' in text or 'SCRIPT ERROR' in text:
    raise SystemExit(result.returncode or 1)
raise SystemExit(result.returncode)
