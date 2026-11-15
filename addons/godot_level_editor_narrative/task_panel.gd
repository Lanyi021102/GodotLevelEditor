@tool
extends "res://addons/godot_level_editor/graph_panel.gd"
var bound_task_id := ""
var task_file: EditorFileDialog
var file_saving := false
var task_library_label: Label
const TASK := preload("res://addons/godot_level_editor_narrative/runtime/task_definition.gd")

func _ready() -> void:
	super._ready()
	mode.hide()
	canvas.zoom_min = 0.25
	var bar := HFlowContainer.new()
	add_child(bar)
	move_child(bar, 0)
	_button(bar, "打开任务图", func(): _choose_task(false))
	_button(bar, "新建任务图", _new_task)
	_button(bar, "适合画布", fit_graph)
	_button(bar, "另存任务图", func(): _choose_task(true))
	_button(bar, "使用台本页当前库", _bind_library)
	task_library_label = Label.new()
	task_library_label.hide()
	bar.add_child(task_library_label)
	_button(bar, "打开对话试玩", func(): EditorInterface.open_scene_from_path("res://tools/narrative/session_fixture.tscn"))
	task_file = EditorFileDialog.new()
	task_file.add_filter("*.tres", "任务图")
	task_file.file_selected.connect(_task_selected)
	add_child(task_file)
	open_graph(load("res://resources/narrative/reception.task.tres"))
	use_current_world()
	_library_label()

func use_current_world() -> void:
	world = null
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		if root.get_script() == WORLD: world = root
		else:
			for child in root.find_children("*", "Node3D", true, false):
				if child.get_script() == WORLD: world = child; break
	status.text = ""

func _choose_task(saving: bool) -> void:
	file_saving = saving
	task_file.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE if saving else EditorFileDialog.FILE_MODE_OPEN_FILE
	task_file.current_path = "res://resources/narrative/new.task.tres"
	task_file.popup_centered_ratio(0.7)

func _new_task() -> void:
	if dirty:
		status.text = "请先保存当前任务图。"
		return
	var source := TASK.new()
	source.dialogue_library = load("res://resources/narrative/reception.dialogue.tres")
	source.graph_id = GRAPH.fresh_id("task")
	open_graph(source)
	_choose_task(true)

func _task_selected(path: String) -> void:
	if file_saving:
		var errors := graph.validate()
		if not errors.is_empty(): status.text = "; ".join(errors); return
		if ResourceSaver.save(graph, path) == OK:
			graph.take_over_path(path)
			dirty = false
			status.text = "已保存任务图：" + path
			EditorInterface.get_resource_filesystem().scan()
	else:
		var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if source != null and source.get_script() == TASK:
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

func _library_label() -> void:
	if graph != null:
		task_library_label.text = "配表：" + graph.table_file().get_file()

func _filter_choices() -> void:
	super._filter_choices()
	for i in range(choices.item_count - 1, -1, -1):
		if not TASK.supported_kinds().has(str(choices.get_item_metadata(i))): choices.remove_item(i)
	if choices.item_count > 0: choices.select(0)

func save_graph() -> bool:
	if graph != null and is_instance_valid(world):
		var binding_errors := PackedStringArray()
		for node in graph.nodes: binding_errors.append_array(preload("res://addons/godot_level_editor_mechanisms/task_nodes.gd").validate_bindings(world, node))
		if not binding_errors.is_empty(): status.text = "未保存：" + "；".join(binding_errors); return false
	if graph != null and graph.dialogue_library != null and not graph.dialogue_library.resource_path.is_empty():
		graph.dialogue_library = ResourceLoader.load(graph.dialogue_library.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return super.save_graph()

func fit_graph() -> void:
	if graph == null or graph.nodes.is_empty(): return
	await get_tree().process_frame
	var bounds := Rect2()
	var first := true
	for card in canvas.get_children():
		if not card is GraphNode: continue
		var rect := Rect2(card.position_offset, card.size)
		bounds = rect if first else bounds.merge(rect)
		first = false
	if first: return
	canvas.zoom = clampf(minf((canvas.size.x - 80) / bounds.size.x, (canvas.size.y - 120) / bounds.size.y), canvas.zoom_min, 1.0)
	canvas.scroll_offset = bounds.position * canvas.zoom - Vector2(40, 80)

func default_task_id() -> String:
	return bound_task_id if not bound_task_id.is_empty() else "meet_receptionist"

func _show_parameters() -> void:
	if graph != null:
		var selected: Dictionary = graph.node_by_id(selected_id)
		if not selected.is_empty() and preload("res://addons/godot_level_editor_mechanisms/task_nodes.gd").DEFINITIONS.has(selected.kind):
			preload("res://addons/godot_level_editor_mechanisms/task_parameters.gd").draw(self, selected)
			return
	super._show_parameters()
	if not bound_task_id.is_empty() and _fields.has("task") and _fields.task is LineEdit: _fields.task.editable = false
