@tool
extends RefCounted
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)
func frames(tree: SceneTree) -> void:
	for i in 12: await tree.process_frame
func click(suite: EditorPlugin, task: Dictionary) -> void:
	suite.open_tab("事件与任务")
	await frames(suite.get_tree())
	var row: TreeItem
	for event in suite.event_panel.table.get_root().get_children():
		event.collapsed = false
		for item in event.get_children():
			if str(item.get_metadata(0)) == str(task.task_id): row = item
	if row == null: check(false, "task row exists"); return
	row.select(0)
	await frames(suite.get_tree())
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = suite.event_panel.table.get_item_area_rect(row, 5).get_center()
	suite.event_panel.table.gui_input.emit(event)
	await frames(suite.get_tree())
func run(suite: EditorPlugin) -> void:
	if OS.get_cmdline_user_args().has("--live-wire"):
		await load("res://tools/narrative/live_wiring_editor_test.gd").new().run(suite)
		return
	if OS.get_cmdline_user_args().has("--task-owner"):
		await load("res://tools/narrative/task_owner_editor_test.gd").new().run(suite)
		return
	if OS.get_cmdline_user_args().has("--qa-task-bindings"):
		await load("res://tools/narrative/task_bindings_editor_test.gd").new().run(suite)
		return
	var tree := suite.get_tree()
	suite._make_visible(true)
	var panel: Control = suite.task_graph
	var original: Resource = panel.graph
	var original_dirty: bool = panel.dirty
	var original_binding: String = panel.bound_task_id
	var original_world: Node = panel.world
	var original_undo: UndoRedo = panel.undo
	panel.undo = UndoRedo.new()
	panel.dirty = false
	var original_catalog: Resource = suite.event_panel.catalog
	var original_selection: String = suite.event_panel.selected_id
	var original_kind: String = suite.event_panel.selected_kind
	var catalog := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd").new()
	var event := catalog.add_event()
	var tasks: Array[Dictionary] = []
	for i in 2:
		var resource := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd").new()
		resource.graph_id = "switch_test_" + str(i)
		resource.nodes = [{"id": "start", "kind": "start", "params": {}}]
		var path := "user://task_switch_%d_%d.tres" % [OS.get_process_id(), i]
		ResourceSaver.save(resource, path)
		var task: Dictionary = catalog.add_task(event.event_id, "1")
		task.graph_path = path
		tasks.append(task)
	suite.event_panel.catalog = catalog
	suite.event_panel._refresh()
	await click(suite, tasks[0])
	check(panel.graph.resource_path == tasks[0].graph_path, "first edit opens task A")
	await click(suite, tasks[1])
	check(panel.graph.resource_path == tasks[1].graph_path and panel.bound_task_id == tasks[1].task_id, "second edit opens task B with its correct binding")
	await click(suite, tasks[0])
	check(panel.graph.resource_path == tasks[0].graph_path, "clean task graphs can be switched repeatedly")
	var before: Dictionary = panel.graph.snapshot()
	var after := before.duplicate(true)
	after.nodes.append({"id": "new_objective", "kind": "objective", "params": {"text": "未保存目标"}})
	panel._commit("修改目标", before, after)
	var modified: Resource = panel.graph
	await click(suite, tasks[0])
	check(panel.graph == modified and panel.dirty and panel.undo.has_undo(), "reopening current task preserves edits and undo history")
	await click(suite, tasks[1])
	check(panel.switch_dialog.visible and panel.graph == modified and panel.bound_task_id == tasks[0].task_id, "dirty switch displays a visible decision without changing the graph or task ID")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var output := "res://docs/narrative_editor/task_switch_2026-11-16"
		DirAccess.make_dir_recursive_absolute(output)
		suite.window.get_texture().get_image().save_png(output + "/切换任务图.png")
		panel.switch_dialog.get_texture().get_image().save_png(output + "/未保存提示.png")
	panel.switch_dialog.hide(); panel.switch_dialog.canceled.emit()
	check(panel.graph == modified and panel.dirty, "cancel preserves the current draft")
	await click(suite, tasks[1])
	panel.world = null
	panel._save_and_switch()
	await frames(tree)
	check(panel.graph.resource_path == tasks[1].graph_path, "save-and-open continues to requested task")
	var saved: Resource = ResourceLoader.load(tasks[0].graph_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(not saved.node_by_id("new_objective").is_empty(), "save-and-open persists the previous draft")
	panel.graph.nodes.append({"id": "invalid", "kind": "constant", "params": {"value": "invalid"}})
	panel.dirty = true
	await click(suite, tasks[0])
	panel.world = null
	panel._save_and_switch()
	check(panel.switch_dialog.visible and panel.graph.resource_path == tasks[1].graph_path and panel.switch_dialog.dialog_text.contains("无法保存"), "failed validation keeps the current graph and an actionable error")
	panel.switch_dialog.custom_action.emit(&"discard")
	await frames(tree)
	check(panel.graph.resource_path == tasks[0].graph_path, "discard-and-open opens the requested graph")
	await click(suite, tasks[1])
	check(panel.graph.node_by_id("invalid").is_empty(), "discarded edits do not reappear when reopening")
	panel.dirty = true
	panel._task_selected(tasks[0].graph_path)
	check(panel.switch_dialog.visible, "file dialog opening uses the same unsaved-change protection")
	panel.switch_dialog.custom_action.emit(&"discard")
	check(panel.graph.resource_path == tasks[0].graph_path and panel.bound_task_id.is_empty(), "standalone file opening clears the old task binding")
	panel.dirty = false
	panel.open_graph(original)
	panel.dirty = original_dirty
	panel.bound_task_id = original_binding
	panel.world = original_world
	panel.undo = original_undo
	suite.event_panel.catalog = original_catalog
	suite.event_panel.selected_id = original_selection
	suite.event_panel.selected_kind = original_kind
	suite.event_panel._refresh()
	for task in tasks: DirAccess.remove_absolute(task.graph_path)
	print("TASK SWITCH: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
