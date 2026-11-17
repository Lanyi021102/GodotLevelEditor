extends Node
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const BINDING := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_binding.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const TASK := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")
const DIRECTOR := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_director.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)

func physics(count := 12) -> void:
	for i in count: await get_tree().physics_frame

func attach(node: Node3D, kind: String, lifetime: String, task_id := "") -> Resource:
	var profile := PROFILE.new(); profile.kind = kind; profile.lifetime = lifetime; profile.task_id = task_id
	profile.model_id = "capsule" if kind == "npc" else "default"
	node.set_meta(PROFILE.META, profile)
	var binding := BINDING.new(); binding.name = PROFILE.BINDING; node.add_child(binding)
	return profile

func npc(id: String, lifetime: String, task_id := "") -> Node3D:
	var node: Node3D = preload("res://addons/godot_level_editor/scenes/narrative/npc.tscn").instantiate(); node.name = id; node.object_id = id
	var body := StaticBody3D.new(); body.name = "Body"; body.collision_layer = 1; body.collision_mask = 2
	var collision := CollisionShape3D.new(); var shape := CapsuleShape3D.new(); shape.radius = 0.3; shape.height = 1.7
	collision.shape = shape; collision.position.y = 0.85; body.add_child(collision); node.add_child(body)
	attach(node, "npc", lifetime, task_id)
	return node

func task_graph(task: Dictionary) -> void:
	var graph := TASK.new(); graph.graph_id = "entity_" + str(task.task_id)
	graph.nodes = [{"id": "start", "kind": "start", "params": {}}, {"id": "finish", "kind": "event_received", "params": {"key": "finish_" + str(task.task_id)}}, {"id": "complete", "kind": "task_complete", "params": {"task": str(task.task_id)}}, {"id": "failure", "kind": "event_received", "params": {"key": "fail_" + str(task.task_id)}}, {"id": "failed", "kind": "task_fail", "params": {"task": str(task.task_id), "reason": "测试任务失败"}}]
	graph.edges = [{"id": "done", "from": "finish", "from_port": "then", "to": "complete", "to_port": "run"}, {"id": "fail", "from": "failure", "from_port": "then", "to": "failed", "to_port": "run"}]
	task.graph_path = "res://tools/level_editor/entity_task_%d_%s.tres" % [OS.get_process_id(), task.task_id]
	paths.append(task.graph_path)
	check(graph.validate().is_empty() and ResourceSaver.save(graph, task.graph_path) == OK, "entity fixture uses a valid real task graph")

func _ready() -> void:
	get_tree().create_timer(35, true).timeout.connect(func(): get_tree().quit(2))
	var catalog := CATALOG.new(); var event := catalog.add_event()
	var first := catalog.add_task(event.event_id, "2"); var second := catalog.add_task(event.event_id, "2")
	task_graph(first); task_graph(second)
	var other_event := catalog.add_event(); var other_task := catalog.add_task(other_event.event_id, "1"); task_graph(other_task)
	var workbook := "user://entity_lifecycle_%d.xlsx" % OS.get_process_id()
	check(catalog.save_book(workbook).is_empty(), "isolated workbook stores both task IDs and their current level")
	var world := WORLD.new(); world.name = "World"; world.world_id = "entity_test"; world.level_id = "2"; world.start_room_id = ""
	world.topology = GRAPH.new(); world.topology.graph_kind = "topology"; world.topology.graph_id = "entity_topology"
	world.events = GRAPH.new(); world.events.graph_kind = "events"; world.events.graph_id = "entity_events"
	var permanent := npc("permanent_npc", "level"); world.add_child(permanent)
	var first_npc := npc("first_npc", "task", first.task_id); world.add_child(first_npc)
	var second_npc := npc("second_npc", "task", second.task_id); world.add_child(second_npc)
	var wrong_level_npc := npc("wrong_level_npc", "task", other_task.task_id); world.add_child(wrong_level_npc)
	var room := FACTORY.ROOM.new(); room.name = "TaskRoom"; room.room_id = "task_room"; room.uses_topology = false
	attach(room, "room", "task", first.task_id); world.add_child(room)
	var mechanism := FACTORY.PLACE.new(); mechanism.name = "TaskMechanism"; mechanism.object_id = "task_mechanism"; mechanism.component_kind = "placeholder"; mechanism.placeholder_contract = ""
	mechanism.component_scene = preload("res://addons/godot_level_editor/scenes/mechanisms/button.tscn")
	attach(mechanism, "mechanism", "task", first.task_id); world.add_child(mechanism)
	add_child(world)
	await physics(3)
	check(world.runtime_valid, "fixture world passes the same runtime graph validation as authored levels")
	check(permanent.visible and permanent.get_node("Body").collision_layer == 1, "permanent NPC is active without any task director")
	check(not first_npc.visible and not second_npc.visible and first_npc.get_node("Body").collision_layer == 0, "task NPCs are hidden and non-colliding before their task starts")
	check(not room.visible and room._region.collision_mask == 0, "task Room disables its detection area before activation")
	check(not mechanism.visible and not mechanism.runtime_component.can_process(), "task mechanism execution is disabled before activation")
	var director := DIRECTOR.new(); director.name = "Tasks"; director.world_path = NodePath("../World"); director.workbook = workbook; add_child(director)
	check(director.valid and director.start_event(event.event_id), "real event director starts the first task")
	check(director.start_event(other_event.event_id), "cross-level event can wait for its task's own level")
	await physics()
	check(first_npc.visible and first_npc.get_node("Body").collision_layer == 1 and not second_npc.visible, "only the NPC belonging to the active task appears with restored collision")
	check(not wrong_level_npc.visible, "an active task waiting for another level does not spawn entities in this level")
	check(room.visible and room._region.collision_mask == 2 and mechanism.visible and mechanism.runtime_component.can_process(), "Room and mechanism follow the same active-task lifecycle")
	permanent.hide(); await physics()
	check(not permanent.visible, "permanent entity adapter preserves explicit gameplay visibility changes")
	permanent.show()
	var progress: Dictionary = director.capture_progress()
	director.publish_event("finish_" + first.task_id); await physics()
	check(director.task_states[first.task_id] == "completed" and not first_npc.visible and first_npc.get_node("Body").collision_layer == 0, "completing the real task removes its NPC and collision")
	check(not room.visible and room._region.collision_mask == 0 and not mechanism.visible and not mechanism.runtime_component.can_process(), "completion also disables the task Room and mechanism")
	check(second_npc.visible and permanent.visible, "next task NPC appears while the permanent NPC remains")
	director.publish_event("finish_" + second.task_id); await physics()
	check(not second_npc.visible and permanent.visible, "finishing the event removes only its task entities")
	check(director.restore_progress(progress), "real task progress can restore an earlier active task")
	await physics()
	check(first_npc.visible and room.visible and mechanism.visible and not second_npc.visible, "restoring progress reactivates the matching task entities")
	director.publish_event("fail_" + first.task_id); await physics()
	check(director.task_states[first.task_id] == "failed" and not first_npc.visible and not room.visible and not mechanism.visible, "task failure also removes its entities")
	for path in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(workbook))
	print("PLACED ENTITIES: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
