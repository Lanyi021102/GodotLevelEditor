# Levels and the quick-add wheel

Maps are ordinary Godot scenes. Open, organize, save and play them using the native editor.

## Open or create a level

Open a `.tscn` from FileSystem. To create one, right-click the addon's `templates/empty_level.tscn`, choose **New Inherited Scene**, and save outside the addon, normally in `content/scenes/levels/`.

The separate **关卡** page edits only the current scene's persistent logic. The old custom map-card catalog is no longer the current map workflow.

## Add objects with the wheel

1. In the native 3D viewport, click **呼出轮盘**, tap backtick, or tap the mouse side button.
2. Choose a category. Layout whitebox pages contain eight shapes; the wheel changes pages and middle-click advances one page.
3. Choose an asset, hover the ground, then left-click to place. R / Shift+R rotate by ±15°.
4. Right-click or Esc finishes placement. In a submenu, right-click returns to the parent wheel.

NPC and mechanism categories offer persistent/task-owned objects and **已有素材** (Existing assets). Task objects need a task belonging to the current level. The recently used list reuses prior asset choices.

## Position, dimensions and precision

Use Godot's move, rotate and scale tools. **选中面 / 选中线 / 选中点** select a face, edge or point and place the manipulator at that element. Clear the selection to restore the object manipulator.

Enter the step directly or choose 0.1 / 0.5 / 1 m. Placement and editing share the step. The metric grid shows 1 m, 0.5 m and 0.1 m divisions and retains real scale after resizing.

## Edit an instance or an asset

Instance transforms, model selection, faction, default animation and task ownership are stored on the scene instance. A source asset may be reused by many instances. Save built-ins as your own assets before changing them; user mechanism/NPC libraries are scanned alongside built-ins.

## Room triggers {#room-triggers}

A new Room is a 1×1×1 m box trigger. It does not block the player. Persistent Rooms are dark translucent green in the editor; task Rooms use lighter green. Dimensions, region material and whether activation remains after exit are Inspector properties.

The player's entry activates the Room before the entry event is emitted. Leaving the final occupant normally deactivates it. Level/task graphs can observe entry, exit and the current active state. Task ownership and region activation are separate: an inactive task's Room does not detect players.

## Scene organization

New NPCs, Rooms, mechanisms and whitebox objects are organized under `NPCs`, `Rooms`, `Mechanisms` and `Whitebox`. Native duplication remains undoable and assigns independent object identities where required. Existing content is not rearranged merely by opening it.

## Duplicate, move or remove {#copy-delete}

Use Godot's native Duplicate and FileSystem operations. The plugin follows native file/folder move and removal notifications to update its level index and task-graph file references. Stable IDs are retained on a move.

If a whole-map copy reports a duplicate level ID, save it again to assign an independent one; the original remains bound to its original tasks. Before deleting a task-bound map, update or remove the affected task binding. Native deletion does not run the old catalog's deletion-protection dialog, and invalid task references are reported by validation.

## Save and play

Save with Godot and use F6. A first save registers the level ID used by tasks. Persistent logic is saved with the map; task graphs and dialogue workbooks have their own save actions.

### Historical thumbnails {#level-thumbnail}

Old map thumbnails remain in the project's `content/resources/level_previews/`. They are excluded from installation ZIPs, and the current native workflow does not depend on the removed map-card catalog.
