extends Node
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const ROOM := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/room.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const LOGIC := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_logic_graph.gd")
const TASK := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const DIRECTOR := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_director.gd")
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const BINDING := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_binding.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)

func physics(count := 15) -> void:
	for i in count: await get_tree().physics_frame

func body(name_value: String, player: bool) -> CharacterBody3D:
	var node := CharacterBody3D.new(); node.name = name_value; node.collision_layer = 2; node.collision_mask = 0
	if player: node.add_to_group("godot_level_editor_player")
	var shape := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius = 0.12; capsule.height = 0.5; shape.shape = capsule; node.add_child(shape)
	node.position = Vector3(-5, 0.5, 0); add_child(node)
	return node

func configured_room(id: String, task_id := "") -> Node3D:
	var node: Node3D = preload("res://addons/godot_level_editor/scenes/level_editor/rooms/trigger_room.tscn").instantiate(); node.name = id; node.room_id = id
	var profile := PROFILE.new(); profile.kind = "room"; profile.model_id = "default"; profile.lifetime = "level" if task_id.is_empty() else "task"; profile.task_id = task_id
	node.set_meta(PROFILE.META, profile)
	var binding := BINDING.new(); binding.name = PROFILE.BINDING; node.add_child(binding)
	return node

func flow(graph: Resource, room_id: String) -> void:
	graph.graph_id = "trigger_" + room_id
	graph.nodes.assign([
		{"id":"enter","kind":"room_enter","params":{"room":room_id,"once":false}},
		{"id":"exit","kind":"room_exit","params":{"room":room_id,"once":false}},
		{"id":"active","kind":"room_active","params":{"room":room_id,"expected":true}},
		{"id":"inactive","kind":"room_active","params":{"room":room_id,"expected":false}},
		{"id":"entered","kind":"set_variable","params":{"key":"entered","type":"bool","bool_value":true,"number_value":0.0}},
		{"id":"exited","kind":"set_variable","params":{"key":"exited","type":"bool","bool_value":true,"number_value":0.0}},
	])
	graph.edges.assign([
		{"id":"a","from":"enter","from_port":"then","to":"entered","to_port":"run"},
		{"id":"b","from":"exit","from_port":"then","to":"exited","to_port":"run"},
	])

