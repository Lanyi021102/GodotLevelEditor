# FAQ

## The editor entry is missing {#editor-entry}

Use Godot 4.7.1, wait for import, then enable the main GodotLevelEditor plugin. The top entry or Project → Tools opens its separate window. Internal modules start automatically. Do not install a second copy into the source development project.

<span id="navigation-performance"></span>

## Startup or first page access takes time {#plugin-startup}

Viewport tools register on startup, while separate-window pages initialize on first use. Model libraries and a page's first visit may take longer than later visits. Reopening an already initialized page should reuse it. If import fails, read the actual output rather than using an old screenshot as evidence of success.

## Scaling looks wrong {#display-scaling}

Try Workspace's automatic scale or a manual 100%–300% value. Preferences are local to the current project. A newly loaded script/theme may require saving work and reopening Godot.

## Where are my maps?

Open `.tscn` files from native FileSystem, normally under `content/scenes/levels/`. The old custom map-card catalog has been removed. New maps can inherit the addon's empty template and be saved outside the addon.

## Play does not control the character

In a project without a main scene, activation creates a start scene for F5. An existing main scene is preserved. For a newly authored plugin level, save and use F6. Click the game viewport after switching back from the editor; Esc intentionally releases control. Keep the spawn above solid geometry.

<span id="task-level"></span>

## A task does not start or advance

Check that the event was accepted/started, the task is the event's current task, and the current level matches its level ID. Persistent level logic can run before task acceptance; task-owned objects cannot. Save the map before binding a new task, and inspect validation errors for missing NPC/Room/mechanism references.

<span id="task-owner"></span>
<span id="missing-npc"></span>

## Task objects are invisible

Check their owning task and level. Inactive, completed and failed task objects are disabled by design. A Room becoming active because the player entered it is a separate state from the task becoming active.

## A request succeeded but the door is still moving

Accepted means motion was started. Wait for `open` or actual action completion when later logic needs a fully opened door. Reversing motion can cancel the previous action.

## HDRI import is blocked or fails {#hdri-import}

Check that the image is readable and the project destination can be written. During import, changing the target preset, saving/copying/restoring or binding is temporarily blocked. Other values in the same draft remain editable. Failure preserves the draft; it does not replace it with an empty preset. HDRI sources are copied into `content/assets/sky_hdri/`.

<span id="dialogue-files"></span>

## Did updating the addon replace my Excel data?

Actual workbooks belong to your project at `content/tables/`. The addon creates only missing empty workbooks and does not overwrite existing files. Close Excel before saving a different draft in the plugin. The reader expects direct values, not formulas.

## Default data locations

| Data | Location |
|---|---|
| Maps | `content/scenes/levels/` or your chosen project folder |
| Level index, events/tasks, dialogue | `content/tables/levels.xlsx`, `events.xlsx`, `dialogues.xlsx` |
| Task graphs | `content/resources/task_graphs/` |
| Personal assets | Project `content/` folders |
| Built-in code/assets | `addons/godot_level_editor/` |

The installation ZIP excludes author maps and personal workbooks. The repository's Source code download is a development snapshot and can contain them.

## Documentation images are not imported {#image-import}

The documentation and generated site contain `.gdignore` markers so Godot skips those image copies. Runtime assets live in the addon or project content folders. Do not remove documentation ignore markers to fix a runtime resource path.
