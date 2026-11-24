@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor/graph_panel.gd"
var bound_task_id := ""
const EVENT_CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
var event_editor: Control
var _owner_id := ""
var _owner_path := ""
var _owner_title := ""
var _task_title := ""
var run_steps: MenuButton
var _previous_steps: Array = []
var _previous_graph := ""
var _previous_world := ""
var task_file: EditorFileDialog
var file_saving := false
var task_library_label: Label
var switch_dialog: ConfirmationDialog
var _switch_action: Callable
var toolbar: HFlowContainer
var toolbar_menus: Dictionary = {}
const TASK := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")

func _ready() -> void:
	super._ready()
	mode.hide()
	canvas.zoom_min = 0.25
	# Keep shared backend controls available without showing a second action bar.
	get_child(0).hide()
	toolbar = HFlowContainer.new()
	toolbar.name = "TaskToolbar"
	add_child(toolbar)
	move_child(toolbar, 0)
	var common := HBoxContainer.new()
	common.name = "CommonActions"
	toolbar.add_child(common)
	_button(common, "添加节点", _show_picker)
	_button(common, "保存", save_graph)
	common.get_child(1).tooltip_text = "校验当前任务图并保存"
	_button(common, "撤销", func(): undo.undo())
	_button(common, "重做", func(): undo.redo())
	_button(common, "适合画布", fit_graph)
	var menus := HBoxContainer.new()
	menus.name = "GroupedActions"
	toolbar.add_child(menus)
	menus.add_child(VSeparator.new())
	_toolbar_menu(menus, "文件", [
		["打开任务图", func(): _choose_task(false)],
		["新建任务图", _new_task],
		["另存任务图", func(): _choose_task(true)],
		[], ["保存后重载", save_reload]])
	_toolbar_menu(menus, "编辑", [
		["复制", copy_selected], ["粘贴", paste_selected], ["删除", delete_selected],
		[], ["整理节点", arrange_all]])
	_toolbar_menu(menus, "绑定", [
		["使用当前世界", use_current_world], ["使用台本页当前库", _bind_library]])
	_toolbar_menu(menus, "试玩", [
		["试玩当前关卡", _play_owner]])
	task_library_label = Label.new()
	task_library_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(task_library_label)
	move_child(task_library_label, 1)
	run_steps = MenuButton.new()
	run_steps.flat = false
	run_steps.alignment = HORIZONTAL_ALIGNMENT_LEFT
	run_steps.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	run_steps.hide()
	run_steps.get_popup().id_pressed.connect(_focus_step)
	add_child(run_steps)
	move_child(run_steps, 2)
	visibility_changed.connect(func():
		if is_visible_in_tree(): _library_label(true))
	task_file = EditorFileDialog.new()
	task_file.add_filter("*.tres", "任务图")
	task_file.file_selected.connect(_task_selected)
	add_child(task_file)
	open_graph(TASK.new())
	use_current_world()
	_library_label()

func _toolbar_menu(parent: Control, title: String, items: Array) -> void:
	var menu := MenuButton.new()
	menu.text = title
	parent.add_child(menu)
	toolbar_menus[title] = menu
	var actions := {}
	for index in items.size():
		var item: Array = items[index]
		if item.is_empty(): menu.get_popup().add_separator()
		else:
			menu.get_popup().add_item(str(item[0]), index)
			actions[index] = item[1]
	menu.get_popup().id_pressed.connect(func(id: int):
		if actions.has(id): actions[id].call())

func use_current_world() -> void:
	world = null
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		if root.get_script() == WORLD: world = root
		else:
			for child in root.find_children("*", "Node3D", true, false):
				if child.get_script() == WORLD: world = child; break
	status.text = ""
	_library_label(true)
	_rebuild()

func _choose_task(saving: bool) -> void:
	file_saving = saving
	task_file.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE if saving else EditorFileDialog.FILE_MODE_OPEN_FILE
	task_file.current_path = "res://content/resources/task_graphs/new.task.tres"
	task_file.popup_centered_ratio(0.7)

func confirm_graph_switch(action: Callable) -> void:
	_switch_action = action
	if not is_instance_valid(switch_dialog):
		switch_dialog = ConfirmationDialog.new()
		switch_dialog.title = "切换任务图"
		switch_dialog.ok_button_text = "保存后打开"
		switch_dialog.cancel_button_text = "取消"
		switch_dialog.dialog_hide_on_ok = false
		switch_dialog.add_button("放弃修改并打开", false, "discard")
		add_child(switch_dialog)
		switch_dialog.confirmed.connect(_save_and_switch)
		switch_dialog.custom_action.connect(func(action_name: StringName):
			if action_name == &"discard":
				dirty = false
				_finish_switch())
		switch_dialog.canceled.connect(func(): _switch_action = Callable())
	switch_dialog.dialog_text = "当前任务图有未保存修改，请选择如何处理。"
	switch_dialog.popup_centered()