func _ready() -> void:
	get_tree().create_timer(35, true).timeout.connect(func(): get_tree().quit(2))
	var source_hash := FileAccess.get_sha256("res://content/scenes/level_editor/rooms/new_room.tscn")
	var world := WORLD.new(); world.name = "World"; world.world_id = "trigger_room_test"; world.level_id = "1"; world.start_room_id = ""
	world.topology = GRAPH.new(); world.topology.graph_kind = "topology"; world.topology.graph_id = "room_topology"
	world.events = GRAPH.new(); world.events.graph_kind = "events"; world.events.graph_id = "room_events"
	world.level_logic = LOGIC.new(); flow(world.level_logic, "level_room")
	check(world.level_logic.validate().is_empty(), "permanent graph accepts Room activation and exit nodes")
	var catalog := CATALOG.new(); var event := catalog.add_event(); var task := catalog.add_task(event.event_id, "1")
	var task_graph := TASK.new(); flow(task_graph, "task_room")
	task_graph.nodes.append({"id":"finish","kind":"event_received","params":{"key":"finish"}})
	task_graph.nodes.append({"id":"complete","kind":"task_complete","params":{"task":str(task.task_id)}})
	task_graph.edges.append({"id":"finish_task","from":"finish","from_port":"then","to":"complete","to_port":"run"})
	check(task_graph.validate().is_empty(), "task graph accepts the same Room state nodes")
	var task_path := "res://tools/level_editor/room_trigger_%d.tres" % OS.get_process_id()
	check(ResourceSaver.save(task_graph, task_path) == OK, "isolated task graph saves")
	task.graph_path = task_path
	var workbook := "user://room_triggers_%d.xlsx" % OS.get_process_id()
	check(catalog.save_book(workbook).is_empty(), "isolated workbook binds the test task to this level")
	var level_room := configured_room("level_room"); var task_room := configured_room("task_room", task.task_id); task_room.position.x = 3
	world.add_child(level_room); world.add_child(task_room); add_child(world)
	var player := body("Player", true); var other := body("Other", false); var second := body("SecondPlayer", true)
	var director := DIRECTOR.new(); director.name = "Tasks"; director.world_path = "../World"; director.workbook = workbook; add_child(director)
	await physics()
	check(level_room.bounds_size == Vector3.ONE and task_room.bounds_size == Vector3.ONE, "both new Room scopes default to a 1x1x1 cube")
	check(level_room._region.get_node("Shape").shape.size == Vector3.ONE, "the detection shape uses the same dimensions")
	check(level_room._region.collision_layer == 0 and level_room._region.collision_mask == 2, "Room is a player sensor rather than a solid collision wall")
	check(not level_room.has_node("Floor") and not level_room.has_node("RoomPreview"), "runtime Room has no architecture or visible trigger mesh")
	check(not level_room.is_active() and not task_room.is_active(), "empty Rooms start inactive")
	check(director.valid and director.level_runner != null, "real director runs the permanent Room graph")
	check(not task_room.visible and not task_room._region.monitoring, "task Room detection is disabled before its task starts")
	other.position = Vector3(0, 0.5, 0); await physics()
	check(not level_room.is_active(), "non-player bodies do not activate a Room")
	player.position = Vector3(0, 0.5, 0); await physics()
	check(level_room.is_active(), "real player entry activates the Room")
	check(director.level_variables.get("entered", false), "entry triggers a real effect in the permanent graph")
	check(director.level_runner.values.get("active", false) and not director.level_runner.values.get("inactive", true), "permanent graph reads the live activation state")
	second.position = Vector3(0.2, 0.5, 0); await physics()
	player.position = Vector3(-5, 0.5, 0); await physics()
	check(level_room.is_active(), "Room stays active while another player remains inside")
	second.position = Vector3(-5, 0.5, 0); await physics()
	check(not level_room.is_active(), "leaving with the final player restores inactive state")
	check(director.level_variables.get("exited", false), "exit triggers its own permanent graph effect")
	check(not director.level_runner.values.get("active", true) and director.level_runner.values.get("inactive", false), "the graph state resets after exit")
	level_room.keep_active_on_exit = true
	player.position = Vector3(0, 0.5, 0); await physics(); player.position = Vector3(-5, 0.5, 0); await physics()
	check(level_room.is_active(), "the optional keep-active rule retains activation after exit")
	level_room.set_detection_enabled(false)
	check(not level_room.is_active(), "disabling detection also clears a latched activation")
	level_room.set_detection_enabled(true)
	player.position = Vector3(3, 0.5, 0); await physics()
	check(not task_room.is_active(), "an unstarted task Room ignores players already inside")
	check(director.start_event(event.event_id), "the real task starts successfully")
	await physics(25)
	var runner: RefCounted = director.active[event.event_id].runner
	check(task_room.visible and task_room._region.monitoring and task_room.is_active(), "task activation detects a player already standing inside")
	check(runner.variables.get("entered", false), "task Room entry triggers the current task graph effect")
	check(runner.values.get("active", false), "task graph reads activation through the same condition node")
	player.position = Vector3(-5, 0.5, 0); await physics()
	check(not task_room.is_active() and runner.variables.get("exited", false), "task Room exit updates state and task effects")
	player.position = Vector3(3, 0.5, 0); await physics()
	check(task_room.is_active(), "task Room can activate again on re-entry")
	director.publish_event("finish"); await physics()
	check(not task_room.is_active() and not task_room._region.monitoring and not task_room.visible, "task completion clears an occupied Room activation and disables detection")
	var unknown := TASK.new(); flow(unknown, "missing")
	check(not preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_bindings.gd").validate(world, unknown).is_empty(), "missing Room state references fail validation")
	var wrong_task := TASK.new(); flow(wrong_task, "task_room")
	check(not preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_bindings.gd").validate(world, wrong_task, "other_task").is_empty(), "Room state nodes reject another task's exclusive Room")
	var legacy := ROOM.new()
	check(legacy.bounds_size == Vector3(20, 4, 20), "legacy implicit scene dimensions retain their original default")
	legacy.free()
	check(FileAccess.get_sha256("res://content/scenes/level_editor/rooms/new_room.tscn") == source_hash, "existing authored room files remain unchanged")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(workbook)); DirAccess.remove_absolute(ProjectSettings.globalize_path(task_path))
	print("ROOM TRIGGERS: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
