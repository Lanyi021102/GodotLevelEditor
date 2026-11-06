extends Node
const WORLD_SCENE := preload("res://scenes/level_editor/continuous_world.tscn")
const GRAPH := preload("res://addons/branch_level_editor/runtime/level_graph.gd")
const FACTORY := preload("res://addons/branch_level_editor/scene_factory.gd")
const PANEL := preload("res://addons/branch_level_editor/graph_panel.gd")
const RUNNER := preload("res://addons/branch_level_editor/runtime/event_runner.gd")
const ACTOR := preload("res://tools/level_editor/test_actor.gd")
var passed := 0
var failed := 0
var world: Node3D
var actor: CharacterBody3D
var helpers: Array[Node] = []
var crossings: Array = []
var completions: Array = []
var checkpoints: Array = []
var objectives: Array = []
var folder := "/tmp/branch_level_editor_" + str(OS.get_process_id())

func _ready() -> void:
	get_tree().create_timer(90).timeout.connect(func(): push_error("LEVEL EDITOR watchdog"); get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute(folder)
	await _run()

func _run() -> void:
	_test_scene_roundtrip()
	_test_graph_validation()
	_test_data_types()
	await _test_canvas()
	world = WORLD_SCENE.instantiate()
	world.room_entered.connect(func(a: String, b: String, _body: Node3D): crossings.append([a, b]))
	world.goal_completed.connect(func(id: String): completions.append(id))
	world.progress_requested.connect(func(progress: Dictionary): checkpoints.append(progress))
	world.objective_changed.connect(func(text: String): objectives.append(text))
	add_child(world)
	await _wait(4)
	_check(world.validate().is_empty() and world.runtime_valid, "world runtime validates")
	_check(world.rooms().size() == 4, "atrium + three instanced room scenes")
	_check(world.runtime_components().size() == 11, "existing mechanisms + two guards reused")
	_check(not _port("atrium/north").unlocked and _port("atrium/east").unlocked, "initial shortcut locked; atrium to puzzle 1 open")
	for component in world.runtime_components().values():
		if component is GuardAI: component.set_physics_process(false)
	# Keep the seam route clear of user-authored props near the portal center.
	actor = _actor(Vector3(8, 0.05, 1), false, true)
	actor.travel = Vector3(3, 0, 0)
	await _wait(90)
	actor.travel = Vector3.ZERO
	_check(actor.global_position.x > 11, "actual actor crosses continuous floor seam")
	_check(crossings.has(["atrium", "puzzle_1"]), "directional room entry signal from aligned spatial edge")
	actor.travel = Vector3(-3, 0, 0)
	await _wait(90)
	actor.travel = Vector3.ZERO
	_check(crossings.has(["puzzle_1", "atrium"]), "reverse traversal reports reverse room")
	actor.global_position = Vector3(20, 0.05, -8)
	actor.travel = Vector3(0, 0, -4)
	await _wait(65)
	actor.travel = Vector3.ZERO
	_check(actor.global_position.z > -9.7, "locked connection physically blocks traversal")
	var original_events: Dictionary = world.events.snapshot()
	var before_progress: Dictionary = world.tl_capture()
	for i in 3:
		await _solve_room(i + 1)
	_check(completions == ["goal_1", "goal_2", "goal_3"], "all three goals execute once in order")
	_check(checkpoints.size() == 3 and checkpoints[2].states.get("latch_3", false), "checkpoint includes same-frame latch updates")
	_check(objectives == ["捷径已开启，返回中庭"], "goal wire executes objective output")
	_check(_port("atrium/north").unlocked and _port("puzzle_3/south").unlocked, "third goal unlocks both shortcut endpoints")
	world.tl_restore(before_progress)
	_check(_port("atrium/north").unlocked and world.runner.persistent.get("goal_3", false), "rewinding local graph state preserves explicit permanent progress")
	_check(world.events.snapshot() == original_events, "runtime never mutates graph resource")
	await _test_changed_wire()
	await _test_shortcut_walk()
	var save := FileAccess.open(folder + "/progress.json", FileAccess.WRITE)
	save.store_string(JSON.stringify(world.capture_progress()))
	save.close()
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/progress.json"))
	_check(stored.states.get("latch_3", false), "progress written to isolated test save")
	var current: Dictionary = world.capture_progress()
	var bad := current.duplicate(true)
	bad.states["missing_node"] = true
	_check(not world.restore_progress(bad) and world.capture_progress() == current, "invalid progress rejected atomically")
	for helper in helpers: helper.queue_free()
	actor.queue_free()
	world.queue_free()
	await _wait(3)
	world = WORLD_SCENE.instantiate()
	add_child(world)
	await _wait(3)
	_check(not _port("atrium/north").unlocked, "fresh runtime starts with locked shortcut")
	_check(world.restore_progress(stored) and _port("atrium/north").unlocked, "independent save restores shortcut in a new world instance")
	_test_pending_snapshot()
	world.queue_free()
	await _wait(2)
	for file in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + file)
	DirAccess.remove_absolute(folder)
	print("LEVEL EDITOR: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _test_scene_roundtrip() -> void:
	for id in ["atrium", "puzzle_1", "puzzle_2", "puzzle_3"]:
		var room: Node3D = load("res://scenes/level_editor/rooms/" + id + ".tscn").instantiate()
		var count := room.get_child_count()
		var block: Node3D = room.object_by_id("floor")
		block.size.x = 21.26
		block.position.x = 0.75
		var file: String = folder + "/" + id + ".tscn"
		_check(FACTORY.save_scene(room, file) == OK, id + " room saves")
		room.free()
		var fresh: Node3D = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		_check(fresh.room_id == id and fresh.get_child_count() == count and is_equal_approx(fresh.object_by_id("floor").size.x, 21.3) and fresh.object_by_id("floor").position.x == 0.75, id + " layout + stable IDs survive disk reload")
		if id == "puzzle_3":
			_check(fresh.object_by_id("door").source_ids == PackedStringArray(["plate_a", "plate_b", "breaker"]), "legacy component bindings survive room reload")
		fresh.free()
	var graph: BranchLevelGraph = load("res://resources/level_editor/world_events.tres").duplicate(true)
	graph.positions["goal_1"] = Vector2(123, -67)
	graph.view_scroll = Vector2(98, 43)
	graph.view_zoom = 1.2
	_check(ResourceSaver.save(graph, folder + "/events.tres") == OK, "graph saves to .tres")
	var fresh_graph: BranchLevelGraph = ResourceLoader.load(folder + "/events.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(fresh_graph.snapshot() == graph.snapshot(), "nodes + parameters + wires + layout + view reload exactly")

func _test_graph_validation() -> void:
	var base: BranchLevelGraph = load("res://resources/level_editor/world_events.tres")
	_check(base.validate().is_empty(), "sample event graph validates")
	var bad: BranchLevelGraph = base.duplicate(true)
	bad.schema_version = 999
	_check(not bad.validate().is_empty() and not RUNNER.new().configure(bad, Callable()), "unsupported version rejected")
	bad = base.duplicate(true)
	bad.edges[0].to_port = "missing"
	_check(not bad.validate().is_empty(), "invalid port rejected")
	bad = base.duplicate(true)
	bad.edges[0].from = "missing"
	_check(not bad.validate().is_empty(), "dangling node rejected")
	bad = base.duplicate(true)
	bad.edges[0].from = "goal_1"
	bad.edges[0].from_port = "completed"
	_check(not bad.validate().is_empty(), "event-to-bool type mismatch rejected")
	bad = base.duplicate(true)
	bad.nodes.append({"id": "and_cycle", "kind": "all", "params": {}})
	bad.edges.append({"id": "cycle", "from": "and_cycle", "from_port": "value", "to": "and_cycle", "to_port": "a"})
	_check(not bad.validate().is_empty(), "unbounded feedback rejected")
	var scene := WORLD_SCENE.instantiate()
	scene.events = scene.events.duplicate(true)
	scene.events.nodes[0].params.object = "puzzle_1/missing"
	_check(not scene.validate().is_empty(), "dangling scene binding rejected")
	scene.free()
	scene = WORLD_SCENE.instantiate()
	scene.rooms()[1].position.x += 1
	_check(not scene.validate().is_empty(), "misaligned physical ports rejected")
	scene.free()

func _test_data_types() -> void:
	var graph := GRAPH.new()
	graph.graph_id = "typed_test"
	graph.nodes = [{"id": "big", "kind": "number", "params": {"value": 3.5}}, {"id": "small", "kind": "number", "params": {"value": 2.0}}, {"id": "compare", "kind": "greater", "params": {}}, {"id": "reference", "kind": "object", "params": {"object": "room/component"}}, {"id": "read", "kind": "read_state", "params": {"query": "powered"}}]
	graph.edges = [{"id": "number_a", "from": "big", "from_port": "value", "to": "compare", "to_port": "a"}, {"id": "number_b", "from": "small", "from_port": "value", "to": "compare", "to_port": "b"}, {"id": "object_wire", "from": "reference", "from_port": "value", "to": "read", "to_port": "target"}]
	var runner := RUNNER.new()
	_check(runner.configure(graph, func(_id: String): return null), "numeric and object-reference ports validate")
	runner.tick()
	_check(runner.values.big == 3.5 and runner.values.compare and runner.values.reference == "room/component" and not runner.values.read, "typed wires evaluate actual values")
	graph.edges[0].to = "read"
	graph.edges[0].to_port = "target"
	_check(not graph.validate().is_empty(), "number-to-object type mismatch rejected")

func _test_canvas() -> void:
	var panel := PANEL.new()
	add_child(panel)
	var graph: BranchLevelGraph = load("res://resources/level_editor/world_events.tres").duplicate(true)
	panel.open_graph(graph)
	await get_tree().process_frame

	_check(panel.canvas.get_node_or_null("goal_1") is GraphNode, "real GraphEdit / GraphNode canvas renders definition")
	var before := graph.snapshot()
	panel.disconnect_ports("goal_1", 0, "latch_1", 0)
	_check(graph.edges.size() == before.edges.size() - 1, "canvas disconnect mutates execution definition")
	panel.undo.undo()
	_check(graph.snapshot() == before, "disconnect undo restores exact graph")
	panel.undo.redo()
	panel.connect_ports("goal_1", 0, "latch_1", 0)
	_check(graph.edges.size() == before.edges.size(), "canvas drag-connect restores semantic wire")
	panel.selected_id = "goal_1"
	panel._show_parameters()
	panel._fields.label.text = "重命名目标"
	panel._apply_parameters()
	_check(graph.node_by_id("goal_1").label == "重命名目标" and graph.node_by_id("goal_1").id == "goal_1", "parameter editing preserves stable ID")
	panel.undo.undo()
	_check(graph.node_by_id("goal_1").label != "重命名目标", "parameter undo works")
	panel.canvas.get_node("goal_1").selected = true
	panel.copy_selected()
	panel.paste_selected()
	_check(graph.nodes.size() > before.nodes.size() and graph.nodes.back().id != "goal_1", "copy-paste allocates fresh graph IDs")
	panel.undo.undo()
	_check(graph.nodes.size() == before.nodes.size(), "copy undo removes new graph nodes")
	panel._move_before = graph.snapshot()
	panel.canvas.get_node("goal_1").position_offset = Vector2(87, 91)
	panel._end_move()
	_check(graph.positions.goal_1 == Vector2(87, 91), "canvas position stored separately")
	panel.undo.undo()
	_check(graph.positions.goal_1 == before.positions.goal_1, "layout movement undo works")
	var packet := {"graph_id": graph.graph_id, "topology_id": "other", "world_id": "test", "values": {"source_1": true}, "persistent": {}, "local": {}, "reasons": {"source_1": "真实门开启"}, "instance": "/test"}
	panel.receive_runtime("1:/test", packet)
	_check(panel.canvas.get_node("source_1/Runtime").text.contains("是"), "runtime value reaches graph node display")
	packet["event_revision"] = "previous_runtime_definition"
	packet["restored"] = true
	panel.receive_runtime("1:/test", packet)
	_check(panel.canvas.get_node("source_1/Runtime").text.contains("启动时定义"), "runtime definition mismatch is shown explicitly")
	_check(panel.canvas.get_node("source_1/Runtime").text.contains("已恢复快照"), "rewind refresh is displayed while paused")
	panel.clear_session(1)
	_check(panel.canvas.get_node("source_1/Runtime").text.contains("无运行实例"), "stopped session clears runtime display")
	graph.take_over_path(folder + "/canvas.tres")
	_check(panel.save_graph(), "canvas save button writes validated definition")
	panel.save_reload()
	_check(panel.status.text.contains("已从磁盘重载"), "canvas save-reload button completes disk roundtrip")
	panel.dirty = false
	panel.queue_free()
	await get_tree().process_frame

func _solve_room(index: int) -> void:
	var prefix := "puzzle_%d/" % index
	var door: Node = world.object_by_id(prefix + "door").runtime_component
	actor.global_position = world.object_by_id(prefix + "goal_region").global_position + Vector3(0, 0.05, 0)
	await _wait(4)
	_check(not completions.has("goal_" + str(index)), "room %d cannot complete with closed door" % index)
	var plate: Node3D = world.object_by_id(prefix + "plate_a")
	helpers.append(_actor(plate.global_position + Vector3(0, 0.05, 0), true, false))
	if index >= 2:
		var second: Node3D = world.object_by_id(prefix + "plate_b")
		var mover := _actor(second.global_position + Vector3(0, 0.05, 0), true, false)
		mover.oscillation_center = second.global_position
		mover.oscillate = true
		helpers.append(mover)
	if index == 3:
		helpers.append(_actor(world.object_by_id(prefix + "breaker").global_position + Vector3(0, 0.05, 0), true, false))
	# Move the controlled actor away while the sources open the actual component door.
	actor.global_position = world.object_by_id(prefix + "door").global_position + Vector3(0, -1.1, 2)
	await _wait(80)
	_check(door.is_open(), "room %d actual legacy sources open actual door" % index)
	actor.clone_actor = true
	actor.global_position = world.object_by_id(prefix + "goal_region").global_position + Vector3(0, 0.05, 0)
	await _wait(4)
	_check(not completions.has("goal_" + str(index)), "room %d clone cannot trigger controlled-player goal" % index)
	actor.clone_actor = false
	actor.global_position = world.object_by_id(prefix + "door").global_position + Vector3(0, -1.1, 2)
	actor.travel = Vector3(0, 0, -4)
	await _wait(75)
	actor.travel = Vector3.ZERO
	_check(actor.global_position.z < world.object_by_id(prefix + "door").global_position.z - 2, "room %d actor physically traverses puzzle door" % index)
	_check(completions.has("goal_" + str(index)), "room %d region + graph condition produces completion" % index)
	_check(_port(prefix + (["north", "west", "south"][index - 1])).unlocked, "room %d graph unlocks next connection" % index)
	await _wait(5)

func _test_changed_wire() -> void:
	var changed: BranchLevelGraph = world.events.duplicate(true)
	changed.edges = changed.edges.filter(func(e: Dictionary): return not (e.from == "goal_3" and e.to == "latch_3"))
	var runner := RUNNER.new()
	_check(runner.configure(changed, world.object_by_id), "disconnected graph remains a valid definition")
	actor.global_position = world.object_by_id("puzzle_3/goal_region").global_position + Vector3(0, 0.05, 0)
	await _wait(4)
	runner.tick()
	_check(runner.persistent.get("goal_3", false) and not runner.link_enabled("link_3"), "removing completion-to-latch wire prevents shortcut unlock")
	var restored := RUNNER.new()
	restored.configure(world.events, world.object_by_id)
	restored.tick()
	_check(restored.link_enabled("link_3"), "reconnecting same wire changes runtime result")

func _test_shortcut_walk() -> void:
	actor.global_position = Vector3(0, 0.05, -12)
	actor.travel = Vector3(0, 0, 3)
	await _wait(90)
	actor.travel = Vector3.ZERO
	_check(actor.global_position.z > -9 and crossings.has(["puzzle_3", "atrium"]), "unlocked shortcut is physically walkable back to atrium")

func _test_pending_snapshot() -> void:
	var graph := GRAPH.new()
	graph.graph_id = "snapshot_test"
	graph.nodes = [{"id": "memory", "kind": "latch", "params": {"persistent": false}}, {"id": "notify", "kind": "objective", "params": {"text": "once"}}]
	var runner := RUNNER.new()
	runner.configure(graph, Callable())
	runner.pending = [{"to": "memory", "port": "set", "from": "test"}, {"to": "notify", "port": "run", "from": "test"}]
	var calls := []
	runner.objective_requested.connect(func(text: String): calls.append(text))
	var state := runner.capture()
	runner.tick()
	_check(runner.local_state.get("memory", false) and calls.size() == 1, "event queue executes local state and one output")
	runner.restore(state)
	_check(calls.size() == 1 and runner.pending.size() == 2 and runner.local_state.is_empty(), "restore recovers pending queue without replaying effects")
	_check(not runner.values.memory, "snapshot restore immediately refreshes displayed continuous values")
	runner.tick()
	_check(calls.size() == 2 and runner.local_state.get("memory", false), "restored queue resumes on next physics tick")

func _actor(at: Vector3, is_clone_actor: bool, controlled: bool) -> CharacterBody3D:
	var body := ACTOR.new()
	body.position = at
	body.clone_actor = is_clone_actor
	if controlled: body.add_to_group("branch_player")
	add_child(body)
	return body

func _port(id: String) -> Node: return world.object_by_id(id)
func _wait(frames: int) -> void:
	for _i in frames: await get_tree().physics_frame
func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)