func _save_and_switch() -> void:
	if not save_graph():
		switch_dialog.dialog_text = "无法保存当前任务图：\n" + status.text
		return
	_finish_switch()

func _finish_switch() -> void:
	var action := _switch_action
	_switch_action = Callable()
	switch_dialog.hide()
	if action.is_valid(): action.call()

func _new_task() -> void:
	if dirty:
		status.text = "请先保存当前任务图。"
		return
	var source := TASK.new()
	source.dialogue_library = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd").new()
	source.graph_id = GRAPH.fresh_id("task")
	bound_task_id = ""
	open_graph(source)
	_choose_task(true)

func _task_selected(path: String) -> void:
	if file_saving:
		_sync_bound_task()
		var errors := graph.validate()
		if not errors.is_empty(): status.text = "; ".join(errors); return
		if ResourceSaver.save(graph, path) == OK:
			graph.take_over_path(path)
			dirty = false
			status.text = "已保存任务图：" + path
			EditorInterface.get_resource_filesystem().scan()
			bound_task_id = _catalog_task_id(path)
			_library_label(true)
	else:
		if graph != null and graph.resource_path == path: return
		if dirty:
			confirm_graph_switch(_task_selected.bind(path))
			return
		var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if source != null and source.get_script() == TASK:
			bound_task_id = _catalog_task_id(path)
			open_graph(source)
			_library_label()
		else: status.text = "请选择任务图资源。"

func _bind_library() -> void:
	var source: Resource = plugin.dialogue_panel.library
	if plugin.dialogue_panel.dirty:
		status.text = "请先保存台本页，再将它绑定到任务。"
		return
	if plugin.dialogue_panel.export_dirty:
		status.text = "请先导出当前对白 XLSX，再绑定任务。"
		return
	var path := str(source.get_meta("source_path", ""))
	if path.is_empty(): return
	graph.dialogue_library = null
	graph.dialogue_xlsx = path if path.ends_with(".xlsx") else source.xlsx_path
	dirty = true
	_library_label()

func _library_label(refresh := false) -> void:
	if task_library_label == null or graph == null: return
	if refresh or _owner_id != bound_task_id:
		_owner_id = bound_task_id
		_owner_path = ""
		_owner_title = ""
		_task_title = ""
		if not bound_task_id.is_empty():
			var catalog: Resource = event_editor.catalog if is_instance_valid(event_editor) else null
			if catalog == null: catalog = EVENT_CATALOG.load_book().catalog
			if catalog != null:
				var task: Dictionary = catalog.task_by_id(bound_task_id)
				_task_title = str(task.get("display_name", ""))
				var levels := EVENT_CATALOG.LEVELS.load_book(EVENT_CATALOG.LEVELS.PATH, false)
				if levels.catalog != null:
					var level: Dictionary = levels.catalog.by_id(str(task.get("level_id", "")))
					_owner_path = str(level.get("scene_path", ""))
					_owner_title = str(level.get("display_name", ""))
	var state := "有修改" if dirty else ("未保存" if graph.resource_path.is_empty() else "已保存")
	var table := str(graph.table_file()).get_file()
	task_library_label.text = "所属关卡　%s　　任务　%s　　台本　%s　　%s" % [
		_owner_title if not _owner_title.is_empty() else "未绑定",
		_task_title if not _task_title.is_empty() else ("未登记" if bound_task_id.is_empty() else bound_task_id),
		table if not table.is_empty() else "未绑定", state]
	if toolbar_menus.has("试玩"):
		var menu: PopupMenu = toolbar_menus["试玩"].get_popup()
		menu.set_item_text(0, "试玩所属关卡　" + _owner_title if not _owner_path.is_empty() else "试玩当前关卡")

func _play_owner() -> void:
	if is_instance_valid(event_editor) and event_editor.dirty:
		event_editor.save()
		if event_editor.dirty:
			status.text = event_editor.status.text
			return
	_library_label(true)
	var root := EditorInterface.get_edited_scene_root()
	if not bound_task_id.is_empty() and (_owner_path.is_empty() or not FileAccess.file_exists(_owner_path)):
		status.text = "请在“事件与任务”中选择有效的所属关卡。"
		return
	if _owner_path.is_empty() and (root == null or not is_instance_valid(world)):
		status.text = "请先打开要试玩的关卡。"
		return
	if not _owner_path.is_empty() and (root == null or root.scene_file_path != _owner_path):
		EditorInterface.open_scene_from_path(_owner_path)
		for attempt in 60:
			root = EditorInterface.get_edited_scene_root()
			if root != null and root.scene_file_path == _owner_path: break
			await get_tree().process_frame
		if root == null or root.scene_file_path != _owner_path:
			status.text = "未能打开所属关卡。"
			return
	use_current_world()
	if dirty and not save_graph(): return
	EditorInterface.play_current_scene()

