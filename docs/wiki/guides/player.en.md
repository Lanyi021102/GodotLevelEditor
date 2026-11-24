# Player 3C presets

A player preset defines character abilities, camera, controls and animation clips. Levels can share a preset or select different presets for their routes and gameplay.

## Create a preset and apply it to a level

1. Open a native level and use Godot's **Scene → Save As** to save it outside the addon.
2. In GodotLevelEditor, choose **玩家 → 新建预设** (Player → New Preset). Enter a name and use the bundled character or choose your own 3D scene.
3. Use **角色** (Character) to enable abilities and tune values. Configure **镜头** (Camera) and **控制** (Controls). Bind and play the model's clips in **动作** (Animations).
4. Click **保存预设** (Save Preset), then **应用到当前关卡** (Apply to Current Level). Save the scene in Godot and press F6.
5. Use **关卡 → 关卡编辑 → 玩家预设** (Levels → Level Editing → Player Preset) to switch presets or select **默认第三人称** (Default Third Person). Godot Undo and Redo support the binding.

Use **复制预设** (Duplicate Preset) for a different combination of abilities. Saving changes to a shared preset affects every level that uses it the next time it runs. Presets live in `content/resources/player_presets/`. The level stores an external resource reference.

## Abilities and default controls

| Ability | Initial state | Default controls |
|---|---|---|
| Walk, run, jump, interact | On | WASD, Shift, Space, F |
| Sprint, crouch, dodge roll | Off | Ctrl, C, Q |
| Double jump | Off | Enable jump, then press Space again in mid-air |
| Automatic steps | Off | Move toward a step within the configured height |
| Vault, mantle | Each off | E. Vault over a thin obstruction or pull up onto a wide ledge |
| Drive vehicles | On | Press F near a vehicle. See [Vehicle presets](vehicles.md) |
| Climb | Off | Press X in a climb zone to start or stop, then W/S to move up and down |
| Focus, swap shoulder, recenter | On | Right button or Z, V, middle button or R |

Click a binding in **控制** to change its keyboard or gamepad input. The left stick moves and the right stick looks. Choose an over-the-shoulder, first-person or fixed-angle view. The fixed-angle camera follows the player while keeping its configured orientation.

For a ladder, click **添加攀爬区** (Add Climb Zone) on the Player page and place the area in front of the ladder in the native 3D viewport. Size its collision box to the climb and point its local +Z away from the ladder. Leaving the area or pressing the climb button again returns the player to gravity.

## Animation sources and custom models

The bundled player uses Quaternius CC0 assets. Idle, walking, running, jumping, landing and crouching reuse the project clips. Sprint, roll and interaction are retargeted from the same source library. Ladder climbing and stepping over are trimmed and retargeted from the [CMU Motion Capture Database](https://mocap.cs.cmu.edu/). `moves/Climb` is bound by default, and `moves/StepOver` can be bound to automatic steps. Vault and mantle use whitebox animations authored in the project. See [Quaternius Universal Animation Library 2](https://quaternius.itch.io/universal-animation-library-2) for additional animations.

A custom character scene needs a Node3D root and an AnimationPlayer. Assign its imported clips in the Animations tab. Empty animation slots still allow the configured ability to run. Import the model and clips and retarget the skeleton in Godot before binding them here.

To add clips to the bundled model, put an animation GLB in the project and let Godot import it. Select it in **动作 → 附加动画包** (Animations → Additional Animation Pack) and choose a clip prefixed with `imported/`. Compatible Quaternius rigs retarget by bone name. For other rigs, retarget in Godot and select a clip from the character scene.
