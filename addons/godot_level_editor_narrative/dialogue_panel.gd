@tool
extends VBoxContainer
const LIBRARY := preload("res://addons/godot_level_editor_narrative/runtime/dialogue_library.gd")
var library: Resource
var undo := UndoRedo.new()
var groups: ItemList
var comments: ItemList
var table: Tree
var status: Label
var selection_title: Label
var search: LineEdit
var file: EditorFileDialog
var menu: PopupMenu
var insert_menu: PopupMenu
var rename_dialog: ConfirmationDialog
var rename_field: LineEdit
var delete_dialog: ConfirmationDialog
var detail_dialog: ConfirmationDialog
var detail_speaker: LineEdit
var detail_content: TextEdit
var detail_type: OptionButton
var detail_duration: SpinBox
var detail_color: ColorPickerButton
var speaker_options: OptionButton
var gi := -1
var ci := -1
var li := -1
var dirty := false
var export_dirty := false
var _mode := "open"
var _context := "group"
var _building := false
var _selection_before := Vector3i(-1, -1, -1)
var _detail_target: Dictionary = {}

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	add_child(bar)
	_button(bar, "打开对白", _open)
	_button(bar, "新建台本", _new)
	_button(bar, "撤销", func(): undo.undo())
	_button(bar, "重做", func(): undo.redo())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	search = LineEdit.new()
	search.placeholder_text = "搜索 ID / NPC / 内容"
	search.custom_minimum_size.x = 310
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String): _refresh_table())
	bar.add_child(search)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var groups_box := _column(split, "对话组", 170)
	groups = _list(groups_box)
	groups.item_selected.connect(func(i: int): gi = i; ci = 0; li = 0; search.clear(); _refresh())
	groups.gui_input.connect(_context_input.bind("group"))
	var content_split := HSplitContainer.new()
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(content_split)
	var comments_box := _column(content_split, "Comments", 195)
	comments = _list(comments_box)
	comments.item_selected.connect(func(i: int): ci = i; li = 0; search.clear(); _refresh())
	comments.gui_input.connect(_context_input.bind("comment"))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.add_child(right)
	selection_title = Label.new()
	selection_title.add_theme_font_size_override("font_size", 17)
	right.add_child(selection_title)
	table = Tree.new()
	table.columns = 3
	table.hide_root = true
	table.column_titles_visible = true
	table.set_column_title(0, "对话 ID")
	table.set_column_title(1, "NPC 姓名")
	table.set_column_title(2, "对话内容")
	table.set_column_expand(0, false)
	table.set_column_custom_minimum_width(0, 135)
	table.set_column_expand(1, false)
	table.set_column_custom_minimum_width(1, 140)
	table.set_column_expand(2, true)
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.allow_rmb_select = true
	table.select_mode = Tree.SELECT_ROW
	for column in 3: table.set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_LEFT)
	var dark := get_theme_color("font_color", "Label").get_luminance() > 0.5
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("22262d") if dark else Color("f8f9fb")
	panel_style.border_color = Color("454b55") if dark else Color("c9cdd4")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	table.add_theme_stylebox_override("panel", panel_style)
	table.draw.connect(_draw_table_grid)
	table.add_theme_constant_override("v_separation", 14)
	table.add_theme_constant_override("h_separation", 14)
	right.add_child(table)
	table.item_selected.connect(func():
		if table.get_selected() != null: li = int(table.get_selected().get_metadata(0)))
	table.item_activated.connect(edit_line)
	table.gui_input.connect(_context_input.bind("line"))
	var hint := Label.new()
	hint.text = "右键管理分组与对白 · 双击对白查看详情 · ID 自动分配"
	hint.add_theme_color_override("font_color", get_theme_color("font_disabled_color", "Label"))
	hint.hide()
	add_child(hint)
	var footer := HBoxContainer.new()
	add_child(footer)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(status)
	_button(footer, "保存对白", save)
	_button(footer, "导出对白…", export_dialogues)
	file = EditorFileDialog.new()
	file.file_selected.connect(_file_selected)
	add_child(file)
	menu = PopupMenu.new()
	menu.id_pressed.connect(_menu_action)
	add_child(menu)
	insert_menu = PopupMenu.new()
	insert_menu.name = "InsertMenu"
	insert_menu.add_item("在当前行之前", 20)
	insert_menu.add_item("在当前行之后", 21)
	insert_menu.id_pressed.connect(_menu_action)
	menu.add_child(insert_menu)
	rename_dialog = ConfirmationDialog.new()
	rename_dialog.title = "重命名"
	rename_field = LineEdit.new()
	rename_field.custom_minimum_size.x = 340
	rename_dialog.add_child(rename_field)
	rename_dialog.confirmed.connect(func(): rename_selected(rename_field.text))
	rename_field.text_submitted.connect(func(_text: String): rename_selected(rename_field.text); rename_dialog.hide())
	add_child(rename_dialog)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "删除所选内容"
	delete_dialog.confirmed.connect(delete_selected)
	add_child(delete_dialog)
	_build_details()
	var initial := LIBRARY.read_xlsx("res://配表/dialogues.xlsx")
	if initial.errors.is_empty(): open_library(initial.library)
	else: open_library(load("res://resources/narrative/reception.dialogue.tres"))

