# Feature map

The separate window starts with **工作台** (Workspace); other pages initialize when first opened. Native placement and viewport tools remain available before that window is opened.

## Find the right editor

| What you want to make | Entry | Guide |
|---|---|---|
| Map geometry and layout | Native Godot scene tree, FileSystem, Inspector and 3D viewport | [Levels](guides/levels.md) |
| Whitebox shapes and placement | 3D toolbar **呼出轮盘**, face/edge/point tools | [Quick start](getting-started.md) |
| Persistent level logic | **关卡** for the current scene | [Levels](guides/levels.md) |
| Reusable mechanisms | **机关 → 我的机关** | [Mechanisms](tutorials/button-door.md) |
| Ordered objectives | **任务 → 事件与任务 / 任务图** | [Terms](reference/glossary.md) |
| Conversations | **台本** | [Dialogue modes](guides/dialogues.md) |
| NPC models and state machines | **NPC → 我的NPC** | [NPC examples](guides/npc-samples.md) |
| Sky, sun, fog and exposure | **天空** | [Environment](guides/sky.md) |
| UI scale and animation | **工作台** | [Preferences](guides/workbench.md) |
| HUD layout and appearance | Native 2D editor; addon `scenes/hud.tscn` and `resources/ui/hud_theme.tres` | [Developer index](development/index.md) |

## Three kinds of logic

**Mechanism graphs** define a reusable asset's internal components, states and actions. **Persistent level graphs** run independently of task acceptance. **Task graphs** run after their event starts, while that task is current and its level is active.

The five built-in mechanism assets are independent. Cross-object relationships are authored in a level or task graph. To require a fully opened door, wait for its real `open` state rather than treating an accepted command as completion.

## Assets and instances

An asset is a reusable scene or definition. An instance is one copy placed in a map, with its own transform and identity. Save built-in assets as your own copies before editing their source. Instance properties are edited in Godot's Inspector.

## Persistent and task-owned objects

The wheel offers **关卡常驻** (Persistent) and **任务对象** (Task-owned). Persistent objects follow the level lifetime. Task-owned objects need a task from that level and are visible, processed and collidable only while it is active; completion/failure disables them.

A Room is a box trigger, initially 1×1×1 m. Entering it activates the region and can drive level/task logic. See [Room triggers](guides/levels.md#room-triggers).

## Bind objects from the scene tree {#scene-reference-drop}

Drag one scene-tree object into the appropriate object/NPC/Room/actor/mechanism field at the bottom of a graph card or in its parameter panel. Valid targets highlight; dropping commits a normal undoable binding immediately. Save the graph afterward.

Only compatible objects from the current scene and task scope are accepted. Multi-selection, organizational folders, other levels and incompatible types do not replace the binding. Dropdown selection remains available. If a mechanism has several components, drag the intended component or select it explicitly.

## NPCs and runtime scope

Thirteen examples cover six humanoids, four animals and three monsters. Animation availability depends on the original model. Model animation, route movement, dialogue and hostile state transitions are configured separately.

## Task tracker {#task-tracker}

The HUD presents active event/task names as a list. Completed tasks use a strike-through/fade animation. Logical progression does not wait for the animation, and dialogue temporarily hides the tracker before restoring it.

## Task graph tools {#task-graph-tools}

Common buttons provide node search, save, undo/redo and frame-all. File, Edit, Binding and Play menus contain additional actions. Search groups nodes by function and supports Chinese/English terms. Task-local nodes follow the current task's stable ID.

Current runtime features include conditions, inventory/equipment checks, variables, waits, parallel/join flow, checkpoints and reusable subgraphs. Original contracts and dated tests are linked from the [developer index](development/index.md); a historical test count is not a claim that every combination was retested for this release.
