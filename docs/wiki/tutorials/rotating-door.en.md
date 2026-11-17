# Inspect and adjust rotating doors

In **机关 → 我的机关**, open the 2×3 single door or 4×3 double door. Dimensions are the outer frame width and height in meters. Save your own copy before changing a built-in.

## Read the graph

Seven nodes represent the fixed frame, hinged leaves, player interaction, rotation animation, and the `close`, `moving`, `open` states. Object connections follow frame → leaves → animation → states; the interaction event runs the animation.

A green state card means that state is currently true. Its entry port pulses only when entering the state. The frame stays fixed; leaves and collision rotate around side hinges. Double-door leaves use opposite rotation signs.

## Edit the curve

1. Select the rotation-animation node. Change duration or choose ease-in/out versus linear motion.
2. The horizontal axis is normalized time; the vertical axis maps 0° to 90°. Click to add an interior point, drag to reshape it and right-click to remove it.
3. Endpoints `(0,0)` and `(1,1)` are fixed. Closing reads the same curve backward; reversing mid-motion continues from the current angle.
4. Use the open/close preview or simulated interaction. The playhead and angle read the real preview component.
5. Check undo/redo and save.

The preview is isolated from the saved initial state. To start open, set the component's initial state to `open`, rather than saving a transient preview position.

## Use the door in a map or task

Place the saved asset through the wheel and press F nearby during F6. Task/level nodes can inspect `close / moving / open`. Requests target `close` or `open`; `moving` is an observation state. Wait for `open` or actual animation completion when a later action requires a fully open door.

A reversal cancels the prior action and proceeds in the opposite direction. A locked door rejects opening while still allowing closure. Missing inputs, cross-door structural links and invalid curves are reported by validation.

See [save/copy behavior](../reference/mechanisms.md#save-and-copy) and the original [mechanism contract](../../mechanism_editor/INTERFACES.md).
