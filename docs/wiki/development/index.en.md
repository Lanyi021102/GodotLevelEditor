# Developer index

Read the root `AGENTS.md`, `README.md` and original [shared toolchain contract](../../tools/BLUEPRINT_TOOLCHAIN.md) before changing interfaces.

## Modules

All code below is relative to `addons/godot_level_editor/`.

| Area | Code | Original interface |
|---|---|---|
| Bootstrap and project initialization | `plugin.gd` | [Suite](../../godot_level_editor_suite/INTERFACES.md) |
| Separate window, tasks and XLSX | `modules/godot_level_editor_suite/` | [Suite](../../godot_level_editor_suite/INTERFACES.md) |
| Wheel, whitebox, element editing and level runtime | `modules/godot_level_editor/` | [Level](../../level_editor/INTERFACES.md) |
| Mechanisms and runtime states | `modules/godot_level_editor_mechanisms/` | [Mechanisms](../../mechanism_editor/INTERFACES.md) |
| NPC models and behavior | `modules/enemy_editor/` | [NPCs](../../enemy_editor/INTERFACES.md) |
| Dialogue and task graphs | `modules/godot_level_editor_narrative/` | [Narrative](../../narrative_editor/INTERFACES.md) |
| Sky and environment | `modules/godot_level_editor_sky/` | [Sky](../../sky_editor/INTERFACES.md) |
| Player/camera/HUD | `scripts/`, `scenes/`, `resources/ui/` | [HUD](../../hud/README.md) |

## Data ownership

Project workbooks live in `content/tables/`, not in the addon. Runtime task graphs remain `.tres`; scene layout remains `.tscn`. The level index exists for stable task binding and follows native scene saves/moves. Display names are not reference keys.

Built-in code/assets and empty templates are the distribution unit. `content/`, developer tools, documents and local caches do not enter the installation ZIP.

## Verification

```sh
Godot --headless --path . --editor --import
python3 tools/release/build.py --version 0.1.0 --godot /path/to/Godot
python3 tools/release/verify.py dist/GodotLevelEditor-0.1.0.zip --godot /path/to/Godot
python3 tools/wiki/wiki.py check
```

Use isolated copies for tests that write scenes or workbooks. Headless checks precede visual checks. Native input/mouse tests and direct API tests are distinct evidence; do not report a direct signal call as a successful mouse drag.

The current [plugin migration record](../../cleanup/plugin_2026-11-17/validation.md) states actual checks, preserved identities and remaining limitations. Older module records retain their dates and do not guarantee that every current combination passes.

Documentation changes belong in both language versions. See [Wiki maintenance](documentation.md), [plugin releases](plugin-release.md) and [Wiki publication](publishing.md).
