extends Node
const FACTORY := preload("res://addons/godot_level_editor_mechanisms/factory.gd")
const ASSEMBLY := preload("res://addons/godot_level_editor_mechanisms/runtime/assembly.gd")
const DEFINITION := preload("res://addons/godot_level_editor_mechanisms/graph/definition.gd")
const STORE := preload("res://addons/godot_level_editor_mechanisms/store.gd")
const SCHEMA := preload("res://addons/godot_level_editor_mechanisms/graph/schema.gd")
const LEVEL_FACTORY := preload("res://addons/godot_level_editor/scene_factory.gd")
const TASK := preload("res://addons/godot_level_editor_narrative/runtime/task_definition.gd")
var failed := false

func _ready() -> void:
	for kind in SCHEMA.COMPONENT_KINDS:
		var root := assembly(kind, str(FACTORY.Stateful.TITLES[kind]))
		add_component(root, kind, kind, Vector3.ZERO)
		root.primary_component = NodePath(str(root.get_child(0).name))
		save(root, "res://scenes/mechanisms/" + kind + ".tscn")
	generate_combinations()
	generate_tasks()
	generate_level()
	get_tree().quit(1 if failed else 0)

func assembly(id: String, title: String) -> Node3D:
	var root := ASSEMBLY.new(); root.name = id.to_pascal_case(); root.instance_id = "wb_v1_" + id; root.object_id = id
	var graph := DEFINITION.new(); graph.definition_id = "wb_v1_" + id; graph.display_name = title; root.definition = graph
	return root

func add_node(root: Node, id: String, kind: String, params: Dictionary, at: Vector2) -> void:
	root.definition.nodes.append({"id": id, "kind": kind, "label": SCHEMA.KINDS[kind].title, "params": params}); root.definition.positions[id] = at

func add_component(root: Node, kind: String, id: String, at: Vector3) -> Node3D:
	var component := FACTORY.component(kind, id); component.name = id.to_pascal_case(); component.position = at
	root.add_child(component); component.owner = root
	add_node(root, id + "_component", kind, {"object_id": id}, Vector2(40, 60 + (root.get_child_count() - 1) * 180))
	return component

func edge(root: Node, from: String, output: String, to: String, input: String) -> void:
	root.definition.edges.append({"from": from, "out": output, "to": to, "in": input})

func save(root: Node, path: String) -> void:
	if FileAccess.file_exists(path): print("保留已存在素材：", path); root.free(); return
	var result := STORE.save_pair(root, path)
	if not result.ok: push_error(str(result.errors)); failed = true
	else: print("生成 ", path)
	root.free()

func generate_combinations() -> void:
	var root := assembly("button_door", "按钮打开滑动门")
	add_component(root, "button", "button", Vector3(-1.6, 0, 2))
	add_component(root, "sliding_door", "door", Vector3(1.2, 0, 0)).interaction_enabled = false
	root.primary_component = NodePath("Door")
	add_node(root, "pressed", "state_entered", {"object_id": "button", "state": "pressed"}, Vector2(360, 60))
	add_node(root, "open", "perform_action", {"object_id": "door", "action": "open"}, Vector2(720, 60)); edge(root, "pressed", "fired", "open", "trigger")
	save(root, "res://scenes/mechanisms/button_door.tscn")
	root = assembly("dual_plate_door", "双压力板控制门")
	add_component(root, "pressure_plate", "plate_a", Vector3(-1.7, 0, 2.1)); add_component(root, "pressure_plate", "plate_b", Vector3(1.7, 0, 2.1))
	add_component(root, "hinged_door", "door", Vector3(0, 0, -1)).interaction_enabled = false
	root.primary_component = NodePath("Door")
	add_node(root, "both", "and", {}, Vector2(380, 70)); edge(root, "plate_a_component", "value", "both", "a"); edge(root, "plate_b_component", "value", "both", "b")
	add_node(root, "pressed", "rising", {}, Vector2(700, 20)); edge(root, "both", "value", "pressed", "value")
	add_node(root, "not_both", "not", {}, Vector2(380, 300)); edge(root, "both", "value", "not_both", "value")
	add_node(root, "released", "rising", {}, Vector2(700, 300)); edge(root, "not_both", "value", "released", "value")
	add_node(root, "open", "perform_action", {"object_id": "door", "action": "open"}, Vector2(1000, 20)); edge(root, "pressed", "fired", "open", "trigger")
	add_node(root, "close", "perform_action", {"object_id": "door", "action": "close"}, Vector2(1000, 300)); edge(root, "released", "fired", "close", "trigger")
	save(root, "res://scenes/mechanisms/dual_plate_door.tscn")
	root = assembly("terminal_lift", "终端启动升降台")
	add_component(root, "terminal", "terminal", Vector3(-2, 0, 1.5)).initial_state = "ready"
	add_component(root, "lift_platform", "lift", Vector3(1, 0, 0)).interaction_enabled = false
	root.primary_component = NodePath("Lift")
	add_node(root, "activated", "state_entered", {"object_id": "terminal", "state": "activated"}, Vector2(380, 60))
	add_node(root, "move", "perform_action", {"object_id": "lift", "action": "move_to_end"}, Vector2(720, 60)); edge(root, "activated", "fired", "move", "trigger")
	save(root, "res://scenes/mechanisms/terminal_lift.tscn")

