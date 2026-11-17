#!/usr/bin/env python3
"""Verify secondary navigation without opening or editing the author's project."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULE = Path('addons/godot_level_editor/modules/godot_level_editor_suite')

def content_hashes():
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (ROOT / 'content').rglob('*') if p.is_file()}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--project', type=Path)
    parser.add_argument('--browser', action='store_true')
    parser.add_argument('--consumer', action='store_true')
    parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
    args = parser.parse_args()
    test = Path('tools/godot_level_editor_suite/level_browser_test.gd' if args.browser else 'tools/godot_level_editor_suite/level_navigation_test.gd')
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    before = content_hashes()
    project = args.project.resolve() if args.project else Path(tempfile.mkdtemp(prefix='godot-navigation-qa-')) / 'project'
    if args.project:
        if not project.parent.name.startswith('godot-navigation-qa-') or project == ROOT:
            raise RuntimeError('Only reuse a disposable navigation test project')
        shutil.rmtree(project / '.godot/editor', ignore_errors=True)
        shutil.copytree(ROOT / 'addons', project / 'addons', dirs_exist_ok=True)
        shutil.copy2(ROOT / test, project / test)
    else:
        project.mkdir()
        for name in (['addons', 'tools'] if args.consumer else ['addons', 'content', 'tools']):
            shutil.copytree(ROOT / name, project / name, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        if args.consumer:
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="GodotLevelEditor"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        else:
            for name in ['project.godot', 'icon.svg']: shutil.copy2(ROOT / name, project / name)
        config = project / 'project.godot'
        config.write_text(config.read_text().replace('config/name="GodotLevelEditor"', 'config/name="QA-Navigation-' + project.parent.name + '"'))
    plugin = project / MODULE / 'plugin.gd'
    original = 'await load("res://tools/godot_level_editor_suite/startup_test.gd").new().run(self)'
    source = plugin.read_text()
    if source.count(original) != 1: raise RuntimeError('Isolated startup test hook changed')
    plugin.write_text(source.replace(original, 'await load("res://' + str(test) + '").new().run(self)'))
    manifest = {'project': str(project), 'render': args.render, 'browser': args.browser, 'consumer': args.consumer}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    with (output / 'import.log').open('w') as log:
        imported = subprocess.run([args.godot, '--headless', '--editor', '--path', str(project), '--quit'], stdout=log, stderr=subprocess.STDOUT, timeout=120)
    if imported.returncode or 'SCRIPT ERROR:' in (output / 'import.log').read_text(): return 2
    with (output / 'parse.log').open('w') as log:
        parsed = subprocess.run([args.godot, '--headless', '--path', str(project), '--check-only', '--script', 'res://' + str(test)], stdout=log, stderr=subprocess.STDOUT, timeout=30)
    if parsed.returncode or 'SCRIPT ERROR:' in (output / 'parse.log').read_text(): return 2
    command = [args.godot] + ([] if args.render else ['--headless']) + ['--editor', '--path', str(project), '--', '--startup-lazy-test', '--qa-output=' + str(output)]
    with (output / 'checks.log').open('w') as log:
        tested = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    log = (output / 'checks.log').read_text()
    manifest.update(exit_code=tested.returncode, source_content_unchanged=before == content_hashes(), script_errors='SCRIPT ERROR:' in log, finished=('LEVEL BROWSER TEST:' if args.browser else 'LEVEL NAVIGATION TEST:') in log)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    uid = test.with_suffix('.gd.uid')
    if (project / uid).exists() and not (ROOT / uid).exists(): shutil.copy2(project / uid, ROOT / uid)
    browser_uid = MODULE / 'level_browser.gd.uid'
    if (project / browser_uid).exists() and not (ROOT / browser_uid).exists(): shutil.copy2(project / browser_uid, ROOT / browser_uid)
    print(json.dumps(manifest, indent=2))
    return tested.returncode or (3 if not manifest['source_content_unchanged'] else 4 if manifest['script_errors'] or not manifest['finished'] else 0)

if __name__ == '__main__':
    raise SystemExit(main())
