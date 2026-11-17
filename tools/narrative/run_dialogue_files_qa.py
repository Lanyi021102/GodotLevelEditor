#!/usr/bin/env python3
"""Exercise dialogue file callbacks in a disposable minimal Godot editor project."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
parser.add_argument('--output', type=Path, required=True, help='Dedicated QA evidence directory')
parser.add_argument('--render', action='store_true', help='Run a native window and capture file-operation states')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
project = Path(tempfile.mkdtemp(prefix='gle-dialogue-files-qa-'))
sources = [
    'addons/godot_level_editor/modules/godot_level_editor_narrative/dialogue_panel.gd',
    'addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd',
    'addons/godot_level_editor/modules/godot_level_editor_suite/runtime/xlsx.gd',
    'addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd',
    'addons/godot_level_editor/modules/godot_level_editor_suite/ui_motion.gd',
    'addons/godot_level_editor/modules/godot_level_editor_suite/identity_colors.gd',
    'addons/godot_level_editor/resources/ui/songti_font.gd',
    'content/tables/dialogues.xlsx',
    'content/resources/narrative/reception.dialogue.tres',
]
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
protected = {p: digest(root / p) for p in sources[-2:]}
for relative in sources:
    target = project / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / relative, target)
    uid = root / (relative + '.uid')
    if uid.exists():
        shutil.copy2(uid, Path(str(target) + '.uid'))
plugin = project / 'addons/qa_dialogue_files'
plugin.mkdir(parents=True)
shutil.copy2(root / 'tools/narrative/dialogue_files_editor_test.gd', plugin / 'plugin.gd')
(plugin / 'plugin.cfg').write_text('[plugin]\nname="Dialogue Files QA"\ndescription="Isolated dialogue file regression"\nauthor="QA"\nversion="1"\nscript="plugin.gd"\n')
(project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="DialogueFilesQA"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/qa_dialogue_files/plugin.cfg")\n')
(output / 'project_path.txt').write_text(str(project) + '\n')
command = [args.godot]
if not args.render:
    command.append('--headless')
command += ['--editor', '--path', str(project)]
if args.render:
    command += ['--', '--qa-capture-dir=' + str(output)]
(output / 'command.txt').write_text(subprocess.list2cmdline(command) + '\n')
log_path = output / ('render.log' if args.render else 'headless.log')
try:
    with log_path.open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=90)
except subprocess.TimeoutExpired:
    print(f'FAIL: test timed out; see {log_path}')
    raise SystemExit(2)
changed = [p for p, original in protected.items() if digest(root / p) != original]
summary = log_path.read_text(errors='replace')
print(summary)
if changed:
    print('FAIL: original source files changed: ' + ', '.join(changed))
    raise SystemExit(2)
print('Original source files unchanged; isolated project: ' + str(project))
if 'DIALOGUE FILE QA:' not in summary or '[FAIL]' in summary or 'SCRIPT ERROR' in summary:
    raise SystemExit(result.returncode or 1)
raise SystemExit(result.returncode)
