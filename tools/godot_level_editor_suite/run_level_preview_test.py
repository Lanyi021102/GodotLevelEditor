#!/usr/bin/env python3
"""Verify level editor workflows in a disposable project with a private cache."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--test', choices=['preview', 'delete', 'placement', 'drag'], default='preview')
    parser.add_argument('--project', type=Path, help='Reuse an already imported disposable copy')
    parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
    args = parser.parse_args()
    test_script = ('tools/level_editor/test_quick_add.gd' if args.test == 'placement' else
                   'tools/godot_level_editor_suite/native_drag_test.gd' if args.test == 'drag' else
                   'tools/godot_level_editor_suite/level_' + args.test + '_test.gd')
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    protected = list((root / 'content/tables').glob('*.xlsx')) + list((root / 'content/scenes/levels').glob('*.tscn'))
    before = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    project = args.project.resolve() if args.project else Path(tempfile.mkdtemp(prefix='godot-preview-qa-')) / 'project'
    if args.project and (project == root or not project.parent.name.startswith('godot-preview-qa-')):
        raise RuntimeError('Reuse is limited to this runner\'s disposable projects')
    if not args.project:
        project.mkdir()
        for name in ['addons', 'addons/godot_level_editor/assets', 'content/resources', 'content/scenes', 'addons/godot_level_editor/scripts', 'tools', 'content/tables']:
            shutil.copytree(root / name, project / name, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        for name in ['project.godot', 'icon.svg']:
            shutil.copy2(root / name, project / name)
        config = project / 'project.godot'
        config.write_text(config.read_text().replace('config/name="GodotLevelEditor"', 'config/name="QA-Preview-' + project.parent.name + '"'))
    else:
        shutil.rmtree(project / '.godot/editor', ignore_errors=True)
        (project / 'content/scenes/levels/900002_preview_new.tscn').unlink(missing_ok=True)
        for name in ['level_preview.gd', 'plugin.gd', 'level_card.gd', 'level_warehouse.gd']:
            shutil.copy2(root / 'addons/godot_level_editor/modules/godot_level_editor_suite' / name, project / 'addons/godot_level_editor/modules/godot_level_editor_suite' / name)
        shutil.copytree(root / 'addons/godot_level_editor/modules/godot_level_editor', project / 'addons/godot_level_editor/modules/godot_level_editor', dirs_exist_ok=True)
        for retired in ['palette_item.gd', 'palette_item.gd.uid']:
            (project / 'addons/godot_level_editor/modules/godot_level_editor' / retired).unlink(missing_ok=True)
        for relative in [test_script, 'tools/level_editor/editor_smoke.gd', 'tools/level_editor/test_qa_identity_delete.gd']:
            shutil.copy2(root / relative, project / relative)
    # Test hook lives only in the disposable copy, never in the user's plugin.
    plugin = project / 'addons/godot_level_editor/modules/godot_level_editor_suite/plugin.gd'
    source = plugin.read_text()
    target = 'await load("res://tools/godot_level_editor_suite/capture_level_previews.gd").run(self)'
    if source.count(target) != 1:
        raise RuntimeError('capture test hook changed')
    receiver = 'self.modules.level' if args.test == 'placement' else 'self'
    constructor = '' if args.test == 'drag' else '.new()'
    plugin.write_text(source.replace(target, 'await load("res://' + test_script + '")' + constructor + '.run(' + receiver + ')'))
    manifest = {'project': str(project), 'source': str(root), 'test': args.test, 'renderer': 'Metal' if args.render else 'headless'}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    with (output / 'import.log').open('w') as log:
        result = subprocess.run([args.godot, '--headless', '--editor', '--path', str(project), '--quit'], stdout=log, stderr=subprocess.STDOUT, timeout=120)
    if result.returncode or 'SCRIPT ERROR:' in (output / 'import.log').read_text():
        print('Import failed:', output / 'import.log'); return 2
    command = [args.godot] + ([] if args.render else ['--headless']) + ['--editor', '--path', str(project), '--', '--capture-level-previews', '--qa-output=' + str(output)]
    if args.test == 'placement' and args.render:
        command.append('--qa-native-capture=' + str(output / 'native_editor.png'))
    with (output / 'checks.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=100)
    after = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    check_log = (output / 'checks.log').read_text()
    marker = 'QUICK ADD:' if args.test == 'placement' else 'WAREHOUSE NATIVE DROP:' if args.test == 'drag' else 'LEVEL ' + args.test.upper() + ' TEST:'
    manifest.update(exit_code=result.returncode, source_unchanged=before == after, script_errors='SCRIPT ERROR:' in check_log, test_finished=marker in check_log)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    # Keep new UID files generated by the isolated import alongside their sources.
    for relative in ['addons/godot_level_editor/modules/godot_level_editor_suite/level_preview.gd.uid', test_script + '.uid']:
        if (project / relative).exists() and not (root / relative).exists():
            shutil.copy2(project / relative, root / relative)
    print(json.dumps(manifest, indent=2))
    return result.returncode or (3 if not manifest['source_unchanged'] else 4 if manifest['script_errors'] else 5 if not manifest['test_finished'] else 0)


if __name__ == '__main__':
    raise SystemExit(main())
