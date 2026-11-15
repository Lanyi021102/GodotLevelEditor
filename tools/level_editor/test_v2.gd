extends Node
const F := preload("res://addons/godot_level_editor/scene_factory.gd")
const G := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
const SHAPES := preload("res://addons/godot_level_editor/runtime/whitebox_shapes.gd")
const RUNNER := preload("res://addons/godot_level_editor/runtime/event_runner.gd")
const DEMO := preload("res://scenes/levels/logic_playground.tscn")
var passed := 0
var failed := 0
var directory := "/tmp/godot_level_editor_level_v2_" + str(OS.get_process_id())
func _ready() -> void:
	get_tree().create_timer(70).timeout.connect(func(): push_error("V2 watchdog"); get_tree().quit(2))
	DirAccess.make_dir_recursive_absolute(directory)
	await _geometry()
	await _logic()
	_budget_and_snapshot()
	for file in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory + "/" + file)
	DirAccess.remove_absolute(directory)
	print("LEVEL EDITOR V2: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
func _geometry() -> void:
	var root := Node3D.new()
	add_child(root)
	var index := 0
	var nodes := {}
	for kind in SHAPES.LABELS:
		var block := F.BLOCK.new()
		block.shape_kind = kind
		if kind == "tube": block.curve_angle = 360
		block.position = Vector3(index * 3, 0.5, 0)
		root.add_child(block)
		nodes[kind] = block
		var geometry: ArrayMesh = block.geometry()
		_check(block.size == Vector3.ONE and geometry.get_aabb().size.is_equal_approx(Vector3.ONE), kind + " defaults to true unit bounds")
		_check(geometry.get_faces().size() >= 12 and not geometry.create_trimesh_shape().get_faces().is_empty(), kind + " has matching collision triangles")
		var id: String = block.object_id
		var file: String = directory + "/" + kind + ".tscn"
		_check(F.save_scene(block, file) == OK, kind + " saves")
		var fresh: Node3D = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		_check(fresh.shape_kind == kind and fresh.object_id == id and fresh.size == Vector3.ONE, kind + " reloads shape parameters and stable ID")
		fresh.free()
		index += 1
	var unit := F.BLOCK.new()
	unit.size = Vector3(1.26, 0.04, 2.34)
	_check(unit.size.is_equal_approx(Vector3(1.3, 0.1, 2.3)), "stretch rounds to 0.1 and clamps minimum")
	unit.shape_kind = "tube"
	unit.curve_angle = 90
	F.save_scene(unit, directory + "/quarter_tube.tscn")
	var quarter: Node3D = ResourceLoader.load(directory + "/quarter_tube.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	_check(quarter.curve_angle == 90 and quarter.geometry().get_faces().size() < nodes.tube.geometry().get_faces().size(), "custom quarter-tube angle survives reload independently of shape defaults")
	quarter.free()
	unit.free()
	await _wait(4)
	_check(_ray(nodes.box.global_position + Vector3(0, 2, 0), nodes.box.global_position - Vector3(0, 2, 0)), "cube collider is solid")
	_check(_ray(nodes.ramp.global_position + Vector3(0, 2, 0), nodes.ramp.global_position - Vector3(0, 2, 0)), "ramp winding produces a walkable top collider")
	_check(not _ray(nodes.doorway.global_position + Vector3(0, 0, 2), nodes.doorway.global_position - Vector3(0, 0, 2)), "doorway opening is actually hollow")
	_check(_ray(nodes.doorway.global_position + Vector3(0.45, 0, 2), nodes.doorway.global_position + Vector3(0.45, 0, -2)), "doorway post remains solid")
	_check(not _ray(nodes.window.global_position + Vector3(0, 0, 2), nodes.window.global_position - Vector3(0, 0, 2)), "window opening is actually hollow")
	_check(not _ray(nodes.tube.global_position + Vector3(0, 2, 0), nodes.tube.global_position - Vector3(0, 2, 0)), "tube preserves its hollow center")
	nodes.box.scale = Vector3(2, 1.5, 0.5)
	nodes.ramp.scale = Vector3(2, 0.5, 1.5)
	nodes.doorway.scale = Vector3(3, 2, 0.5)
	await _wait(3)
	_check(_ray(nodes.box.global_position + Vector3(0.8, 2, 0), nodes.box.global_position + Vector3(0.8, -2, 0)), "nonuniform stretch expands actual box collision")
	_check(not _ray(nodes.box.global_position + Vector3(0, 2, 0.4), nodes.box.global_position + Vector3(0, -2, 0.4)), "nonuniform stretch shrinks actual box collision")
	_check(_ray(nodes.ramp.global_position + Vector3(0.8, 2, 0), nodes.ramp.global_position + Vector3(0.8, -2, 0)), "nonuniform ramp scale updates triangle collision")
	_check(not _ray(nodes.doorway.global_position + Vector3(0, 0, 2), nodes.doorway.global_position - Vector3(0, 0, 2)), "scaled doorway keeps its collision opening")
	root.queue_free()
	await _wait(2)
func _ray(a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a, b, 1)
	return not get_viewport().find_world_3d().direct_space_state.intersect_ray(query).is_empty()
func _make_world(has_key := true, connected := true) -> Node3D:
	var world := DEMO.instantiate()
	world.get_node("预览玩家").input_enabled = false
	if not has_key: world.get_node("预览玩家/LevelAgent").unlocked_items = PackedStringArray()
	if not connected:
		world.events = world.events.duplicate(true)
		world.events.edges = world.events.edges.filter(func(e: Dictionary): return not (e.from == "if_key" and e.to == "open_switch"))
	add_child(world)
	return world
func _logic() -> void:
	var world := _make_world()
	var actor: CharacterBody3D = world.get_node("预览玩家")
	var agent: Node = actor.get_node("LevelAgent")
	var lever: Node = world.object_by_id("demo_room/switch").runtime_component
	var guard: Node = world.object_by_id("demo_room/guard").runtime_component
	await _wait(5)
	_check(world.runtime_valid and world.validate().is_empty(), "new nodes and Room bindings validate in saved demo")
	_check(world.runner.counts.get("begin") == 1 and world.runner.counts.get("received") == 1, "game-start event fires once and named event is delivered")
	_check(not lever.is_powered() and not guard.is_physics_processing(), "actions wait for actual room entry")
	actor.travel = Vector3.RIGHT
	await _wait(65)
	actor.travel = Vector3.ZERO
	_check(world.runner.counts.get("enter", 0) == 1, "real Room volume emits player-enter trigger once")
	_check(world.runner.values.key and world.runner.values.if_key, "inventory condition reads actual player adapter")
	_check(lever.is_powered(), "true godot_level_editor actually opens switch")
	_check(guard.is_physics_processing() and guard.enemy_runtime_state().state_id == "patrol", "action enables original enemy patrol state machine")
	await _wait(60)
	_check(world.object_by_id("demo_room/door").runtime_component.is_open(), "opened switch actually drives existing door")
	var graph_state: Dictionary = world.tl_capture()
	var player_state: Dictionary = agent.tl_capture()
	var deaths := []
	agent.killed.connect(func(reason: String): deaths.append(reason))
	actor.global_position = Vector3(3, 0.05, 3)
	await _wait(6)
	_check(agent.dead and not actor.visible and not actor.is_physics_processing() and actor.collision_layer == 0 and not agent.level_test_state("moving"), "kill action changes actual player state, visibility, processing and collision")
	_check(not world.runner.values.alive and deaths.size() == 1 and world.runner.counts.get("kill", 0) == 1, "death condition and execution trace reflect real result")
	agent.tl_restore(player_state)
	world.tl_restore(graph_state)
	await _wait(3)
	_check(not agent.dead and actor.visible and actor.is_physics_processing() and actor.collision_layer == 2 and deaths.size() == 1, "snapshot restore revives without repeating kill side effect")
	_check(world.runner.counts.get("begin", 0) == 1, "snapshot restore does not re-run game start")
	actor.travel = Vector3.LEFT
	await _wait(35)
	actor.travel = Vector3.RIGHT
	await _wait(35)
	actor.travel = Vector3.ZERO
	_check(agent.dead and deaths.size() == 2, "restored trigger becomes active after a real exit and reentry")
	var missing: GodotLevelEditorLevelGraph = world.events.duplicate(true)
	for n in missing.nodes:
		if n.kind == "room_enter": n.params.room = "missing_room"
	var previous: Resource = world.events
	world.events = missing
	_check(not world.validate().is_empty(), "missing Room reference is rejected")
	world.events = previous
	world.queue_free()
	await _wait(3)
	world = _make_world(false)
	actor = world.get_node("预览玩家")
	await _wait(4)
	actor.travel = Vector3.RIGHT
	await _wait(65)
	actor.travel = Vector3.ZERO
	_check(not world.runner.values.key and not world.object_by_id("demo_room/switch").runtime_component.is_powered(), "missing key takes false godot_level_editor and leaves switch closed")
	_check(world.runner.counts.get("no_key", 0) == 1 and world.runner.counts.get("open_switch", 0) == 0, "false output executes different connected behavior")
	world.queue_free()
	await _wait(3)
	world = _make_world(true, false)
	actor = world.get_node("预览玩家")
	await _wait(4)
	actor.travel = Vector3.RIGHT
	await _wait(65)
	actor.travel = Vector3.ZERO
	_check(world.runner.values.if_key and not world.object_by_id("demo_room/switch").runtime_component.is_powered(), "disconnecting wire changes actual switch behavior despite true condition")
	var no_agent: Node = actor.get_node("LevelAgent")
	no_agent.free()
	var result: Dictionary = world.actions.perform({"kind": "kill_player", "params": {}}, {"actor": str(actor.get_path())})
	_check(not result.ok and actor.visible and result.reason.contains("尚未接入"), "missing player bridge reports explicit failure and leaves actor intact")
	world.queue_free()
	await _wait(3)
func _budget_and_snapshot() -> void:
	var graph := G.new()
	graph.graph_id = "queued_events"
	graph.nodes = [{"id": "receive", "kind": "event_received", "params": {"key": "test", "once": false}}, {"id": "send", "kind": "emit_event", "params": {"key": "test"}}]
	graph.edges = [{"id": "deferred_feedback", "from": "receive", "from_port": "then", "to": "send", "to_port": "run"}]
	var runner := RUNNER.new()
	_check(runner.configure(graph, Callable()), "named-event feedback has explicit next-frame semantics")
	runner.queue_trigger("event_received", {"key": "test"})
	runner.tick()
	_check(runner.counts.get("receive", 0) == 1 and runner.incoming.size() == 1, "named event does not infinitely recurse in same frame")
	var state := runner.capture()
	runner.tick()
	runner.restore(state)
	_check(runner.incoming.size() == 1 and runner.counts.get("receive", 0) == 1, "snapshot preserves trigger queue and execution counters")
	for _i in 400: runner.queue_trigger("event_received", {"key": "test"})
	_check(runner.incoming.size() == 256, "trigger queue is bounded")
func _wait(frames: int) -> void:
	for _i in frames: await get_tree().physics_frame
func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)