func _button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)

func _column(parent: Node, title: String, width: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	parent.add_child(column)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 17)
	column.add_child(label)
	return column

func _list(parent: Node) -> ItemList:
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.allow_rmb_select = true
	list.add_theme_constant_override("v_separation", 14)
	parent.add_child(list)
	return list

func open_library(source: Resource) -> void:
	if source == null or source.get_script() != LIBRARY: return
	if dirty:
		status.text = "请先保存当前对白，再切换台本。"
		return
	var candidate: Resource = source.duplicate(true)
	candidate.set_meta("source_path", source.xlsx_path if source.resource_path.is_empty() else source.resource_path)
	var migrated: bool = candidate.migrate_legacy()
	if candidate.schema_version != LIBRARY.VERSION:
		status.text = "不支持的台本版本。"
		return
	library = candidate
	undo.clear_history()
	gi = 0 if not library.groups.is_empty() else -1
	ci = 0
	li = 0
	dirty = migrated
	export_dirty = migrated
	var exported_path: String = library.xlsx_path if not library.xlsx_path.is_empty() else source.resource_path.get_basename() + ".xlsx"
	var exported: Dictionary = LIBRARY.read_xlsx(exported_path)
	if exported.library == null or exported.library.export_signature() != library.export_signature(): export_dirty = true
	_refresh()

func _state() -> Dictionary:
	return {"speakers": library.speakers.duplicate(), "groups": library.groups.duplicate(true), "selection": _selection_before}

func _apply(state: Dictionary) -> void:
	library.speakers = state.speakers.duplicate()
	library.groups.assign(state.groups.duplicate(true))
	var selected: Vector3i = state.get("selection", Vector3i(gi, ci, li))
	gi = selected.x
	ci = selected.y
	li = selected.z
	dirty = true
	export_dirty = true
	_refresh()

func _commit(title: String, after: Dictionary) -> void:
	var before := _state()
	after["selection"] = Vector3i(gi, ci, li)
	if before == after: return
	undo.create_action(title)
	undo.add_do_method(_apply.bind(after))
	undo.add_undo_method(_apply.bind(before))
	undo.commit_action()

func current_comment() -> Dictionary:
	if gi < 0 or ci < 0 or gi >= library.groups.size() or ci >= library.groups[gi].comments.size(): return {}
	return library.groups[gi].comments[ci]

func _new_line(speaker := "旁白") -> Dictionary:
	library.match_speaker(speaker)
	return {"id": library.allocate_line_id(), "speaker": speaker, "text": "新的对白", "type": "对白", "duration": 0.0}

func add_group() -> void:
	var line := _new_line()
	var after := _state()
	after.groups.append({"id": LIBRARY.fresh_id("group"), "name": "新对话组", "comments": [{"id": LIBRARY.fresh_id("comment"), "name": "进入", "lines": [line]}]})
	gi = after.groups.size() - 1
	ci = 0
	li = 0
	_commit("新建对话组", after)

func add_comment() -> void:
	if gi < 0: return
	var line := _new_line()
	var after := _state()
	after.groups[gi].comments.append({"id": LIBRARY.fresh_id("comment"), "name": "新 comment", "lines": [line]})
	ci = after.groups[gi].comments.size() - 1
	li = 0
	_commit("新建 comment", after)

func add_line(at := -1) -> void:
	var comment := current_comment()
	if comment.is_empty(): return
	var name_text := str(comment.lines.back().speaker) if not comment.lines.is_empty() else "旁白"
	var line := _new_line(name_text)
	var after := _state()
	var target: Array = after.groups[gi].comments[ci].lines
	li = target.size() if at < 0 else clampi(at, 0, target.size())
	target.insert(li, line)
	_commit("新建对白", after)

