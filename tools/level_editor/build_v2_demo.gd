extends Node
const F := preload("res://addons/godot_level_editor/scene_factory.gd")
const G := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
func _ready() -> void:
	var world := preload("res://addons/godot_level_editor/runtime/world.gd").new()
	world.name = "关卡节点示例"
	world.world_id = "level_nodes_demo"
	world.start_room_id = "demo_room"
	var room := F.room("demo_room", "教学 Room")
	room.name = "教学Room"
	room.bounds_size = Vector3(10, 4, 10)
	F.add_owned(world, room, world)
	# Existing room children belong to the room and must also be owned by the saved world.
	for child in room.get_children():
		child.owner = world
		if child.get("object_id") == "floor": child.name = "地板"
	var lever := F.placement(room, "switch", "lever", Vector3(-2, 0, 0))
	lever.name = "开关"
	lever.owner = world
	var door := F.placement(room, "door", "door", Vector3(0, 1.15, -3.5))
	door.source_ids = PackedStringArray(["switch"])
	door.name = "门"
	door.owner = world
	var guard := F.placement(room, "guard", "guard", Vector3(2.5, 0.05, -1))
	guard.initially_active = false
	guard.patrol_local = PackedVector3Array([Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0)])
	guard.component_definition = load("res://resources/enemies/guard_default.tres")
	guard.name = "敌人"
	guard.owner = world
	var region := F.REGION.new()
	region.name = "危险触发区"
	region.object_id = "danger"
	region.position = Vector3(3, 0, 3)
	region.extent = Vector3(1.5, 2, 1.5)
	region.tint = Color("cb715d")
	F.add_owned(room, region, world)
	var topology := G.new()
	topology.graph_kind = "topology"
	topology.graph_id = "demo_topology"
	var graph := G.new()
	graph.graph_id = "demo_events"
	_node(graph, "begin", "start", {}, Vector2(20, 20))
	_node(graph, "send", "emit_event", {"key": "教学开始"}, Vector2(300, 20))
	_node(graph, "received", "event_received", {"key": "教学开始", "once": true}, Vector2(20, 180))
	_node(graph, "intro", "objective", {"text": "示例会检查玩家是否持有样例钥匙。进入蓝框 Room 触发判断；红区触发击杀。"}, Vector2(300, 180))
	_node(graph, "enter", "room_enter", {"room": "demo_room", "once": false}, Vector2(20, 380))
	_node(graph, "key", "has_item", {"key": "sample_key"}, Vector2(20, 570))
	_node(graph, "if_key", "branch", {}, Vector2(330, 380))
	_node(graph, "open_switch", "set_switch", {"object": "demo_room/switch", "enabled": true}, Vector2(650, 350))
	_node(graph, "patrol", "enemy_patrol", {"object": "demo_room/guard"}, Vector2(970, 350))
	_node(graph, "success", "objective", {"text": "有钥匙：开关已开启，敌人开始巡逻，门会升起。红区可以测试击杀与玩家状态。"}, Vector2(1280, 350))
	_node(graph, "no_key", "objective", {"text": "没有样例钥匙，开关保持关闭。"}, Vector2(650, 560))
	_node(graph, "danger", "region_enter", {"object": "demo_room/danger", "once": false}, Vector2(20, 800))
	_node(graph, "kill", "kill_player", {"reason": "进入危险触发区"}, Vector2(360, 800))
	_node(graph, "dead", "objective", {"text": "玩家已被击杀。按 R 重新开始；编辑器可查看节点执行原因。"}, Vector2(680, 800))
	_node(graph, "alive", "player_state", {"state": "alive"}, Vector2(20, 1010))
	_edge(graph, "begin", "then", "send", "run")
	_edge(graph, "received", "then", "intro", "run")
	_edge(graph, "enter", "then", "if_key", "run")
	_edge(graph, "key", "value", "if_key", "condition")
	_edge(graph, "if_key", "yes", "open_switch", "run")
	_edge(graph, "if_key", "no", "no_key", "run")
	_edge(graph, "open_switch", "then", "patrol", "run")
	_edge(graph, "patrol", "then", "success", "run")
	_edge(graph, "danger", "then", "kill", "run")
	_edge(graph, "kill", "then", "dead", "run")
	ResourceSaver.save(topology, "res://resources/level_editor/demo_topology.tres")
	ResourceSaver.save(graph, "res://resources/level_editor/demo_events.tres")
	world.topology = load("res://resources/level_editor/demo_topology.tres")
	world.events = load("res://resources/level_editor/demo_events.tres")
	var actor := CharacterBody3D.new()
	actor.name = "预览玩家"
	actor.set_script(preload("res://tools/level_editor/demo_actor.gd"))
	actor.position = Vector3(-7, 0.05, 3)
	actor.collision_layer = 2
	actor.collision_mask = 1
	F.add_owned(world, actor, world)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	capsule.radius = 0.25
	shape.shape = capsule
	shape.position.y = 0.8
	F.add_owned(actor, shape, world)
	var visual := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.height = 1.6
	mesh.radius = 0.25
	visual.mesh = mesh
	visual.position.y = 0.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("70d7e9")
	visual.material_override = material
	F.add_owned(actor, visual, world)
	var agent := preload("res://addons/godot_level_editor/runtime/actor_agent.gd").new()
	agent.name = "LevelAgent"
	agent.unlocked_items = PackedStringArray(["sample_key"])
	F.add_owned(actor, agent, world)
	var camera := Camera3D.new()
	camera.position = Vector3(12, 15, 16)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25
	camera.current = true
	F.add_owned(world, camera, world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, -20, 0)
	F.add_owned(world, light, world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("152436")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b2c2d4")
	environment.environment.ambient_light_energy = 0.6
	F.add_owned(world, environment, world)
	var hud := CanvasLayer.new()
	hud.set_script(preload("res://tools/level_editor/demo_hud.gd"))
	F.add_owned(world, hud, world)
	var errors := world.validate()
	if not errors.is_empty(): push_error(str(errors)); world.free(); get_tree().quit(1); return
	var result := F.save_scene(world, "res://scenes/levels/logic_playground.tscn")
	world.free()
	print("V2 DEMO: ", error_string(result))
	get_tree().quit(0 if result == OK else 1)
func _node(graph: GodotLevelEditorLevelGraph, id: String, kind: String, params: Dictionary, position_value: Vector2) -> void:
	graph.nodes.append({"id": id, "kind": kind, "label": G.LABELS[kind], "params": params})
	graph.positions[id] = position_value
func _edge(graph: GodotLevelEditorLevelGraph, a: String, ap: String, b: String, bp: String) -> void:
	graph.edges.append({"id": "edge_" + a + "_" + b, "from": a, "from_port": ap, "to": b, "to_port": bp})