func generate_tasks() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/mechanisms/whitebox_v1")
	for id in ["button_door", "dual_plate_door", "terminal_lift"]:
		var path: String = "res://resources/mechanisms/whitebox_v1/" + id + ".task.tres"
		if FileAccess.file_exists(path): continue
		var graph := TASK.new(); graph.graph_id = "wb_v1_task_" + id
		var target: String = "$world/" + id + "::" + ("lift" if id == "terminal_lift" else "door")
		graph.nodes.assign([
			{"id": "start", "kind": "start", "label": "任务开始", "params": {}},
			{"id": "wait", "kind": "wait_mechanism_state", "label": "等待实际到位", "params": {"mechanism": target, "state": "at_end" if id == "terminal_lift" else "open", "timeout": 0.0, "scope": ""}},
			{"id": "complete", "kind": "task_complete", "label": "目标完成", "params": {"task": "demo_" + id}}
		])
		graph.edges.assign([
			{"id": "a", "from": "start", "from_port": "then", "to": "wait", "to_port": "run"},
			{"id": "b", "from": "wait", "from_port": "then", "to": "complete", "to_port": "run"}
		])
		graph.positions = {"start": Vector2(40, 90), "wait": Vector2(380, 90), "complete": Vector2(780, 90)}
		if not graph.validate().is_empty() or ResourceSaver.save(graph, path) != OK: failed = true; push_error(str(graph.validate()))

func generate_level() -> void:
	var path := "res://scenes/levels/mechanism_whitebox_v1.tscn"
	if FileAccess.file_exists(path): return
	var world := preload("res://addons/godot_level_editor/runtime/world.gd").new(); world.name = "MechanismWhiteboxV1"; world.world_id = "mechanism_whitebox_v1"
	world.topology = preload("res://addons/godot_level_editor/runtime/level_graph.gd").new(); world.topology.graph_id = "mechanism_whitebox_topology"; world.topology.graph_kind = "topology"
	world.events = preload("res://addons/godot_level_editor/runtime/level_graph.gd").new(); world.events.graph_id = "mechanism_whitebox_events"
	LEVEL_FACTORY.block(world, "floor", Vector3(34, 0.6, 20), Vector3(0, -0.3, 0))
	var lighting: Node = load("res://scenes/lighting/sunlit_miniature_v2.tscn").instantiate(); lighting.name = "Lighting"; LEVEL_FACTORY.add_owned(world, lighting, world)
	var spawn := preload("res://addons/godot_level_editor/runtime/spawn_marker.gd").new(); spawn.name = "PlayerSpawn"; spawn.object_id = "player_spawn"; spawn.position = Vector3(0, 0.12, 7); LEVEL_FACTORY.add_owned(world, spawn, world)
	var index := 0
	for id in ["button_door", "dual_plate_door", "terminal_lift"]:
		var sample: Node3D = load("res://scenes/mechanisms/" + id + ".tscn").instantiate(); sample.position.x = (index - 1) * 10.0; sample.object_id = id; sample.instance_id = "demo_" + id
		LEVEL_FACTORY.add_owned(world, sample, world); index += 1
	var weight := preload("res://tools/mechanisms/whitebox_v1/demo_weight.gd").new(); weight.name = "Weight"; weight.position = Vector3(-2, 0.65, 4.5); LEVEL_FACTORY.add_owned(world, weight, world)
	var controller := preload("res://tools/mechanisms/whitebox_v1/demo_controller.gd").new(); controller.name = "ExampleObjectives"; LEVEL_FACTORY.add_owned(world, controller, world)
	if LEVEL_FACTORY.save_scene(world, path) != OK: failed = true
	world.free()
