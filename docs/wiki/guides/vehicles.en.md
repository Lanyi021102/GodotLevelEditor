# Vehicle presets

Place, edit and playtest drivable vehicles. Built-in presets include a **kart**, a **motorcycle** and a **hovercraft**.

## Place a vehicle

1. In Godot’s 3D viewport, choose **呼出轮盘 → 载具** (Quick Add → Vehicles). Select a preset and left-click the ground to place it. The blue arrow points forward.
2. Select the vehicle and use the Inspector to edit driving, model and collision, boarding and exiting, and the driving camera.
3. Save the level and press F6. Walk to the boarding side and press F. Stop and press F again to get out. The right exit is tried if the left side is blocked. If both sides are blocked, the player stays aboard.

| Action | Default key |
|---|---|
| Accelerate, brake and reverse | W accelerates. S brakes, then reverses once stopped |
| Steer and look | A/D steer, mouse looks around, middle-click recenters the driving camera |
| Ascend and descend | Space ascends and Shift descends. A custom player preset also supports its crouch binding, C by default |
| Board and exit | F. Land the hovercraft before exiting |

Custom player presets supply the movement, interaction and ascent or descent bindings. Use **玩家 → 角色 → 可驾驶载具** to set whether a player can drive.

## Reuse a vehicle with your own model

1. Place a template and choose its driving mode. Drag a Godot-imported GLB, GLTF or 3D scene into **Model Scene**, and align it with the model offset, rotation and scale. An empty slot shows a whitebox vehicle.
2. Set **Body Size** and **Body Center** to adjust the blue collision box. Blue marks the boarding point, yellow the rider's pose origin, and green the left and right exits. Check those positions again after changing the model.
3. The default character uses sitting, seated idle and standing clips from Quaternius. To use custom character animations, enter their AnimationPlayer clip names under **Board Animation**, **Seated Animation** and **Exit Animation**. For a named library, enter `library/clip`.
4. Click **保存为载具预设** (Save as Vehicle Preset) at the top of the Inspector. Save the scene in `content/scenes/vehicles/`. The preset appears by display name under **Quick Add → Vehicles** in other levels.

Each placed instance is saved with the level scene. Ground vehicles use simple acceleration and collision. The hovercraft can stop in midair. See [asset credits](../../vehicle_editor/INTERFACES.md#vehicle-sources).
