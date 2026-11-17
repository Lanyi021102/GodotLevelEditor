#!/usr/bin/env python3
"""Simulate replacing only the installed plugin in a prepared QA project."""
import argparse
import json
from pathlib import Path
import shutil
from prepare import hashes, OUTPUT, SOURCE

parser = argparse.ArgumentParser()
parser.add_argument('project', type=Path)
args = parser.parse_args()
project = args.project.resolve()
if not project.name.startswith('branch-mechanism-structure-') or project == SOURCE:
    raise SystemExit('Use only an isolated project created by prepare.py')
kind = 'empty' if '-empty-' in project.name else 'dev'
snapshot = {p: h for p, h in hashes(project / 'content').items() if not p.startswith('qa/')}
(OUTPUT / f'{kind}-update-content-before.json').write_text(json.dumps(snapshot, indent=2))
plugin = project / 'addons/godot_level_editor'
shutil.rmtree(plugin)
shutil.copytree(SOURCE / 'addons/godot_level_editor', plugin)
print(f'Replaced only {plugin}; protected {len(snapshot)} authored content files')
