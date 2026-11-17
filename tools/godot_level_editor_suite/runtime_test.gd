extends Node
const XLSX := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/xlsx.gd")
const LIB := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd")
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const TASK := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")
var checks := 0
var failed := 0
var paths: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func physics(count := 3) -> void:
	for i in count: await get_tree().physics_frame
func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame
func graph(task: Dictionary, held := false) -> void:
	var resource := TASK.new()
	resource.graph_id = "task_" + str(task.task_id)
	resource.nodes = [{"id": "start", "kind": "start", "params": {}}, {"id": "received", "kind": "event_received", "params": {"key": "finish_" + str(task.task_id)}}, {"id": "complete", "kind": "task_complete", "params": {"task": str(task.task_id)}}]
	resource.edges = [{"id": "e1", "from": "received", "from_port": "then", "to": "complete", "to_port": "run"}]
	if held:
		resource.nodes.append({"id": "hold", "kind": "event_hold", "params": {}})
		resource.nodes.append({"id": "release", "kind": "event_received", "params": {"key": "release"}})
		resource.nodes.append({"id": "end", "kind": "event_complete", "params": {}})
		resource.edges.append({"id": "e2", "from": "start", "from_port": "then", "to": "hold", "to_port": "run"})
		resource.edges.append({"id": "e3", "from": "release", "from_port": "then", "to": "end", "to_port": "run"})
	task.graph_path = "res://tools/godot_level_editor_suite/.test_graph_" + str(OS.get_process_id()) + "_" + str(task.task_id) + ".tres"
	paths.append(str(task.graph_path))
	check(resource.validate().is_empty() and ResourceSaver.save(resource, task.graph_path) == OK, "task graph accepts automatically allocated numeric task ID")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(35, true).timeout.connect(func(): get_tree().quit(2))
	var source := LIB.read_xlsx("res://content/tables/dialogues.xlsx")
	check(source.errors.is_empty(), "migrated dialogue XLSX reads all five sheets")
	if not source.errors.is_empty(): print(source.errors); get_tree().quit(1); return
	check(not source.library.comment_by_id("reception_intro").is_empty(), "migration preserves existing dialogue and comment IDs")
	var book := CATALOG.load_book()
	check(book.errors.is_empty(), "events.xlsx loads event and task sheets plus persistent counters")
	var library: Resource = source.library.duplicate(true)
	var line: Dictionary = library.comment_by_id("reception_intro").lines[0]
	line.text = "逗号,引号\"\n多行 & < > 内容"
	line.id = "09999"
	library.next_line_id = 40
	check(library.write_xlsx("user://godot_level_editor_dialogue_test.xlsx").is_empty(), "editor writes valid XLSX without a CSV intermediate")
	var loaded := LIB.read_xlsx("user://godot_level_editor_dialogue_test.xlsx")
	check(loaded.errors.is_empty() and loaded.library.comment_by_id("reception_intro").lines[0].text == line.text, "XLSX round trip retains Unicode, quotes, XML characters and line breaks")
	check(loaded.library.comment_by_id("reception_intro").lines[0].id == "09999" and loaded.library.allocate_line_id() == "00040", "XLSX retains leading zeros and monotonic ID counters")
	var invalid := XLSX.read_book("user://does_not_exist.xlsx")
	check(not invalid.errors.is_empty(), "missing workbook returns an actionable failure")
	var catalog := CATALOG.new()
	var event := catalog.add_event()
	event.display_name = "新手教学"
	var first := catalog.add_task(event.event_id, "2")
	first.display_name = "找讲解员说话"
	var second := catalog.add_task(event.event_id, "2")
	second.display_name = "潜入剧院"
	check(event.event_id == "1001" and first.task_id == "1001001" and second.task_id == "1001002", "event IDs begin at 1001 and tasks append a three-digit suffix")
	second.order = 0
	first.order = 1
	check(catalog.event_tasks("1001")[0].task_id == "1001002" and first.task_id == "1001001", "execution order changes independently of stable IDs")
	first.order = 0
	second.order = 1
	graph(first)
	graph(second)
	var special := catalog.add_event()
	special.display_name = "等待显式结束"
	var held_task := catalog.add_task(special.event_id, "2")
	graph(held_task, true)
	var received := catalog.add_event()
	received.start_type = "event_received"
	received.start_key = "start_event"
	var room := catalog.add_event()
	room.start_type = "room_enter"
	room.start_key = "atrium"
	check(catalog.save_book("user://godot_level_editor_events_test.xlsx").is_empty(), "catalog XLSX saves both relational sheets and ID allocation counters")
	var restored := CATALOG.load_book("user://godot_level_editor_events_test.xlsx")
	check(restored.errors.is_empty() and restored.catalog.events.size() == 4 and restored.catalog.tasks.size() == 3, "catalog round trip preserves event ownership and task order")
	var next: Dictionary = restored.catalog.add_task("1001", "2")
	check(next.task_id == "1001003", "new task after reload never reuses a previously allocated ID")
	var session: Node3D = load("res://tools/narrative/session_fixture.tscn").instantiate()
	var director: Node = session.get_node("Narrative/Tasks")
	director.workbook = "user://godot_level_editor_events_test.xlsx"
	add_child(session)
	await physics(15)
	check(director.valid, "event director starts against a real world and XLSX catalog")
	check(director.event_states.get(room.event_id) == "completed", "room entry independently starts its configured event")
	check(not director.event_states.has(event.event_id), "manual event does not begin merely because its task graph exists")
	check(director.start_event(event.name), "program name can start an event independently of HUD display name")
	await physics(3)
	check(director.task_states.get(first.task_id) == "active" and not director.task_states.has(second.task_id), "only the first ordered task is active")
	check(director.objective_label.text.contains("新手教学") and director.objective_label.text.contains("找讲解员说话"), "HUD uses event and task display names")
	director.publish_event("finish_" + str(second.task_id))
	await physics(2)
	check(not director.task_states.has(second.task_id), "future task cannot consume triggers before becoming active")
	director.publish_event("finish_" + str(first.task_id))
	await physics(3)
	check(director.task_states.get(first.task_id) == "completed" and director.task_states.get(second.task_id) == "active", "completing first task activates the next task")
	director.publish_event("finish_" + str(second.task_id))
	await physics(3)
	check(director.event_states.get(event.event_id) == "completed" and not director.active.has(event.event_id), "last task automatically completes its event")
	check(not director.start_event(event.event_id), "completed event cannot repeat implicitly")
	director.start_event(special.event_id)
	await physics(2)
	director.publish_event("finish_" + str(held_task.task_id))
	await physics(3)
	check(director.task_states.get(held_task.task_id) == "completed" and director.event_states.get(special.event_id) == "active", "explicit hold node overrides automatic event completion")
	var saved: Dictionary = director.capture_progress()
	check(director.restore_progress(saved), "active held event restores without repeating completion effects")
	director.publish_event("release")
	await physics(3)
	check(director.event_states.get(special.event_id) == "completed", "explicit end node completes a held event after save/restore")
	director.publish_event("unmatched")
	check(not director.event_states.has(received.event_id), "event-level named trigger requires an exact match")
	director.publish_event("start_event")
	check(director.event_states.get(received.event_id) == "completed", "matching received event activates event-level start condition")
	var bad: Dictionary = director.capture_progress().duplicate(true)
	bad.events["9999"] = "active"
	var before: Dictionary = director.capture_progress()
	check(not director.restore_progress(bad) and before == director.capture_progress(), "foreign progress is rejected atomically")
	var cross_catalog := CATALOG.new()
	var cross_event := cross_catalog.add_event()
	var here_task := cross_catalog.add_task(cross_event.event_id, "2")
	var away_task := cross_catalog.add_task(cross_event.event_id, "1")
	graph(here_task); graph(away_task)
	check(cross_catalog.validate().is_empty(), "one event allows consecutive tasks bound to different levels")
	away_task.level_id = ""
	check(not cross_catalog.validate().is_empty(), "task without a level is rejected")
	away_task.level_id = "1,2"
	check(not cross_catalog.validate().is_empty(), "one task cannot bind multiple levels")
	away_task.level_id = "1"
	director.catalog = cross_catalog
	director.event_states.clear(); director.task_states.clear(); director.active.clear()
	director.start_event(cross_event.event_id)
	await physics(2)
	director.publish_event("finish_" + str(here_task.task_id))
	await physics(3)
	check(director.task_states.get(away_task.task_id) == "active" and director.active[cross_event.event_id].runner == null, "next task waits when its bound level differs from current level")
	director.publish_event("finish_" + str(away_task.task_id))
	await physics(3)
	check(director.event_states.get(cross_event.event_id) == "active", "signals from the wrong level cannot advance the task")
	var other_world: Node = load("res://content/scenes/levels/whitebox_world.tscn").instantiate()
	session.add_child(other_world)
	await physics(2)
	check(director.bind_world(other_world), "director can attach to a newly entered level")
	await physics(2)
	check(director.active[cross_event.event_id].runner != null and director.current_level_id == "1", "entering the task's bound level activates its graph")
	director.publish_event("finish_" + str(away_task.task_id))
	await physics(3)
	check(director.event_states.get(cross_event.event_id) == "completed", "cross-level sequence completes only after each task runs in its own level")
	director.bind_world(session.world)
	var player: CharacterBody3D = session.player
	player.global_position = Vector3(-4, 0.1, 2)
	session.camera_rig.snap_to_target()
	director.dialogue.library = source.library.duplicate(true)
	for item in director.dialogue.library.comment_by_id("reception_intro").lines: item.duration = 0.1
	var completed: Array = []
	director.dialogue.dialogue_completed.connect(func(id: String): completed.append(id))
	check(director.dialogue.show_dialog("reception_intro"), "runtime subtitle consumes XLSX data directly")
	if OS.get_cmdline_user_args().has("--capture"):
		director.dialogue._remaining_seconds = 3.0
		await frames(8)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://docs/narrative_editor/dialogue_preview.png")
		director.dialogue._remaining_seconds = 0.1
	for i in 120:
		if not director.dialogue.is_active(): break
		await physics(1)
	check(completed == ["reception_001", "reception_002", "reception_003", "reception_intro"], "XLSX-backed comment plays automatically in order and ends at its boundary")
	check(not get_tree().paused, "dialogue restores the previous gameplay pause state")
	session.queue_free()
	await frames(3)
	# Exercise the authored room -> interaction -> dialogue -> completion chain.
	var authored: Node3D = load("res://tools/narrative/session_fixture.tscn").instantiate()
	add_child(authored)
	await physics(15)
	var authored_director: Node = authored.get_node("Narrative/Tasks")
	check(authored_director.task_states.get("1001001") == "active", "authored Room entry starts the configured event and first task")
	var actor: CharacterBody3D = authored.player
	actor.global_position = Vector3(-4, 0.1, 2)
	authored.camera_rig.snap_to_target()
	await physics(3)
	var npc: Node3D = authored.get_node("Narrative/Receptionist")
	check(npc.can_interact(actor), "current task enables interaction with its NPC within range")
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	Input.parse_input_event(interact)
	# Physics steps can share a render frame. Keep the press immutable until input
	# dispatch has run, and send a distinct release event rather than mutating it.
	await frames(2)
	await physics(2)
	var release_interact := InputEventAction.new()
	release_interact.action = "interact"
	release_interact.pressed = false
	Input.parse_input_event(release_interact)
	await frames(3)
	check(authored_director.dialogue.is_active(), "player interaction input reaches ShowDialog through the authored task graph")
	check(not authored_director.objective_label.visible and not npc.prompt.visible, "dialogue hides task and NPC overlays while displaying subtitles")
	for i in 180:
		if not authored_director.dialogue.is_active(): break
		authored_director.dialogue._remaining_seconds = 0.0
		await frames(1)
	await physics(4)
	check(authored_director.task_states.get("1001001") == "completed" and authored_director.event_states.get("1001") == "completed", "authored dialogue completion trigger finishes the task and event")
	authored.queue_free()
	await frames(3)
	for path in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for path in ["user://godot_level_editor_dialogue_test.xlsx", "user://godot_level_editor_events_test.xlsx"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("GODOT_LEVEL_EDITOR SUITE RUNTIME: %d checks, %d failures" % [checks, failed])
	get_tree().quit(1 if failed else 0)
