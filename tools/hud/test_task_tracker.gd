extends Node
var checks := 0
var failures := 0
var paths: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)
func physics(count := 3) -> void:
	for i in count: await get_tree().physics_frame
func wait_for(predicate: Callable, seconds := 3.0) -> bool:
	var elapsed := 0.0
	var deadline := Time.get_ticks_msec() + 15000
	while elapsed < seconds and Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return false
func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	await RenderingServer.frame_post_draw
	var output := "res://docs/hud/task_tracker_2026-11-16"
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output + "/" + name + ".png")
func make_task(catalog: Resource, event: Dictionary, title: String) -> Dictionary:
	var task: Dictionary = catalog.add_task(event.event_id, "2")
	task.display_name = title
	var graph := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd").new()
	graph.graph_id = "hud_test_" + str(task.task_id)
	graph.nodes = [{"id": "finish", "kind": "event_received", "params": {"key": task.task_id}}, {"id": "complete", "kind": "task_complete", "params": {"task": task.task_id}}]
	graph.edges = [{"id": "e1", "from": "finish", "from_port": "then", "to": "complete", "to_port": "run"}]
	task.graph_path = "user://task_hud_%d_%s.tres" % [OS.get_process_id(), task.task_id]
	ResourceSaver.save(graph, task.graph_path)
	paths.append(task.graph_path)
	return task
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(35, true).timeout.connect(func(): get_tree().quit(2))
	var session: Node = load("res://tools/narrative/session_fixture.tscn").instantiate()
	var director: Node = session.get_node("Narrative/Tasks")
	director.automatic_starts = false
	add_child(session)
	await physics(15)
	var catalog := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd").new()
	var event := catalog.add_event()
	event.display_name = "窃取旗帜"
	var first := make_task(catalog, event, "进入无线电室")
	var second := make_task(catalog, event, "取得门禁卡")
	var third := make_task(catalog, event, "离开基地")
	director.catalog = catalog
	director.start_event(event.event_id)
	await physics()
	var tracker: Control = director.objective_label
	check(tracker == session.get_node("HUD/Root/TaskTracker"), "runtime reuses the editable HUD tracker instead of a duplicate overlay")
	var row: Node = tracker.rows[event.event_id]
	check(row.title_line.label.text == "窃取旗帜" and row.task_line.label.text == "进入无线电室", "event and task display names occupy separate levels")
	check(row.task_line.get_parent().get_theme_constant("margin_left") == 26, "task is indented below its event")
	await get_tree().create_timer(0.4).timeout
	await capture("01_当前任务")
	var saved: Dictionary = director.capture_progress()
	director.publish_event(first.task_id)
	await physics()
	check(director.task_states.get(second.task_id) == "active", "gameplay advances independently of the completion animation")
	check(row.busy and row.displayed_task == first.task_id, "completed task remains visible while the strike is drawn")
	await wait_for(func(): return row.task_line.strike > 0.5)
	await capture("02_划掉任务")
	var strike: float = row.task_line.strike
	director._hide_ui()
	get_tree().paused = true
	await get_tree().create_timer(0.2, true).timeout
	check(not tracker.visible and is_equal_approx(row.task_line.strike, strike), "dialogue pause hides the tracker and freezes its animation")
	get_tree().paused = false
	director._restore_ui()
	check(tracker.visible, "dialogue restores tracker visibility")
	check(await wait_for(func(): return row.displayed_task == second.task_id and row.task_line.modulate.a < 1), "next task enters through a fade after the strike and fade-out")
	await wait_for(func(): return row.task_line.modulate.a > 0.45)
	await capture("03_下个任务渐显")
	await get_tree().create_timer(0.4).timeout
	check(row.task_line.label.text == "取得门禁卡" and row.task_line.strike == 0, "new task has clean text without the previous strike")
	director.publish_event(second.task_id); await physics()
	director.publish_event(third.task_id); await physics()
	check(director.event_states[event.event_id] == "completed", "finishing the event is not delayed by HUD animation")
	check(tracker.rows.has(event.event_id), "last task is retained until its completion animation ends")
	check(await wait_for(func(): return not tracker.rows.has(event.event_id)), "rapid consecutive completions drain their queue and remove the finished event")
	check(not tracker.visible, "tracker disappears when there are no active events")
	check(director.restore_progress(saved), "task progress restores normally")
	await physics()
	row = tracker.rows[event.event_id]
	check(row.displayed_task == first.task_id and not row.busy and row.task_line.strike == 0, "restore shows the active task without replaying completion animations")
	director.publish_event(first.task_id); await physics()
	check(row.busy, "completion animation starts again after checkpoint replay")
	director.restore_progress(saved); await physics()
	check(not tracker.rows[event.event_id].busy, "restore during an animation cancels the obsolete visual queue")
	var other := catalog.add_event()
	other.display_name = "取得情报"
	make_task(catalog, other, "调查档案柜")
	director.start_event(other.event_id); await physics()
	check(tracker.rows.size() == 2, "multiple active events each retain their own current task")
	for path in paths: DirAccess.remove_absolute(path)
	session.queue_free(); await physics()
	print("TASK TRACKER: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