func _context_input(event: InputEvent, kind: String) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed: return
	_context = kind
	var picked := false
	if kind == "group":
		var index := groups.get_item_at_position(event.position, true)
		if index >= 0: gi = index; ci = 0; li = 0; picked = true
	elif kind == "comment":
		var index := comments.get_item_at_position(event.position, true)
		if index >= 0: ci = index; li = 0; picked = true
	else:
		var item := table.get_item_at_position(event.position)
		if item != null: li = int(item.get_metadata(0)); picked = true
	_refresh()
	_show_context(kind, picked)
	get_viewport().set_input_as_handled()

func _show_context(kind: String, include_selected := true) -> void:
	_context = kind
	menu.clear()
	if kind == "group": menu.add_item("新建对话组", 1)
	elif kind == "comment": menu.add_item("新建 comment", 2)
	else:
		menu.add_item("新建对白", 3)
		menu.add_submenu_item("插入对白", "InsertMenu")
	var has_selection: bool = gi >= 0 if kind == "group" else not current_comment().is_empty() if kind == "comment" else li >= 0 and li < current_comment().get("lines", []).size()
	if has_selection and include_selected:
		menu.add_separator()
		menu.add_item("编辑对白详情…" if kind == "line" else "重命名…", 4)
		menu.add_item("复制" + {"group": "对话组", "comment": " comment", "line": "对白"}[kind], 5)
		menu.add_item("删除" + {"group": "对话组…", "comment": " comment…", "line": "对白…"}[kind], 6)
		menu.add_separator()
		menu.add_item("上移", 7)
		menu.add_item("下移", 8)
		menu.add_item("复制 ID", 9)
	menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))

func _menu_action(id: int) -> void:
	match id:
		1: add_group()
		2: add_comment()
		3: add_line()
		4:
			if _context == "line": edit_line()
			else:
				rename_field.text = str(library.groups[gi].name if _context == "group" else current_comment().name)
				rename_dialog.popup_centered()
				rename_field.grab_focus()
				rename_field.select_all()
		5: duplicate_selected()
		6:
			delete_dialog.dialog_text = "删除当前%s及其包含的内容？可通过撤销恢复。" % {"group": "对话组", "comment": " comment", "line": "对白"}[_context]
			delete_dialog.popup_centered()
		7: move_selected(-1)
		8: move_selected(1)
		9:
			var id_text := str(library.groups[gi].id if _context == "group" else current_comment().id if _context == "comment" else current_comment().lines[li].id)
			DisplayServer.clipboard_set(id_text)
		20: add_line(li)
		21: add_line(li + 1)

func rename_selected(name_text: String) -> void:
	if gi < 0 or name_text.strip_edges().is_empty(): return
	var after := _state()
	if _context == "group": after.groups[gi].name = name_text.strip_edges()
	elif ci >= 0: after.groups[gi].comments[ci].name = name_text.strip_edges()
	_commit("重命名", after)

func delete_selected() -> void:
	if gi < 0: return
	var after := _state()
	if _context == "group": after.groups.remove_at(gi)
	elif _context == "comment" and ci >= 0: after.groups[gi].comments.remove_at(ci)
	elif _context == "line" and li >= 0: after.groups[gi].comments[ci].lines.remove_at(li)
	_commit("删除所选内容", after)

func duplicate_selected() -> void:
	if gi < 0: return
	var after := _state()
	if _context == "line" and li >= 0:
		var line: Dictionary = current_comment().lines[li].duplicate(true)
		line.id = library.allocate_line_id()
		after.groups[gi].comments[ci].lines.insert(li + 1, line)
		li += 1
	elif _context == "comment" and ci >= 0:
		var comment: Dictionary = current_comment().duplicate(true)
		_remap_comment(comment)
		comment.name += " 副本"
		after.groups[gi].comments.insert(ci + 1, comment)
		ci += 1
	elif _context == "group":
		var group: Dictionary = library.groups[gi].duplicate(true)
		group.id = LIBRARY.fresh_id("group")
		group.name += " 副本"
		for comment in group.comments: _remap_comment(comment)
		after.groups.insert(gi + 1, group)
		gi += 1
	_commit("复制所选内容（新 ID）", after)

func _remap_comment(comment: Dictionary) -> void:
	comment.id = LIBRARY.fresh_id("comment")
	for line in comment.lines: line.id = library.allocate_line_id()

