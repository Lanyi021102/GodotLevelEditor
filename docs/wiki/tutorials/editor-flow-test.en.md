# End-to-end workflow example

This example is in the development repository, not the installation ZIP. Open `content/scenes/levels/9_editor_flow_test.tscn` from Godot's native FileSystem and use F6.

## Play the sequence

Approach the tester and press F. Finish the stationary introduction to accept the event and start inventory/equipment checks. Continue the equipment dialogue, then press the nearby button twice, waiting for its reset between presses. One press leaves the door closed; the second starts opening it.

Walk through the opened door into the marked region. Stay there for about three seconds while parallel timers, variable conditions and a subgraph finish. A free-dialogue message completes automatically and a green completion message appears. Stop and restart F6 to repeat; this standalone session does not save long-term progress.

## Inspect the graphs

| Graph | Purpose | Nodes / connections |
|---|---|---|
| Level 9 persistent logic | NPC interaction, introduction, task acceptance | 4 / 2 |
| Task 1004001 | Inventory, equipment, condition combination and dialogue | 12 / 10 |
| Task 1004002 | Button count, mechanism action, door wait, Room and join | 12 / 10 |
| Task 1004003 | Checkpoint, parallel timers, numeric check, subgraph and exits | 15 / 16 |
| Child graph | Delay, actor state and return | 4 / 3 |

Open persistent logic through **关卡** and tasks through **任务 → 事件与任务**, event 1004. Main graphs and child graphs are under `content/resources/task_graphs/editor_flow_test/`; the example dialogue is under `content/resources/narrative/`.

## Evidence and troubleshooting

The original dated example record reports 47 nodes, 41 manually wired connections and two successful playthroughs. That record does not prove that failure/checkpoint branches or every editor feature were retested during plugin packaging. See the [original validation](../../qa/editor_flow_2026-11-17/validation.md).

If F does nothing, approach the object, wait for button reset and restore game focus. If the door is open but the task waits, enter the marked region and remain there. A normal dialogue saying the test is complete is not, by itself, evidence that all recorder checks passed.
