# Install and update

Use **Godot 4.7.1 Standard**. Plugin users do not need Python or Microsoft Excel.

1. Download `GodotLevelEditor-<version>.zip` from [Releases](https://github.com/Lanyi021102/GodotLevelEditor/releases/latest). The automatically generated **Source code** downloads are development snapshots, not the installation package.
2. Copy `addons/godot_level_editor/` from the ZIP into your Godot project.
3. Wait for asset import. In **Project → Project Settings → Plugins**, enable **GodotLevelEditor**. Its internal modules start automatically.
4. In an empty project, press **F5** or Play to control the included character. To make another map, follow the [quick start](getting-started.md).

The package includes five independent mechanisms, 13 NPC examples, models, animations, the player, third-person camera, HUD, lighting and sky presets. Author maps and personal task/dialogue data are excluded.

## Where files belong

| Content | Default location |
|---|---|
| Addon code and built-in resources | `addons/godot_level_editor/` |
| Empty level template | `addons/godot_level_editor/templates/empty_level.tscn` |
| Your maps | `content/scenes/levels/`, or another project folder outside the addon |
| Your mechanism/NPC scenes | `content/scenes/mechanisms/`, `content/scenes/npcs/` |
| Your NPC definitions | `content/resources/enemies/` |
| Your task graphs | `content/resources/task_graphs/` |
| Project Excel workbooks | `content/tables/` |
| Custom sky presets and HDRI | `content/resources/sky_presets/custom/`, `content/assets/sky_hdri/` |

Excel data belongs to each project. The addon contains empty workbook templates and creates only missing project workbooks. It does not overwrite existing workbooks during activation or updates.

If no main scene is configured, first activation generates a blank project start scene and sets it as the main scene. An existing main scene, input actions and rendering settings are preserved. Missing default input actions and the GLE-prefixed runtime services are added.

## Update or disable

Close Godot and replace only `addons/godot_level_editor/`. Keep `content/`. Save modified built-in assets as your own copies outside the addon before updating.

Disabling the main plugin stops its editor modules while retaining your workbooks, maps, input bindings and runtime services. Before physically removing the addon, migrate or remove scenes that depend on its scripts/models, then remove the `GLELightZones`, `GLENoiseBus` and `GLESaveSystem` Autoload entries.

Compatibility is recorded in the release's `manifest.json` and validation record. Original code uses MIT; third-party models and animations retain their own licenses.