func move_selected(direction: int) -> void:
	if gi < 0: return
	var after := _state()
	var list: Array = after.groups if _context == "group" else after.groups[gi].comments if _context == "comment" else after.groups[gi].comments[ci].lines
	var index := gi if _context == "group" else ci if _context == "comment" else li
	var next := index + direction
	if index < 0 or next < 0 or next >= list.size(): return
	var item: Dictionary = list.pop_at(index)
	list.insert(next, item)
	if _context == "group": gi = next
	elif _context == "comment": ci = next
	else: li = next
	_commit("移动所选内容", after)

func _refresh() -> void:
	_building = true
	groups.clear()
	comments.clear()
	gi = clampi(gi, 0, library.groups.size() - 1) if not library.groups.is_empty() else -1
	for group in library.groups:
		groups.add_item(str(group.name))
		groups.set_item_tooltip(groups.item_count - 1, str(group.id))
	if gi >= 0:
		groups.select(gi)
		var list: Array = library.groups[gi].comments
		ci = clampi(ci, 0, list.size() - 1) if not list.is_empty() else -1
		for i in list.size():
			comments.add_item("%d  %s" % [i + 1, list[i].name])
			comments.set_item_tooltip(i, "触发 ID：" + str(list[i].id))
		if ci >= 0: comments.select(ci)
	else: ci = -1
	_building = false
	_selection_before = Vector3i(gi, ci, li)
	_refresh_table()
	status.text = "未保存" if dirty else ""

func _refresh_table() -> void:
	if table == null or library == null: return
	_building = true
	table.clear()
	var root := table.create_item()
	var comment := current_comment()
	selection_title.text = "选择对话组和 comment"
	if not comment.is_empty():
		selection_title.text = str(library.groups[gi].name) + "  /  " + str(comment.name)
		li = mini(li, comment.lines.size() - 1)
		for i in comment.lines.size():
			var line: Dictionary = comment.lines[i]
			if not search.text.is_empty() and not (str(line.id) + str(line.speaker) + str(line.text)).to_lower().contains(search.text.to_lower()): continue
			var item := table.create_item(root)
			item.set_metadata(0, i)
			item.set_text(0, str(line.id))
			item.set_text(1, str(line.speaker))
			item.set_text(2, str(line.text).replace("\n", " ↵ "))
			item.set_custom_minimum_height(46)
			item.set_tooltip_text(0, "自动分配的稳定 ID，复制时生成新 ID")
			item.set_tooltip_text(1, "双击打开编辑；同名 NPC 自动匹配颜色")
			item.set_tooltip_text(2, str(line.text) + "\n\n双击打开完整编辑；" + str(line.type) + " · " + ("自动时长" if float(line.get("duration", 0)) == 0 else str(line.duration) + " 秒"))
			if i == li: item.select(0)
	_building = false

func _draw_table_grid() -> void:
	var color := Color(0.5, 0.53, 0.58, 0.3)
	var x := 1.0
	for column in 2:
		x += table.get_column_width(column)
		table.draw_line(Vector2(x, 0), Vector2(x, table.size.y), color)
	var root := table.get_root()
	if root == null: return
	var item := root.get_first_child()
	while item != null:
		var rect := table.get_item_area_rect(item)
		if rect.end.y > 0 and rect.end.y < table.size.y:
			table.draw_line(Vector2(1, rect.end.y + 4), Vector2(table.size.x - 1, rect.end.y + 4), color)
		item = item.get_next()

func _build_details() -> void:
	detail_dialog = ConfirmationDialog.new()
	detail_dialog.title = "编辑对白"
	detail_dialog.min_size = Vector2i(620, 440)
	add_child(detail_dialog)
	var box := VBoxContainer.new()
	detail_dialog.add_child(box)
	detail_speaker = LineEdit.new()
	detail_speaker.placeholder_text = "NPC 姓名（新角色自动配色）"
	box.add_child(detail_speaker)
	speaker_options = OptionButton.new()
	box.add_child(speaker_options)
	speaker_options.item_selected.connect(func(i: int): detail_speaker.text = speaker_options.get_item_text(i); _detail_match())
	detail_speaker.text_changed.connect(func(_text: String): _detail_match())
	detail_color = ColorPickerButton.new()
	detail_color.custom_minimum_size.y = 30
	detail_color.tooltip_text = "NPC 颜色，同名角色共用"
	box.add_child(detail_color)
	detail_content = TextEdit.new()
	detail_content.custom_minimum_size.y = 210
	detail_content.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(detail_content)
	var row := HBoxContainer.new()
	box.add_child(row)
	detail_type = OptionButton.new()
	for name_text in LIBRARY.TYPES: detail_type.add_item(name_text)
	row.add_child(detail_type)
	detail_duration = SpinBox.new()
	detail_duration.max_value = 3600
	detail_duration.step = 0.1
	detail_duration.prefix = "显示秒数 "
	detail_duration.tooltip_text = "0：根据字数自动安排阅读时间；大于 0：固定秒数。只播放当前 comment。"
	row.add_child(detail_duration)
	var hint := Label.new()
	hint.text = "0 秒＝按字数自动播放"
	hint.hide()
	row.add_child(hint)
	detail_dialog.confirmed.connect(_apply_details)