func _update_runtime() -> void:
	super._update_runtime()
	if run_steps == null or graph == null: return
	var packet: Dictionary = _packets.get(_active_key, {})
	if not packet.is_empty():
		_previous_steps = packet.get("trace", []).duplicate()
		_previous_graph = graph.graph_id
		_previous_world = str(packet.get("world_id", ""))
	var matching: bool = _previous_graph == graph.graph_id and (not is_instance_valid(world) or world.world_id == _previous_world)
	var history: Array = _previous_steps if matching else []
	var waiting: Array = packet.get("waiting", [])
	run_steps.visible = not waiting.is_empty() or not history.is_empty()
	if not run_steps.visible: return
	var menu := run_steps.get_popup()
	if menu.visible: return
	menu.clear()
	for entry in waiting:
		_append_step(menu, str(entry.id), _step_text(entry))
	if not waiting.is_empty() and not history.is_empty(): menu.add_separator()
	for index in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[index]
		_append_step(menu, str(entry.id), _step_text(entry))
	run_steps.text = ("上次试玩　" if packet.is_empty() else "试玩记录　") + (menu.get_item_text(0) if menu.item_count > 0 else "") + "　▾"
	run_steps.tooltip_text = "展开查看最近的执行和等待条件，选择一项定位节点。"

func _step_text(entry: Dictionary) -> String:
	var n := graph.node_by_id(str(entry.id))
	var name_text := GRAPH.display_label(n) if not n.is_empty() else str(entry.id)
	var target := str(entry.get("target", ""))
	var reason := str(entry.get("reason", ""))
	if not target.is_empty(): reason = _friendly("object", target) + "　" + reason
	return name_text + ("　" + reason if not reason.is_empty() else "")

func _append_step(menu: PopupMenu, id: String, caption: String) -> void:
	menu.add_item(caption)
	var index := menu.item_count - 1
	menu.set_item_metadata(index, id)
	menu.set_item_disabled(index, graph.node_by_id(id).is_empty())

func _focus_step(menu_id: int) -> void:
	var menu := run_steps.get_popup()
	var id := str(menu.get_item_metadata(menu.get_item_index(menu_id)))
	var node := canvas.get_node_or_null(NodePath(id)) as GraphNode
	if node == null: return
	canvas.set_selected(node)
	_select_graph_node(node)
	canvas.scroll_offset = node.position_offset * canvas.zoom - canvas.size * 0.35

func _can_offer_node(kind: String) -> bool:
	return TASK.supported_kinds().has(kind)

func save_graph() -> bool:
	if graph != null and bound_task_id.is_empty(): bound_task_id = _catalog_task_id(graph.resource_path)
	_sync_bound_task()
	if graph != null and is_instance_valid(world):
		var expected_level := ""
		if not bound_task_id.is_empty():
			var catalog: Resource = event_editor.catalog if is_instance_valid(event_editor) else EVENT_CATALOG.load_book().catalog
			if catalog != null: expected_level = str(catalog.task_by_id(bound_task_id).get("level_id", ""))
		var binding_errors := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_bindings.gd").validate(world, graph, bound_task_id, expected_level)
		if expected_level.is_empty() or str(world.level_id) == expected_level:
			for node in graph.nodes: binding_errors.append_array(preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_nodes.gd").validate_bindings(world, node))
		if not binding_errors.is_empty(): status.text = "未保存：" + "；".join(binding_errors); return false
	if graph != null and graph.dialogue_library != null and not graph.dialogue_library.resource_path.is_empty():
		graph.dialogue_library = ResourceLoader.load(graph.dialogue_library.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var saved := super.save_graph()
	_library_label()
	return saved

func _catalog_task_id(path: String, source: Resource = null) -> String:
	if path.is_empty(): return ""
	if source == null:
		var book := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd").load_book()
		source = book.catalog
	if source == null: return ""
	var matches: Array[String] = []
	for task in source.tasks:
		if str(task.graph_path) == path: matches.append(str(task.task_id))
	return matches[0] if matches.size() == 1 else ""

func _sync_bound_task() -> void:
	if graph == null or bound_task_id.is_empty() or graph.is_level_logic(): return
	var changed := false
	for node in graph.nodes:
		if not TASK.LOCAL_TASK_KINDS.has(node.get("kind", "")) or not node.get("params") is Dictionary: continue
		if node.params.get("task", "") != bound_task_id:
			node.params.task = bound_task_id
			changed = true
	if changed:
		dirty = true
		graph.emit_changed()

func _rebuild() -> void:
	_sync_bound_task()
	super._rebuild()
	_library_label()

func default_task_id() -> String:
	return bound_task_id

func _show_parameters() -> void:
	if parameters == null: return
	parameters.get_parent().visible = graph != null and not graph.node_by_id(selected_id).is_empty()
	if graph != null:
		var selected: Dictionary = graph.node_by_id(selected_id)
		if not selected.is_empty() and preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_nodes.gd").DEFINITIONS.has(selected.kind):
			preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_parameters.gd").draw(self, selected)
			return
	super._show_parameters()
	if not bound_task_id.is_empty() and _fields.has("task") and _fields.task is LineEdit: _fields.task.editable = false
