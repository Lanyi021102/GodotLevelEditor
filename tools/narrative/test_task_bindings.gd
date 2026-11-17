extends Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	get_tree().create_timer(25, true).timeout.connect(func(): get_tree().quit(2))
	var session: Node = load("res://tools/narrative/session_fixture.tscn").instantiate()
	var director: Node = session.get_node("Narrative/Tasks")
	director.automatic_starts = false
	add_child(session)
	for i in 15: await get_tree().physics_frame
	var bindings := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_bindings.gd")
	var task := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd").new()
	task.graph_id = "qa06"
	task.nodes = [{"id": "talk", "kind": "npc_interact", "params": {"npc": "qa_missing_npc", "task": "1001001"}}, {"id": "end", "kind": "task_complete", "params": {"task": "1001001"}}]
	task.edges = [{"id": "edge", "from": "talk", "from_port": "then", "to": "end", "to_port": "run"}]
	check(task.validate().is_empty(), "dangling entity remains a schema-valid graph for contextual validation")
	check(not bindings.validate(session.world, task).is_empty(), "missing NPC is rejected in the current world")
	check(bindings.validate(session.world, task, "1001001", "1").is_empty(), "a different level is deferred rather than falsely rejected")
	var npc: Node = load("res://addons/godot_level_editor/scenes/narrative/npc.tscn").instantiate()
	npc.object_id = "qa_missing_npc"
	session.world.add_child(npc)
	var profile := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd").new()
	profile.lifetime = "task"; profile.task_id = "1001001"
	npc.set_meta(profile.META, profile)
	npc.visible = false
	check(bindings.validate(session.world, task, "1001001").is_empty(), "authored task NPC is valid before it becomes visible")
	check(not bindings.validate(session.world, task, "1001002").is_empty(), "NPC assigned to another task is rejected")
	var catalog := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd").new()
	var event := catalog.add_event()
	var item := catalog.add_task(event.event_id, "2")
	var path := "user://qa06_%d.tres" % OS.get_process_id()
	ResourceSaver.save(task, path); item.graph_path = path
	director.catalog = catalog
	npc.get_parent().remove_child(npc)
	check(not director.start_event(event.event_id), "activation rejects a deleted NPC before marking its task active")
	check(director.active.is_empty() and director.task_states.is_empty() and not director.task_binding_errors.is_empty(), "invalid graph creates no stalled active task and exposes the cause")
	check(director.objective_label.visible and director.objective_label.failure.text.contains("NPC 不存在"), "rejected mission displays a visible actionable HUD error")
	session.world.add_child(npc)
	check(director.start_event(event.event_id), "valid authored task NPC can activate normally")
	for i in 3: await get_tree().physics_frame
	check(director.active[event.event_id].runner != null, "valid task receives its runner")
	var room_graph: Resource = task.duplicate(true)
	room_graph.nodes.assign([{"id": "room", "kind": "room_enter", "params": {"room": "missing_room"}}])
	room_graph.edges.clear()
	check(not bindings.validate(session.world, room_graph).is_empty(), "missing Room is rejected by the same contextual service")
	DirAccess.remove_absolute(path)
	session.queue_free()
	for i in 3: await get_tree().process_frame
	print("QA06 TASK BINDINGS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
