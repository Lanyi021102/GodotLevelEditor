# Mechanisms and nodes

## Assets, states and actions

| Asset | States | Actions |
|---|---|---|
| Button | `idle`, `pressed` | `press`, `release` |
| Pressure plate | `released`, `pressed` | Driven by occupancy |
| Single/double door | `close`, `moving`, `open` | `open`, `close`, `toggle` |
| Lift | `at_start`, `moving`, `at_end`, `stopped` | `move_to_end`, `move_to_start`, `toggle`, `stop` |

Built-in scenes are under `addons/godot_level_editor/scenes/mechanisms/`. State/action IDs are technical identifiers and are not translated. Components validate supported transitions; restoring saved state does not replay completion events.

## Save, conflicts and copy {#save-and-copy}

Built-in addon assets are read-only. **Save** on an edited built-in opens **Save As** for a personal scene and matching graph under `content/scenes/mechanisms/`. Native saving also protects addon sources; a refusal keeps the draft unsaved until Save As finishes. Personal versions appear in My Mechanisms and the wheel and survive addon replacement.

A mechanism scene and its graph are saved together. If the source changes externally, reload or resolve the displayed conflict instead of silently replacing it. Invalid graphs do not become a successfully saved runnable asset. Use Save as for a personal copy; copy/paste and undo retain valid internal references while allocating independent identities where needed.

## Custom actions and button reset {#custom-actions}

Component state configuration can provide supported custom state/transition behavior. The button's reset/release delay belongs to its component. A request's accepted output and the eventual action-completed output are separate; cancelled or reversed motion must not be treated as an already completed action.

## Common graph nodes

| Node | Purpose |
|---|---|
| Door frame / hinged leaf | Actual fixed and movable objects |
| Rotation animation | Curve, duration, real angle, accepted/failed/completed outputs |
| Named state card | Current state and entry pulse |
| Button / plate / lift component | Reference to the actual component |
| Current state / state changed | Observe a continuing fact or transition |
| Interaction succeeded | React only to successful interaction |
| Request action / request state | Send a supported request to an instance |
| Action finished | React to actual completion or cancellation |
| Branch, AND, OR, NOT | Combine conditions and direct event flow |
| Rising edge | Convert a false→true change to one event |

## Level and task integration

Both graph types can inspect mechanism state, observe interactions/transitions/action completion, wait for a target state and request actions. Bind the correct scene instance from its dropdown or by scene-tree drag/drop. A mechanism with multiple components may require the specific component reference.

## Where parameters live

The graph selects objects, states, actions and connections. The native Inspector owns component dimensions, movement offsets, collision layers and occupancy settings. Door animation nodes expose duration and curve editing. Save the asset/map and restart play to test runtime behavior.

Built-ins remain independent until the level author connects them. See [independent mechanisms](../tutorials/button-door.md) and [rotating doors](../tutorials/rotating-door.md).
