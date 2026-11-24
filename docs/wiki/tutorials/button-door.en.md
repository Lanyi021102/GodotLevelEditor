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

A new mechanism starts with an empty graph. **添加节点** adds components; a single/double door adds its own frame, leaves, animation and state graph, not an external button. Place your saved scene through the wheel's **机关 → 已有素材**, save the map and use F6.

## Connect a button to one door {#wire-button}

1. Create an inherited map from **工作台 → 新建关卡** and save it. In the native wheel, choose **机关**, hover over **关卡常驻机关**, then open **已有素材**. Place a button and two independent single doors. Space the doors apart and save the map.
2. Select the map in **关卡 → 我的关卡** and click **编辑常驻逻辑**. Add **机关交互成功时** (On successful mechanism interaction) and **请求机关执行动作** (Request mechanism action).
3. Drag the placed button from the scene tree into the trigger’s mechanism field. Drag the first door into the action’s mechanism field, choose `open` and click **应用参数**.
4. Connect the trigger’s **继续** output to the action’s **执行** input. Save the graph, press F6 in the native viewport and press F at the button. Only the first door should swing open.
5. Stop, bind the action to the other door, check that it still requests `open`, save and play again. Now the second door should open. If neither moves, check the two instance bindings and the action.

## Check the result

Pressing a button changes that button's state. It does not control another door or lift until you connect that relationship in a level/task graph. Doors respond to their own interaction, plates to occupancy, and lifts to interaction on the moving platform.

To make a task wait for a door to finish, observe its `open` state. An accepted request alone is not completion. See [rotating doors](rotating-door.md) and the [node reference](../reference/mechanisms.md).

The development repository has `content/scenes/levels/mechanism_whitebox_v1.tscn` for an independent-asset check. Author demo maps are not in the installation ZIP.
