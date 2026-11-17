# Use independent mechanisms

Open **机关 → 我的机关**. The library contains five independent assets; relationships between different objects are authored explicitly.

| Asset | Independent behavior |
|---|---|
| Double door | Interaction toggles two leaves to +90° / −90° |
| Single door | Interaction toggles one leaf to 90° |
| Pressure plate | Occupancy drives pressed/released |
| Button | F presses it; it returns to idle after its configured delay |
| Lift platform | F on the platform travels to the other end; F again returns |

## Make a personal copy {#own-copy}

Select an asset, then double-click or choose **进入编辑**. Use **另存为** before editing a built-in. Keep personal scenes under `content/scenes/mechanisms/`.

A new mechanism starts with an empty graph. **+ 节点** adds components; a single/double door adds its own frame, leaves, animation and state graph, not an external button. Place your saved scene through the wheel's **机关 → 已有素材**, save the map and use F6.

## Check the result

Pressing a button changes that button's state. It does not control another door or lift until you connect that relationship in a level/task graph. Doors respond to their own interaction, plates to occupancy, and lifts to interaction on the moving platform.

To make a task wait for a door to finish, observe its `open` state. An accepted request alone is not completion. See [rotating doors](rotating-door.md) and the [node reference](../reference/mechanisms.md).

The development repository has `content/scenes/levels/mechanism_whitebox_v1.tscn` for an independent-asset check. Author demo maps are not in the installation ZIP.
