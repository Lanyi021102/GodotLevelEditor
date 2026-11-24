# Quick start

Build and save a whitebox map with Godot's normal scene tools, then play it with F6. No script writing is required for this workflow.

## 1. Open the project

Use Godot 4.7.1 and [install the plugin](plugin-install.md), or open the development repository's `project.godot`. Wait for import and enable GodotLevelEditor.

In a new project without a main scene, activation creates `content/scenes/levels/start.tscn`. Press F5 to try the built-in player immediately.

## 2. Create a map with native scenes

1. Open **GodotLevelEditor → 工作台** (Workspace) and click **新建关卡** (New Level).
2. Godot opens an inherited map in the native 3D viewport.
3. Use **Scene → Save As** to save it as `content/scenes/levels/my_first_level.tscn`.

The template supplies a floor, player spawn, sky and empty logic. Your map is a normal `.tscn`, edited through the native scene tree, Inspector and 3D viewport. Its first save registers a stable level ID for task binding.

## 3. Place whitebox shapes and assets

Click **呼出轮盘** (Quick-add wheel) on the native 3D toolbar, or tap the backtick key / mouse side button. Choose **白盒体块** (Whitebox Shapes), pick a shape and left-click the ground to place it. Scroll to change pages, press R to rotate, and right-click / Esc to finish.

NPCs and mechanisms have an **已有素材** (Existing assets) option. Move, rotate, scale and undo with Godot's normal controls. Face/edge/point tools and the 0.1 / 0.5 / 1 m step settings are also available. See [levels and the wheel](guides/levels.md).

## 4. Save and play

Keep the player spawn above a solid floor. Save the scene with Godot and press **F6**. The player, camera, HUD and persistent level logic are attached at runtime, rather than stored as extra authored map objects.

WASD moves, Shift runs, Space jumps and F interacts. Esc releases the mouse; click the game viewport to regain control. Stop play to continue editing. F5 runs the project's configured main scene.

## 5. Add logic

Select a map in **关卡 → 我的关卡**. Choose **打开场景** to build in 3D or **编辑常驻逻辑** to wire interactions. **继续上次关卡** on the Workspace reopens your latest map.

Use your map for the [button and door exercise](tutorials/button-door.md#wire-button) or the [conversation and task exercise](guides/npc-samples.md#first-conversation-task).

Check that the map appears in FileSystem, keeps its layout after reopening, and starts the character at the intended spawn when played with F6.
