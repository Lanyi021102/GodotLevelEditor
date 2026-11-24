@tool
extends VBoxContainer
signal edit_task_requested(task: Dictionary)
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const IDENTITY_COLORS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/identity_colors.gd")
var workbook_path := CATALOG.PATH
var catalog: Resource
var table: Tree
var status: Label
var menu: PopupMenu
var form: ConfirmationDialog
var confirm_delete: ConfirmationDialog
var fields: Dictionary = {}
var _creating_task := false
var _form_event_id := ""
var _form_task_id := ""
var form_error: Label
var _levels: Resource
var selected_id := ""
var selected_kind := "event"
var dirty := false
var undo := UndoRedo.new()
func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	_button(bar, "新建事件", add_event)
	_button(bar, "展开全部", func(): _collapse(false))
	_button(bar, "收起全部", func(): _collapse(true))
	_button(bar, "撤销", func(): undo.undo())
	_button(bar, "重做", func(): undo.redo())
	_button(bar, "重新读取配表", reload_book)
	table = Tree.new()
	table.columns = 6
	table.hide_root = true
	table.column_titles_visible = true
	table.select_mode = Tree.SELECT_ROW
	table.allow_rmb_select = true
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in 6:
		table.set_column_title(i, ["事件 / 任务 ID", "名称", "中文名", "所属关卡", "备注", "操作"][i])
		table.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		table.set_column_custom_minimum_width(i, [175, 200, 240, 240, 260, 90][i])
		table.set_column_expand(i, i in [2, 3, 4])
	var font := table.get_theme_font("font", "Tree")
	var font_size := table.get_theme_font_size("font_size", "Tree")
	for i in [0, 1, 5]:
		var sample: String = ["事件 / 任务 ID", "task_1001001", "", "", "", "编辑任务图"][i]
		table.set_column_custom_minimum_width(i, int(font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + (72 if i == 0 else 36))
	add_child(table)
	table.item_selected.connect(_selected)
	table.item_activated.connect(edit_selected)
	table.gui_input.connect(_context_input)
	var hint := Label.new()
	hint.text = "右键管理事件与任务 · 双击修改信息 · 编辑按钮打开任务图 · ID 固定，顺序独立"
	hint.hide()
	add_child(hint)
	var footer := HBoxContainer.new()
	add_child(footer)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(status)
	_button(footer, "保存事件与任务", save)
	menu = PopupMenu.new()
	menu.id_pressed.connect(_action)
	add_child(menu)
	confirm_delete = ConfirmationDialog.new()
	confirm_delete.title = "删除事件／任务"
	confirm_delete.confirmed.connect(delete_selected)
	add_child(confirm_delete)
	form = ConfirmationDialog.new()
	form.hide()
	form.force_native = true
	form.transient = true
	form.exclusive = true
	form.dialog_hide_on_ok = false
	form.min_size = Vector2i(620, 540)
	form.confirmed.connect(apply_form)
	add_child(form)
	reload_book()
func _button(parent: Node, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
func reload_book(discard_draft := false) -> void:
	if dirty and not discard_draft: status.text = "当前有未保存修改，请先保存或撤销。"; return
	var result := CATALOG.load_book(workbook_path)
	if not result.errors.is_empty():
		status.text = "; ".join(result.errors)
		if catalog == null: catalog = CATALOG.new(); _refresh()
		return
	catalog = result.catalog
	dirty = false
	undo.clear_history()
	_refresh()
func _apply(state: Dictionary) -> void:
	catalog.apply_snapshot(state)
	dirty = true
	_refresh()
func _commit(title: String, before: Dictionary) -> void:
	var after: Dictionary = catalog.snapshot()
	if before == after: return
	undo.create_action(title)
	undo.add_do_method(_apply.bind(after))
	undo.add_undo_method(_apply.bind(before))
	undo.commit_action()
func add_event() -> void:
	var before: Dictionary = catalog.snapshot()
	var event: Dictionary = catalog.add_event()
	selected_id = event.event_id
	selected_kind = "event"
	_commit("新建事件", before)
func add_task() -> void:
	var event_id := selected_id if selected_kind == "event" else str(catalog.task_by_id(selected_id).get("event_id", ""))
	if catalog.event_by_id(event_id).is_empty(): return
	_creating_task = true
	_form_event_id = event_id
	_form_task_id = ""
	_build_form({"task_id": catalog.next_task_id(event_id), "name": "", "display_name": "", "notes": "", "level_id": ""}, false)
func _selected() -> void:
	var item := table.get_selected()
	if item == null: return
	selected_id = str(item.get_metadata(0))
	selected_kind = str(item.get_metadata(1))
func _refresh() -> void:
	_levels = CATALOG.LEVELS.load_book().catalog
	var font := table.get_theme_font("font", "Tree")
	var font_size := table.get_theme_font_size("font_size", "Tree")
	var name_width := 200.0
	for row in catalog.events + catalog.tasks:
		name_width = maxf(name_width, font.get_string_size(str(row.name), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 48)
	table.set_column_custom_minimum_width(1, int(name_width))
	var collapsed := {}
	if table.get_root() != null:
		for item in table.get_root().get_children(): collapsed[str(item.get_metadata(0))] = item.collapsed
	table.clear()
	var root := table.create_item()
	for event in catalog.events:
		var parent := table.create_item(root)
		_fill(parent, event, "event")
		parent.collapsed = bool(collapsed.get(str(event.event_id), false))
		for task in catalog.event_tasks(event.event_id): _fill(table.create_item(parent), task, "task")
	status.text = "未保存" if dirty else ""
func _fill(item: TreeItem, data: Dictionary, kind: String) -> void:
	var id := str(data.event_id if kind == "event" else data.task_id)
	item.set_metadata(0, id)
	item.set_metadata(1, kind)
	item.set_text(0, id)
	item.set_text(1, str(data.name))
	item.set_tooltip_text(1, str(data.name))
	item.set_text(2, str(data.display_name))
	item.set_text(3, _level_caption(data, kind))
	item.set_tooltip_text(3, item.get_text(3))
	item.set_text(4, str(data.notes))
	item.set_custom_minimum_height(44)
	item.set_cell_mode(5, TreeItem.CELL_MODE_CUSTOM)
	item.set_custom_as_button(5, true)
	if kind == "event":
		for i in 6: item.set_custom_bg_color(i, Color(0.3, 0.5, 0.7, 0.12))
		item.set_tooltip_text(0, "开始条件：" + str(data.start_type) + " " + str(data.start_key))
		item.set_text(5, "添加任务")
	else:
		item.set_text(5, "编辑任务图")
		item.set_tooltip_text(5, "编辑任务图（不存在则新建）")
	var level_ids: Array[String] = []
	var tasks: Array = [data] if kind == "task" else catalog.event_tasks(str(data.event_id))
	for task in tasks:
		var level_id := str(task.get("level_id", ""))
		if not level_id.is_empty() and not level_ids.has(level_id): level_ids.append(level_id)
	level_ids.sort()
	if not level_ids.is_empty(): IDENTITY_COLORS.apply(item, 3, "level:" + "|".join(level_ids))
	if id == selected_id: item.select(0)
func _context_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index == MOUSE_BUTTON_LEFT and table.get_column_at_position(event.position) == 5:
		var action_item := table.get_item_at_position(event.position)
		if action_item != null and not event.double_click:
			action_item.select(0)
			selected_id = str(action_item.get_metadata(0))
			selected_kind = str(action_item.get_metadata(1))
			if selected_kind == "event": add_task()
			else: edit_selected()
			table.accept_event()
		return
	if event.button_index != MOUSE_BUTTON_RIGHT: return
	var item := table.get_item_at_position(event.position)
	if item != null: item.select(0); _selected()
	menu.clear()
	menu.add_item("新建事件", 1)
	if item != null:
		menu.add_item("新建任务", 2)
		menu.add_separator()
		menu.add_item("编辑信息／开始条件…" if selected_kind == "event" else "编辑任务信息…", 3)
		if selected_kind == "task": menu.add_item("编辑任务图…", 4)
		menu.add_item("复制事件／任务", 5)
		menu.add_item("删除事件／任务…", 6)
		menu.add_separator()
		menu.add_item("上移", 7)
		menu.add_item("下移", 8)
		menu.add_item("复制 ID", 9)
	menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))
	get_viewport().set_input_as_handled()
func _action(action: int) -> void:
	match action:
		1: add_event()
		2: add_task()
		3: show_form()
		4: edit_selected()
		5: duplicate_selected()
		6:
			confirm_delete.dialog_text = "删除当前事件及其全部任务？任务图文件将保留。" if selected_kind == "event" else "删除当前任务？任务图文件将保留。"
			confirm_delete.popup_centered()
		7: move_selected(-1)
		8: move_selected(1)
		9: DisplayServer.clipboard_set(selected_id)
func edit_selected() -> void:
	if selected_kind == "event": show_form(); return
	var task: Dictionary = catalog.task_by_id(selected_id)
	if not task.is_empty(): edit_task_requested.emit(task)
func _level_caption(data: Dictionary, kind: String) -> String:
	var labels: Array[String] = []
	var tasks: Array = [data] if kind == "task" else catalog.event_tasks(str(data.event_id))
	for task in tasks:
		var level: Dictionary = _levels.by_id(str(task.get("level_id", ""))) if _levels != null else {}
		var text := str(level.get("display_name", "未指定"))
		if not labels.has(text): labels.append(text)
	return "、".join(labels) if not labels.is_empty() else "—"
func show_form() -> void:
	_creating_task = false
	_form_task_id = selected_id
	var data: Dictionary = catalog.event_by_id(selected_id) if selected_kind == "event" else catalog.task_by_id(selected_id)
	if data.is_empty(): return
	_build_form(data, selected_kind == "event")
func _build_form(data: Dictionary, is_event: bool) -> void:
	for child in form.get_children():
		if child is VBoxContainer: child.free()
	fields.clear()
	form.title = "新建任务" if _creating_task else "事件信息" if is_event else "任务信息"
	var box := VBoxContainer.new()
	form.add_child(box)
	for key in ["id", "name", "display_name", "notes"]:
		var label := Label.new()
		label.text = {"id": "事件 ID" if is_event else "任务 ID", "name": "事件名" if is_event else "任务名", "display_name": "事件中文名" if is_event else "任务中文名", "notes": "备注"}[key]
		box.add_child(label)
		var field := LineEdit.new()
		field.text = str(data.get("event_id" if is_event else "task_id", "")) if key == "id" else str(data.get(key, ""))
		field.editable = key != "id"
		box.add_child(field)
		fields[key] = field
	if is_event:
		var label := Label.new()
		label.text = "开始条件"
		box.add_child(label)
		var field := OptionButton.new()
		for i in CATALOG.START_TYPES.size():
			field.add_item(["程序调用（手动）", "玩家进入房间", "收到指定事件", "游戏开始"][i])
			if CATALOG.START_TYPES[i] == data.start_type: field.select(i)
		box.add_child(field)
		fields.start_type = field
		var key := LineEdit.new()
		key.placeholder_text = "房间 ID / 接收事件名称"
		key.text = str(data.start_key)
		box.add_child(key)
		fields.start_key = key
	else:
		var label := Label.new()
		label.text = "绑定关卡"
		box.add_child(label)
		var picker := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_picker.gd").new()
		box.add_child(picker)
		picker.select_id(str(data.get("level_id", "")))
		fields.level_id = picker
		picker.selection_changed.connect(func(_id: String):
			if is_instance_valid(form_error): form_error.text = "")
	form_error = Label.new()
	form_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(form_error)
	form.popup_centered()
func apply_form() -> void:
	var is_event := not fields.has("level_id")
	if fields.name.text.strip_edges().is_empty() or fields.display_name.text.strip_edges().is_empty():
		form_error.text = "请填写名称和中文名。"; return
	if not is_event and fields.level_id.value().is_empty():
		form_error.text = "请选择一个关卡。"; return
	var before: Dictionary = catalog.snapshot()
	var data: Dictionary
	if _creating_task:
		data = catalog.add_task(_form_event_id, fields.level_id.value())
		selected_id = str(data.task_id)
		selected_kind = "task"
	else:
		data = catalog.event_by_id(_form_task_id) if is_event else catalog.task_by_id(_form_task_id)
	if data.is_empty(): return
	for key in fields:
		if key == "id": continue
		data[key] = CATALOG.START_TYPES[fields[key].selected] if key == "start_type" else fields[key].value() if key == "level_id" else fields[key].text.strip_edges()
	var errors: PackedStringArray = catalog.validate()
	if not errors.is_empty():
		catalog.apply_snapshot(before)
		form_error.text = "; ".join(errors)
		return
	_commit("新建任务" if _creating_task else "修改事件／任务信息", before)
	form.hide()
func delete_selected() -> void:
	var before: Dictionary = catalog.snapshot()
	if selected_kind == "event":
		catalog.events.assign(catalog.events.filter(func(event: Dictionary): return str(event.event_id) != selected_id))
		catalog.tasks.assign(catalog.tasks.filter(func(task: Dictionary): return str(task.event_id) != selected_id))
	else: catalog.tasks.assign(catalog.tasks.filter(func(task: Dictionary): return str(task.task_id) != selected_id))
	_normalize_orders()
	_commit("删除事件／任务", before)
func move_selected(direction: int) -> void:
	var before: Dictionary = catalog.snapshot()
	var items: Array = catalog.events if selected_kind == "event" else catalog.event_tasks(str(catalog.task_by_id(selected_id).get("event_id", "")))
	for i in items.size():
		if str(items[i].get("event_id" if selected_kind == "event" else "task_id")) != selected_id: continue
		var target := i + direction
		if target < 0 or target >= items.size(): return
		var temp: Dictionary = items[i]
		items[i] = items[target]
		items[target] = temp
		for j in items.size(): items[j].order = j
		if selected_kind == "event": catalog.events.assign(items)
		break
	_commit("调整执行顺序（ID 保持）", before)
func _normalize_orders() -> void:
	for i in catalog.events.size():
		catalog.events[i].order = i
		var children: Array = catalog.event_tasks(catalog.events[i].event_id)
		for j in children.size(): children[j].order = j
func duplicate_selected() -> void:
	var before: Dictionary = catalog.snapshot()
	if selected_kind == "event":
		var source: Dictionary = catalog.event_by_id(selected_id).duplicate(true)
		var children: Array = catalog.event_tasks(selected_id).duplicate(true)
		var event: Dictionary = catalog.add_event()
		event.display_name = str(source.display_name) + " 副本"
		event.notes = source.notes
		event.start_type = source.start_type
		event.start_key = source.start_key
		for child in children:
			var task: Dictionary = catalog.add_task(event.event_id, str(child.get("level_id", "")))
			_copy_task(child, task)
		selected_id = event.event_id
	else:
		var source: Dictionary = catalog.task_by_id(selected_id).duplicate(true)
		var task: Dictionary = catalog.add_task(source.event_id, str(source.get("level_id", "")))
		_copy_task(source, task)
		selected_id = task.task_id
	_commit("复制事件／任务（新 ID）", before)
func _copy_task(source: Dictionary, target: Dictionary) -> void:
	target.display_name = str(source.display_name) + " 副本"
	target.notes = source.notes
	target.level_id = source.level_id
	if FileAccess.file_exists(str(source.graph_path)):
		var graph: Resource = load(str(source.graph_path)).duplicate(true)
		graph.graph_id = "task_" + str(target.task_id)
		for node in graph.nodes:
			if node.get("params", {}).get("task") == source.task_id: node.params.task = str(target.task_id)
		ResourceSaver.save(graph, str(target.graph_path))
func _collapse(collapsed: bool) -> void:
	for item in table.get_root().get_children(): item.collapsed = collapsed
func save() -> void:
	var errors: PackedStringArray = catalog.save_book(workbook_path)
	if not errors.is_empty():
		status.text = "; ".join(errors)
		if CATALOG.XLSX.CONFLICT in errors and not has_node("WorkbookConflict"):
			var conflict := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/workbook_conflict.gd").new()
			conflict.name = "WorkbookConflict"
			conflict.offer(self, reload_book.bind(true), _save_draft_copy)
		return
	dirty = false
	_refresh()
	status.text = "已保存"

func _save_draft_copy() -> void:
	var file := EditorFileDialog.new()
	file.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file.add_filter("*.xlsx", "事件与任务配表")
	add_child(file)
	file.current_path = workbook_path.get_basename() + "_copy.xlsx"
	file.file_selected.connect(func(path: String):
		if path == workbook_path: status.text = "请选择新的文件名。"; return
		var original: Dictionary = catalog.workbook_origin.duplicate()
		var errors: PackedStringArray = catalog.save_book(path)
		catalog.workbook_origin = original
		status.text = "已另存草稿：" + path if errors.is_empty() else "; ".join(errors))
	file.visibility_changed.connect(func():
		if not file.visible: file.queue_free())
	file.popup_centered_ratio(0.7)
func _exit_tree() -> void:
	undo.clear_history()
	undo.free()
