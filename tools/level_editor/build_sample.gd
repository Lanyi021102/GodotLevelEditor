extends Node
const FACTORY := preload("res://addons/godot_level_editor/scene_factory.gd")
const GRAPH := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
const WORLD := preload("res://addons/godot_level_editor/runtime/world.gd")

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	var definitions := [
		["atrium", "中庭", ["east", "north"]],
		["puzzle_1", "驻影之门", ["west", "north"]],
		["puzzle_2", "并行回声", ["south", "west"]],
		["puzzle_3", "多源协作房间", ["east", "south"]],
	]
	for i in definitions.size():
		var info: Array = definitions[i]
		var room: Node3D = FACTORY.room(info[0], info[1])
		# Extend only downward, preserving the original playable plane and ports.
		var floor: Node3D = room.object_by_id("floor")
		floor.size.y = 3.6
		floor.position.y = -1.8
		var sides: Array[String] = []
		sides.assign(info[2])
		FACTORY.boundary(room, sides)
		for side in sides:
			match side:
				"east": FACTORY.port(room, side, Vector3(10, 0, 0), -90)
				"west": FACTORY.port(room, side, Vector3(-10, 0, 0), 90)
				"north": FACTORY.port(room, side, Vector3(0, 0, -10), 0)
				"south": FACTORY.port(room, side, Vector3(0, 0, 10), 180)
		if i == 0:
			FACTORY.placement(room, "player_spawn", "placeholder", Vector3(-4, 0, 4))
			FACTORY.block(room, "central_cover", Vector3(3, 1.2, 3), Vector3(0, 0.6, 0))
		else:
			FACTORY.placement(room, "plate_a", "plate", Vector3(-5, 0.02, 4))
			var door: Node3D = FACTORY.placement(room, "door", "door", Vector3(0, 1.15, -4))
			door.source_ids = PackedStringArray(["plate_a"])
			if i >= 2:
				FACTORY.placement(room, "plate_b", "kinetic", Vector3(5, 0.02, 3))
				door.source_ids.append("plate_b")
				var guard: Node3D = FACTORY.placement(room, "guard", "guard", Vector3(0, 0.1, -1.3))
				if ResourceLoader.exists("res://resources/enemies/guard_default.tres"):
					guard.component_definition = load("res://resources/enemies/guard_default.tres")
				FACTORY.block(room, "cover_a", Vector3(2.6, 1.2, 1), Vector3(-5, 0.6, -1))
				FACTORY.block(room, "cover_b", Vector3(2.6, 1.2, 1), Vector3(5, 0.6, -1))
			if i == 3:
				FACTORY.placement(room, "breaker", "breaker", Vector3(-7, 0.02, -2.8))
				door.source_ids.append("breaker")
			for side in [-1.0, 1.0]:
				FACTORY.block(room, "partition_" + ("a" if side < 0 else "b"), Vector3(8.2, 2.6, 0.4), Vector3(side * 5.9, 1.3, -4))
			var region := FACTORY.REGION.new()
			region.name = "GoalRegion"
			region.object_id = "goal_region"
			region.position = Vector3(0, 0, -7.3)
			FACTORY.add_owned(room, region, room)
		_assert_ok(FACTORY.save_scene(room, "res://scenes/level_editor/rooms/%s.tscn" % info[0]))
		room.free()
	var topology := GRAPH.new()
	topology.graph_id = "godot_level_editor_topology_v1"
	topology.graph_kind = "topology"
	var pairs := [["atrium/east", "puzzle_1/west"], ["puzzle_1/north", "puzzle_2/south"], ["puzzle_2/west", "puzzle_3/east"], ["puzzle_3/south", "atrium/north"]]
	for i in pairs.size():
		for j in 2:
			var id := "port_%d_%d" % [i, j]
			topology.nodes.append({"id": id, "kind": "port", "label": pairs[i][j], "params": {"object": pairs[i][j]}})
			topology.positions[id] = Vector2(60 + j * 480, 40 + i * 160)
		topology.edges.append({"id": "link_%d" % i, "from": "port_%d_0" % i, "from_port": "space", "to": "port_%d_1" % i, "to_port": "space"})
	var events := GRAPH.new()
	events.graph_id = "godot_level_editor_events_v1"
	for i in 3:
		var suffix := str(i + 1)
		_node(events, "source_" + suffix, "source", {"object": "puzzle_%s/door" % suffix, "query": "open"}, Vector2(40, 40 + i * 240))
		_node(events, "goal_" + suffix, "goal", {"object": "puzzle_%s/goal_region" % suffix, "persistent": true}, Vector2(330, 40 + i * 240))
		_node(events, "latch_" + suffix, "latch", {"persistent": true}, Vector2(620, 40 + i * 240))
		_node(events, "unlock_" + suffix, "unlock", {"link": "link_" + suffix}, Vector2(910, 40 + i * 240))
		_node(events, "checkpoint_" + suffix, "checkpoint", {}, Vector2(620, 150 + i * 240))
		_edge(events, "source_" + suffix, "value", "goal_" + suffix, "condition")
		_edge(events, "goal_" + suffix, "completed", "latch_" + suffix, "set")
		_edge(events, "latch_" + suffix, "value", "unlock_" + suffix, "enabled")
		_edge(events, "goal_" + suffix, "completed", "checkpoint_" + suffix, "run")
	_node(events, "objective_final", "objective", {"text": "捷径已开启，返回中庭"}, Vector2(930, 700))
	_edge(events, "goal_3", "completed", "objective_final", "run")
	_assert_ok(ResourceSaver.save(topology, "res://resources/level_editor/world_topology.tres"))
	_assert_ok(ResourceSaver.save(events, "res://resources/level_editor/world_events.tres"))
	var world := WORLD.new()
	world.name = "GodotLevelEditorWorld"
	world.topology = load("res://resources/level_editor/world_topology.tres")
	world.events = load("res://resources/level_editor/world_events.tres")
	var positions := [Vector3.ZERO, Vector3(20, 0, 0), Vector3(20, 0, -20), Vector3(0, 0, -20)]
	for i in definitions.size():
		var instance: Node3D = load("res://scenes/level_editor/rooms/%s.tscn" % definitions[i][0]).instantiate()
		instance.position = positions[i]
		FACTORY.add_owned(world, instance, world)
	var camera := Camera3D.new()
	camera.name = "OverviewCamera"
	camera.position = Vector3(52, 54, 44)
	camera.look_at_from_position(camera.position, Vector3(10, 0, -10))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 66
	camera.current = true
	FACTORY.add_owned(world, camera, world)
	var lighting := preload("res://scenes/lighting/sunlit_miniature_v2.tscn").instantiate()
	lighting.name = "Lighting"
	FACTORY.add_owned(world, lighting, world)
	var errors := world.validate()
	if not errors.is_empty():
		push_error(str(errors))
		get_tree().quit(1)
		world.free()
		return
	_assert_ok(FACTORY.save_scene(world, "res://scenes/levels/continuous_world.tscn"))
	world.free()
	print("LEVEL SAMPLE: 4 room scenes + 2 graphs + continuous world saved")
	get_tree().quit()

func _node(graph: GodotLevelEditorLevelGraph, id: String, kind: String, params: Dictionary, at: Vector2) -> void:
	graph.nodes.append({"id": id, "kind": kind, "label": GRAPH.LABELS[kind], "params": params})
	graph.positions[id] = at

func _edge(graph: GodotLevelEditorLevelGraph, a: String, ap: String, b: String, bp: String) -> void:
	graph.edges.append({"id": "edge_%s_%s" % [a, b], "from": a, "from_port": ap, "to": b, "to_port": bp})

func _assert_ok(err: Error) -> void:
	assert(err == OK, error_string(err))
