@tool
extends RefCounted
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)
func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	suite._make_visible(true)
	suite.open_tab("任务图")
	await frames(tree)
	var panel: Control = suite.task_graph
	var original: Resource = panel.graph
	var original_hash: String = original.semantic_hash()
	var original_dirty: bool = panel.dirty
	var original_binding: String = panel.bound_task_id
	var original_undo: UndoRedo = panel.undo
	var original_world: Node = panel.world
	panel.undo = UndoRedo.new()
	panel.dirty = false
	panel.world = null
	var task := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd").new()
	task.graph_id = "task_owner_test"
	for kind in task.LOCAL_TASK_KINDS:
		var p := {"task": ""}
		if kind == "task_start": p.erase("task")
		if kind == "npc_interact": p = {"npc": "receptionist", "task": "old_task"}
		if kind == "dialog_completed": p = {"dialog_id": "reception_intro", "task": ""}
		if kind == "task_fail": p = {"task": "", "reason": "测试"}
		var id := "n_12c9b56108581caa390b7a04" if kind == "task_complete" else str(kind)
		task.nodes.append({"id": id, "kind": kind, "params": p})
		task.positions[id] = Vector2((task.nodes.size() - 1) * 260, 100)
	var paths: Array[String] = []
	var path := "user://task_owner_%d.tres" % OS.get_process_id()
	paths.append(path)
	ResourceSaver.save(task, path)
	task.take_over_path(path)
	check(not task.validate().is_empty(), "missing task IDs reproduce the save validation failure")
	var node_ids: Array = task.nodes.map(func(n: Dictionary): return n.id)
	panel.bound_task_id = "1001001"
	panel.open_graph(task)
	check(task.nodes.all(func(n: Dictionary): return n.params.get("task") == "1001001"), "opening a bound task repairs missing and foreign local task IDs")
	check(task.nodes.map(func(n: Dictionary): return n.id) == node_ids, "automatic binding preserves stable node IDs")
	check(panel.dirty and task.validate().is_empty(), "repaired graph is valid and remains unsaved until the user saves")
	panel.selected_id = "n_12c9b56108581caa390b7a04"
	panel._show_parameters()
	check(panel._fields.task.text == "1001001" and not panel._fields.task.editable, "inspector shows the correct read-only task ID")
	check(panel.save_graph(), "repaired graph saves normally")
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded.nodes.all(func(n: Dictionary): return n.params.task == "1001001"), "saved graph contains the current task binding")
	var foreign := {"id": "foreign", "kind": "task_complete", "params": {"task": "9001001"}}
	panel._clipboard = {"kind": "events", "nodes": [foreign], "edges": [], "positions": {"foreign": Vector2.ZERO}}
	var count: int = task.nodes.size()
	panel.paste_selected()
	check(task.nodes.size() == count + 1 and task.nodes[-1].params.task == "1001001", "pasting a completion node from another task rebinds it to the current task")
	panel.undo.undo()
	check(task.nodes.size() == count, "paste remains undoable")
	panel.undo.redo()
	check(task.nodes[-1].params.task == "1001001", "redo cannot restore a foreign task ID")
	task.nodes[1].params.task = ""
	check(panel.save_graph() and task.nodes[1].params.task == "1001001", "save also repairs an already-open draft with an empty task ID")
	var catalog := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd").new()
	var event := catalog.add_event()
	var row := catalog.add_task(event.event_id, "1")
	row.graph_path = path
	check(panel._catalog_task_id(path, catalog) == row.task_id, "registered graph paths resolve their actual task ID")
	var duplicate := catalog.add_task(event.event_id, "1")
	duplicate.graph_path = path
	check(panel._catalog_task_id(path, catalog).is_empty(), "ambiguous graph ownership is not guessed")
	var unbound: Resource = task.duplicate(true)
	unbound.nodes.assign([{"id": "finish", "kind": "task_complete", "params": {"task": ""}}])
	var unbound_path := path.replace(".tres", "_unbound.tres")
	paths.append(unbound_path)
	ResourceSaver.save(unbound, unbound_path)
	unbound.take_over_path(unbound_path)
	panel.bound_task_id = ""
	panel.dirty = false
	panel.open_graph(unbound)
	check(not panel.save_graph() and panel.status.text.contains("缺少所属任务") and panel.status.text.contains("完成任务"), "unregistered standalone graphs show a named, actionable missing-owner error")
	unbound.nodes[0].params.task = "legacy_task"
	check(panel.save_graph() and unbound.nodes[0].params.task == "legacy_task", "standalone legacy bindings remain editable and are not overwritten")
	var labels: Array[String] = []
	for button in panel.toolbar.get_node("CommonActions").get_children(): labels.append(button.text)
	check(labels == ["添加节点", "保存", "撤销", "重做", "适合画布"], "frequent actions occupy the left group in priority order")
	check(panel.toolbar_menus.keys() == ["文件", "编辑", "绑定", "试玩"], "secondary commands are grouped by function")
	var commands: Array[String] = []
	for menu in panel.toolbar_menus.values():
		var popup: PopupMenu = menu.get_popup()
		for i in popup.item_count:
			if not popup.is_item_separator(i): commands.append(popup.get_item_text(i))
	check(commands == ["打开任务图", "新建任务图", "另存任务图", "保存后重载", "复制", "粘贴", "删除", "整理节点", "使用当前世界", "使用台本页当前库", "打开对话试玩"], "all secondary commands remain available through the grouped menus")
	panel.toolbar_menus["文件"].get_popup().id_pressed.emit(0)
	check(panel.task_file.visible and not panel.file_saving, "File/Open executes the original file dialog action")
	panel.task_file.hide()
	panel.toolbar_menus["文件"].get_popup().id_pressed.emit(2)
	check(panel.task_file.visible and panel.file_saving, "File/Save As executes the original file dialog action")
	panel.task_file.hide()
	panel.toolbar.get_node("CommonActions").get_child(0).pressed.emit()
	check(panel.picker.visible, "leftmost Add Node opens the node palette")
	check(not panel.node_category.visible and panel.node_picker.category_buttons.size() == 7, "category filters are always available as buttons instead of a dropdown")
	var headers := 0
	var colors_ok := true
	var clean_names := true
	for i in panel.choices.item_count:
		var kind := str(panel.choices.get_item_metadata(i))
		if kind.is_empty():
			headers += 1
			colors_ok = colors_ok and not panel.choices.is_item_selectable(i)
		else:
			var icon: GradientTexture2D = panel.choices.get_item_icon(i)
			var role: String = panel.PRESENTATION.category_key(kind)
			colors_ok = colors_ok and icon != null and icon.gradient.get_color(0) == panel.PRESENTATION.CATEGORIES[role].color
			clean_names = clean_names and not panel.choices.get_item_text(i).contains("【")
	check(headers == 6 and colors_ok, "all-node results have separate non-selectable category headers and matching role colors")
	check(clean_names, "node names do not repeat category prefixes on every row")
	panel.node_picker.category_buttons[2].pressed.emit()
	var only_actions: bool = panel.choices.item_count > 0
	for i in panel.choices.item_count:
		only_actions = only_actions and panel.PRESENTATION.category_key(str(panel.choices.get_item_metadata(i))) == "action"
	check(only_actions and panel.node_category.selected == 2, "one click filters the results to actions")
	panel.node_picker.category_buttons[0].pressed.emit()
	panel.search.text = "Equipped"
	panel._filter_choices()
	check(panel.choices.item_count == 2, "English search still finds nodes across categories")
	panel.search.text = "no_such_node_qa"
	panel._filter_choices()
	check(panel.choices.item_count == 0 and panel.picker.get_ok_button().disabled, "empty search results cannot add an invalid node")
	panel.search.text = "数值"
	panel._filter_choices()
	var number_index := -1
	for i in panel.choices.item_count:
		if panel.choices.get_item_metadata(i) == "number": number_index = i
	if number_index >= 0:
		var before_add: int = panel.graph.nodes.size()
		panel.choices.select(number_index)
		panel.choices.item_activated.emit(number_index)
		check(panel.graph.nodes.size() == before_add + 1 and panel.graph.nodes[-1].kind == "number", "double-clicking a categorized result adds the selected node")
		panel.undo.undo()
	else: check(false, "number node remains searchable")
	panel.picker.hide()
	if OS.get_cmdline_user_args().has("--capture"):
		panel.bound_task_id = "1001001"
		panel.dirty = false
		panel.open_graph(task)
		panel.selected_id = "n_12c9b56108581caa390b7a04"
		panel._show_parameters()
		suite.window.size = Vector2i(1504, 1000)
		panel.arrange_all()
		await panel.fit_graph()
		await frames(tree, 10)
		RenderingServer.force_draw(false)
		var output := "res://docs/narrative_editor/task_toolbar_2026-11-16"
		DirAccess.make_dir_recursive_absolute(output)
		suite.window.get_texture().get_image().save_png(output + "/任务图工具栏.png")
		var file_menu: MenuButton = panel.toolbar_menus["文件"]
		file_menu.get_popup().popup_centered()
		await frames(tree)
		RenderingServer.force_draw(false)
		file_menu.get_popup().get_texture().get_image().save_png(output + "/文件菜单.png")
		file_menu.get_popup().hide()
		panel._show_picker()
		await frames(tree)
		RenderingServer.force_draw(false)
		panel.picker.get_texture().get_image().save_png(output + "/节点分类.png")
		panel.picker.hide()
		check(panel.toolbar.size.y < 100 and panel.canvas.size.x > 650, "rendered toolbar stays compact and leaves canvas space")
	panel.dirty = false
	panel.bound_task_id = original_binding
	panel.open_graph(original)
	panel.dirty = original_dirty
	panel.undo = original_undo
	panel.world = original_world
	check(original.semantic_hash() == original_hash, "tests preserve the original user graph")
	for temp_path in paths: DirAccess.remove_absolute(temp_path)
	print("TASK OWNER AND TOOLBAR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
