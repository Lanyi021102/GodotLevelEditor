extends Node
const STORE := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd")
const GENERATE := preload("res://tools/mechanisms/doors_v2/generate.gd")
const ACCESS := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/state_access.gd")
var checks := 0
var failures := 0
var actor: CharacterBody3D

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", title)
func quiet(node: Node) -> void:
	node.set_physics_process(false)
	if node is AnimatableBody3D: node.sync_to_physics = false
	for child in node.get_children(): quiet(child)

func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(2))
	actor = CharacterBody3D.new(); actor.add_to_group("godot_level_editor_player"); actor.position = Vector3(0, 1, 1); add_child(actor)
	for kind in ["single_door", "double_door"]:
		var root := STORE.load_pair("res://addons/godot_level_editor/scenes/mechanisms/" + str(kind) + ".tscn")
		check(root != null, str(kind) + " paired asset loads")
		if root == null: continue
		add_child(root); quiet(root)
		var door: Node = root.bindings.door
		check(STORE.validate(root).is_empty() and door.state_names() == ["close", "moving", "open"], str(kind) + " exposes exactly the agreed three states")
		check(door.door_dimensions() == Vector2(2 if kind == "single_door" else 4, 3) and door._leaves.size() == (1 if kind == "single_door" else 2), str(kind) + " has the requested outer size and leaf count")
		check(door.has_node("DoorGeometry/DoorFrame/LeftPost") and door.has_node("DoorGeometry/DoorFrame/Lintel") and door._leaves[0].has_node("LeafCollision"), str(kind) + " separates fixed frame and real colliding hinged leaves")
		var frame: Node3D = door.get_node("DoorGeometry/DoorFrame")
		var fixed_transform := frame.global_transform
		var bounds := AABB(); var first := true
		for mesh in frame.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			bounds = box if first else bounds.merge(box); first = false
		check(is_equal_approx(bounds.size.x, 2 if kind == "single_door" else 4) and is_equal_approx(bounds.size.y, 3), str(kind) + " actual frame mesh bounds measure the requested width and height")
		root.step()
		check(root.values["close:value"] and not root.values["moving:value"] and not root.values["open:value"], str(kind) + " graph initially displays close only")
		var events: Array = []; var finished: Array = []
		door.state_changed.connect(func(old: String, state: String): events.append([old, state]))
		door.action_finished.connect(func(action: String, ok: bool): finished.append([action, ok]))
		check(door.interact(actor) and door.get_state() == "close", str(kind) + " interaction is routed through the visible animation connection")
		root.step(); door.advance(door.motion_seconds * 0.25); root.step()
		check(door.get_state() == "moving" and root.values["moving:value"] and events == [["close", "moving"]], str(kind) + " animation activates moving instead of prematurely claiming open")
		check(is_equal_approx(door.angle_degrees(), 14.0625) and finished.is_empty(), str(kind) + " 25% time follows the ease curve rather than linear rotation")
		check(is_equal_approx(rad_to_deg(door._leaves[0].rotation.y), door.angle_degrees()), str(kind) + " visible and collision leaf use the same curve angle")
		var saved: Dictionary = root.tl_capture()
		door.advance(door.motion_seconds); root.step()
		check(door.get_state() == "open" and is_equal_approx(door.angle_degrees(), 90) and root.values["open:value"] and finished == [["toggle", true]], str(kind) + " reaches exactly 90 degrees before reporting completion and open")
		check(frame.global_transform.is_equal_approx(fixed_transform), str(kind) + " outer frame remains fixed while the leaf animates")
		if door.leaf_count() == 2: check(is_equal_approx(rad_to_deg(door._leaves[1].rotation.y), -90), "double door leaves rotate in opposite directions")
		var event_frame: int = root.last_events.open.frame; root.step()
		check(root.last_events.open.frame == event_frame, str(kind) + " entered-state event does not repeat each frame")
		var count := events.size(); root.tl_restore(saved)
		check(events.size() == count and door.get_state() == "moving" and is_equal_approx(door.progress, 0.25), str(kind) + " snapshot restores curve progress silently")
		check(door.perform_action("close").ok and finished.back() == ["toggle", false], str(kind) + " reversing cancels the previous motion explicitly")
		var angle: float = door.angle_degrees(); door.advance(door.motion_seconds * 0.10)
		check(door.angle_degrees() < angle and door.angle_degrees() > 0, str(kind) + " closing plays the same curve backward without a pose jump")
		door.advance(door.motion_seconds); root.step()
		check(door.get_state() == "close" and door.angle_degrees() == 0 and root.values["close:value"], str(kind) + " closes physically and reactivates close")
		door.locked = true
		check(not door.interact(actor) and not door.request_state("open").ok and not door.request_state("moving").ok and not door.perform_action("repair").ok, str(kind) + " rejects locked, transition-state and unsupported requests cleanly")
		var graph: Resource = root.definition.duplicate(true); graph.find_node("leaf").params.object_id = "another_door"
		check(str(graph.validate(root.bindings, true)).contains("门的结构连线"), str(kind) + " rejects a structural chain that refers to different physical doors")
		door.motion_curve = null
		var rejected := "res://tools/mechanisms/doors_v2/rejected_%d.tscn" % OS.get_process_id()
		check(not STORE.save_pair(root, rejected).ok and not FileAccess.file_exists(rejected) and not FileAccess.file_exists(rejected.get_basename() + ".graph.tres"), str(kind) + " refuses a missing animation curve before writing either paired file")
		root.free()
	await collision_test()
	task_test()
	print("ROTATING DOORS RUNTIME: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func collision_test() -> void:
	var root := GENERATE.fixture("double_door"); add_child(root)
	var door: Node = root.bindings.door; door.motion_seconds = 0.12
	for i in 3: await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0.6, 1.5, 3), Vector3(0.6, 1.5, -3), 1)
	check(not door.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "closed double door blocks a real physics ray through its opening")
	door.perform_action("open")
	for i in 20: await get_tree().physics_frame
	check(door.get_state() == "open" and door.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "opened double door clears the passage with physical collision following the rotation")
	root.free()

func task_test() -> void:
	var world := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd").new()
	world.topology = preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd").new(); world.topology.graph_kind = "topology"; world.topology.graph_id = "door_test_topology"
	world.events = preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd").new(); world.events.graph_id = "door_test_events"; add_child(world)
	var root := GENERATE.fixture("single_door"); root.object_id = "door_a"; world.add_child(root); quiet(root)
	var target := "$world/door_a::door"
	check(ACCESS.resolve(world, target) == root.bindings.door and ACCESS.descriptions(world).any(func(item: Dictionary): return item.reference == target and item.states == ["close", "moving", "open"]), "task target lookup exposes the new door's actual three states")
	var actions := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_actions.gd").new(); actions.world = world
	var request := {"id": "open", "kind": "mechanism_request_state", "params": {"mechanism": target, "state": "open"}}
	check(preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_nodes.gd").validate_bindings(world, request).is_empty() and actions.perform(request, {}).ok and root.bindings.door.get_state() == "moving", "task request starts the same curve animation through the shared state interface")
	root.bindings.door.advance(2)
	check(actions.condition({"kind": "mechanism_state", "params": {"mechanism": target, "state": "open"}}), "task state condition observes the real final open state")
	world.free()