func edit_line() -> void:
	var comment := current_comment()
	if comment.is_empty() or li < 0 or li >= comment.lines.size(): return
	var line: Dictionary = comment.lines[li]
	_detail_target = {"group": gi, "comment": ci, "id": line.id}
	detail_dialog.title = "编辑对白 · " + str(line.id)
	detail_speaker.text = line.speaker
	_detail_match()
	speaker_options.clear()
	for name_text in library.speakers:
		speaker_options.add_item(name_text)
		if name_text == line.speaker: speaker_options.select(speaker_options.item_count - 1)
	detail_content.text = line.text
	detail_type.select(maxi(0, LIBRARY.TYPES.find(line.type)))
	detail_duration.value = float(line.get("duration", 0.0))
	detail_dialog.popup_centered()
	detail_content.grab_focus()

func _detail_match() -> void:
	detail_color.color = library.speakers.get(detail_speaker.text, Color.from_hsv(float(absi(detail_speaker.text.hash()) % 360) / 360.0, 0.42, 0.95))

func _apply_details() -> void:
	if _detail_target.is_empty() or detail_speaker.text.strip_edges().is_empty() or detail_content.text.strip_edges().is_empty():
		status.text = "NPC 姓名和对白内容不能为空。"
		return
	var after := _state()
	for line in after.groups[_detail_target.group].comments[_detail_target.comment].lines:
		if line.id != _detail_target.id: continue
		line.speaker = detail_speaker.text.strip_edges()
		line.text = detail_content.text
		line.type = detail_type.get_item_text(detail_type.selected)
		line.duration = detail_duration.value
		after.speakers[line.speaker] = detail_color.color
	_commit("编辑对白详情", after)

func save() -> void:
	if library.xlsx_path.is_empty(): _choose("save"); return
	export_to(library.xlsx_path)

func export_dialogues() -> void: _choose("export")

func export_to(path: String) -> bool:
	var errors: PackedStringArray = library.write_xlsx(path)
	if not errors.is_empty(): status.text = "; ".join(errors); return false
	library.xlsx_path = path
	library.set_meta("source_path", path)
	dirty = false
	export_dirty = false
	status.text = "已保存全部对白：" + path.get_file()
	return true

func _open() -> void:
	if dirty: status.text = "请先保存当前对白。"; return
	_choose("open")

func _new() -> void:
	if dirty: status.text = "请先保存当前对白。"; return
	var source := LIBRARY.new()
	source.xlsx_path = ""
	open_library(source)
	add_group()

func _choose(mode: String) -> void:
	_mode = mode
	file.clear_filters()
	if mode == "open":
		file.add_filter("*.xlsx,*.tres", "XLSX 配表 / 旧版台本迁移")
		file.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	else:
		file.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		file.add_filter("*.xlsx", "对白 XLSX")
		var source_path := str(library.get_meta("source_path", ""))
		file.current_path = (library.xlsx_path if not library.xlsx_path.is_empty() else source_path.get_basename() + ".xlsx" if not source_path.is_empty() else "res://配表/new_dialogues.xlsx") if mode == "export" else "res://配表/new_dialogues.xlsx"
	file.popup_centered_ratio(0.7)

func _file_selected(path: String) -> void:
	if _mode == "export": export_to(path)
	elif _mode == "save": library.set_meta("source_path", path); save()
	elif path.get_extension().to_lower() == "csv":
		var result := LIBRARY.read_xlsx(path)
		if not result.errors.is_empty(): status.text = "; ".join(result.errors); return
		open_library(result.library)
	else: open_library(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE))

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed or event.meta_pressed:
		if event.keycode == KEY_S: save(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Z:
			if event.shift_pressed: undo.redo()
			else: undo.undo()
			get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if get_meta("godot_level_editor_reparenting", false): return
	undo.clear_history()
	undo.free()
