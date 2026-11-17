#!/usr/bin/env python3
"""Prepare isolated development and plugin-only projects; never run original Godot."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

SOURCE = Path(__file__).resolve().parents[3]
OUTPUT = SOURCE / '.validation/structure-qa-2026-11-17/mechanism'

def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file() and '.godot' not in p.parts}

def prepare(kind):
    project = Path(tempfile.mkdtemp(prefix=f'branch-mechanism-structure-{kind}-'))
    shutil.copytree(SOURCE / 'addons/godot_level_editor', project / 'addons/godot_level_editor')
    if kind == 'dev':
        shutil.copytree(SOURCE / 'tools', project / 'tools', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copytree(SOURCE / 'content', project / 'content')
        shutil.copy2(SOURCE / 'project.godot', project / 'project.godot')
        shutil.copy2(SOURCE / 'icon.svg', project / 'icon.svg')
        config = (project / 'project.godot').read_text().replace('config/name="GodotLevelEditor"', f'config/name="MechanismStructureQA-{project.name}"')
    else:
        shutil.copytree(SOURCE / 'tools/mechanisms', project / 'tools/mechanisms')
        config = f'config_version=5\n[application]\nconfig/name="MechanismStructureQA-{project.name}"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg")\n'
    harness = project / 'addons/mechanism_structure_qa'
    harness.mkdir()
    (harness / 'plugin.cfg').write_text('[plugin]\nname="Mechanism Structure QA"\ndescription="Isolated validation only"\nauthor="QA"\nversion="1"\nscript="probe.gd"\n')
    (harness / 'probe.gd').write_text('@tool\nextends EditorPlugin\nfunc _enter_tree() -> void:\n\t_run.call_deferred()\nfunc _run() -> void:\n\tvar test: RefCounted = load("res://tools/mechanisms/structure_qa/editor.gd").new()\n\tawait test.run(self)\n')
    config = config.replace('enabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg")', 'enabled=PackedStringArray("res://addons/godot_level_editor/plugin.cfg", "res://addons/mechanism_structure_qa/plugin.cfg")')
    (project / 'project.godot').write_text(config)
    (project / 'plugin-before.json').write_text(json.dumps(hashes(project / 'addons/godot_level_editor'), indent=2))
    return str(project)

if __name__ == '__main__':
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, directory in [('original-content-before.json', SOURCE / 'content'), ('original-builtins-before.json', SOURCE / 'addons/godot_level_editor/scenes/mechanisms')]:
        if not (OUTPUT / name).exists():
            (OUTPUT / name).write_text(json.dumps(hashes(directory), indent=2))
    if (OUTPUT / 'projects.json').exists():
        history = json.loads((OUTPUT / 'project-history.json').read_text()) if (OUTPUT / 'project-history.json').exists() else []
        history.append(json.loads((OUTPUT / 'projects.json').read_text()))
        (OUTPUT / 'project-history.json').write_text(json.dumps(history, indent=2))
    projects = {kind: prepare(kind) for kind in ['dev', 'empty']}
    (OUTPUT / 'projects.json').write_text(json.dumps(projects, indent=2))
    print(json.dumps(projects, indent=2))
