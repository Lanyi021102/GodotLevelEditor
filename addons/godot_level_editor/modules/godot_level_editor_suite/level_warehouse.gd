@tool
extends VBoxContainer
signal levels_changed
signal level_created(scene_path: String)
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const SPAWN := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/spawn_marker.gd")
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")
const LEVEL_CARD := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_card.gd")
const SKY_LIBRARY := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/library.gd")
var module: EditorPlugin
var catalog: Resource
var workbook_path := LEVELS.PATH
var logic_panel: Control
var mode_bar: HBoxContainer
var mode_buttons: Dictionary = {}
var mode_stack: TabContainer
var catalog_grid: GridContainer
var detail: VBoxContainer
var detail_cover: TextureRect
var detail_title: Label
var detail_info: Label
var detail_notes: Label
var level_heading: Label
var delete_dialog: ConfirmationDialog
var _delete_target: Dictionary = {}
var _cards: Dictionary = {}
var _last_mode := -1
var selector: OptionButton
var status: Label
var form: ConfirmationDialog
var fields: Dictionary = {}
var form_error: Label
var selected_level_id := ""
var _editing := false
var _syncing_selector := false
var _world: Node
var sky_picker: OptionButton
var _form_sky_path := ""
var catalog_search: LineEdit
var catalog_count: Label
var _catalog_scroll: ScrollContainer
var _detail_side: PanelContainer
var _detail_edit: Button
var _detail_enter: Button
var _detail_remove: Button
var _detail_uses_file_preview := false
func _ready() -> void:
	add_theme_stylebox_override("panel", STYLE.box(STYLE.PAPER, 0, 0))
	if mode_bar == null:
		mode_bar = HBoxContainer.new(); add_child(mode_bar)
	for title in ["我的关卡", "关卡编辑"]:
		var button := Button.new(); button.text = title; STYLE.navigation(button, 34, false); button.custom_minimum_size.x = 110
		button.pressed.connect(func():
			if title == "我的关卡": set_mode(0)
			else: enter_edit())
		mode_bar.add_child(button); mode_buttons[title] = button
	mode_stack = TabContainer.new(); mode_stack.tabs_visible = false; mode_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL; mode_stack.add_theme_stylebox_override("panel", STYLE.box(STYLE.BACKGROUND, 0, 0)); add_child(mode_stack)
	_build_catalog()
	var editor_view := VBoxContainer.new(); editor_view.name = "关卡编辑"; mode_stack.add_child(editor_view)
	var bar := HBoxContainer.new(); editor_view.add_child(bar)
	_button(bar, "编辑关卡信息", func(): show_form(true))
	_button(bar, "保存场景", func():
		if logic_panel.graph != null: logic_panel.save_graph()
		else: EditorInterface.save_scene())
	_button(bar, "刷新", reload_catalog)
	selector = OptionButton.new(); selector.custom_minimum_size.x = 260
	selector.item_selected.connect(func(i: int):
		if _syncing_selector: return
		selected_level_id = str(selector.get_item_metadata(i)); open_selected())
	bar.add_child(selector)
	level_heading = Label.new(); level_heading.add_theme_color_override("font_color", STYLE.NAVY); editor_view.add_child(level_heading)
	logic_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor/level_logic_panel.gd").new()
	logic_panel.name = "关卡图"; logic_panel.plugin = module; editor_view.add_child(logic_panel)
	STYLE.workspace(logic_panel)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	form = ConfirmationDialog.new()
	form.hide()
	form.force_native = true
	form.transient = true
	form.exclusive = true
	form.dialog_hide_on_ok = false
	form.min_size = Vector2i(540, 350)
	form.confirmed.connect(apply_form)
	delete_dialog = ConfirmationDialog.new(); delete_dialog.title = "删除关卡"; delete_dialog.ok_button_text = "删除关卡"; delete_dialog.cancel_button_text = "取消"
	delete_dialog.confirmed.connect(_confirm_delete); delete_dialog.canceled.connect(func(): _delete_target.clear()); add_child(delete_dialog)
	delete_dialog.get_ok_button().theme_type_variation = "DangerButton"
	add_child(form)
	module.scene_changed.connect(bind_scene)
	reload_catalog()
	bind_scene(EditorInterface.get_edited_scene_root())
	set_mode(0)
func _button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new(); button.text = title; button.pressed.connect(action); parent.add_child(button)
func _build_catalog() -> void:
	var page := VBoxContainer.new(); page.name = "我的关卡"; page.add_theme_constant_override("separation", 22); mode_stack.add_child(page)
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation", 16); page.add_child(header)
	var heading := VBoxContainer.new(); heading.add_theme_constant_override("separation", 5); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(heading)
	var title := Label.new(); title.text = "关卡库"; title.add_theme_font_size_override("font_size", 24); title.add_theme_color_override("font_color", STYLE.INK); heading.add_child(title)
	catalog_count = Label.new(); catalog_count.add_theme_font_size_override("font_size", 13); catalog_count.add_theme_color_override("font_color", STYLE.MUTED); heading.add_child(catalog_count)
	catalog_search = LineEdit.new(); catalog_search.placeholder_text = "搜索关卡名称或 ID"; catalog_search.custom_minimum_size.x = 240; catalog_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER; catalog_search.text_changed.connect(func(_text: String): _filter_catalog()); header.add_child(catalog_search)
	var create := Button.new(); create.text = "+  新建关卡"; create.theme_type_variation = "PrimaryButton"; create.size_flags_vertical = Control.SIZE_SHRINK_CENTER; create.pressed.connect(func(): show_form(false)); header.add_child(create)
	var body := HBoxContainer.new(); body.add_theme_constant_override("separation", 24); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; page.add_child(body)
	_catalog_scroll = ScrollContainer.new(); _catalog_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; _catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER; body.add_child(_catalog_scroll)
	catalog_grid = GridContainer.new(); catalog_grid.columns = 4; catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; catalog_grid.add_theme_constant_override("h_separation", 18); catalog_grid.add_theme_constant_override("v_separation", 18); _catalog_scroll.add_child(catalog_grid)
	_catalog_scroll.resized.connect(_layout_catalog)
	_detail_side = PanelContainer.new(); _detail_side.custom_minimum_size.x = 312; _detail_side.add_theme_stylebox_override("panel", STYLE.bordered(STYLE.PAPER, STYLE.BORDER, 12, 20)); body.add_child(_detail_side)
	detail = VBoxContainer.new(); detail.add_theme_constant_override("separation", 16); _detail_side.add_child(detail)
	var content_scroll := ScrollContainer.new(); content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER; detail.add_child(content_scroll)
	var content := VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation", 16); content_scroll.add_child(content)
	var eyebrow := Label.new(); eyebrow.text = "关卡详情"; eyebrow.add_theme_font_size_override("font_size", 13); eyebrow.add_theme_color_override("font_color", STYLE.MUTED); content.add_child(eyebrow)
	detail_cover = TextureRect.new(); detail_cover.custom_minimum_size.y = 158; detail_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; detail_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; content.add_child(detail_cover)
	var material := ShaderMaterial.new(); material.shader = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/rounded_preview.gdshader"); material.set_shader_parameter("radius", 6.0); detail_cover.material = material; detail_cover.resized.connect(func(): material.set_shader_parameter("rect_size", detail_cover.size))
	var title_row := HBoxContainer.new(); content.add_child(title_row)
	detail_title = Label.new(); detail_title.add_theme_font_size_override("font_size", 21); detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_row.add_child(detail_title)
	_detail_edit = Button.new(); _detail_edit.text = "编辑"; _detail_edit.add_theme_font_size_override("font_size", 13); _detail_edit.tooltip_text = "编辑关卡信息"; _detail_edit.pressed.connect(func(): show_form(true)); title_row.add_child(_detail_edit)
	detail_info = Label.new(); detail_info.add_theme_font_size_override("font_size", 14); detail_info.add_theme_color_override("font_color", STYLE.MUTED); detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; content.add_child(detail_info)
	content.add_child(HSeparator.new())
	var notes_heading := Label.new(); notes_heading.text = "关卡说明"; notes_heading.add_theme_font_size_override("font_size", 13); notes_heading.add_theme_color_override("font_color", STYLE.MUTED); content.add_child(notes_heading)
	detail_notes = Label.new(); detail_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail_notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL; detail_notes.add_theme_font_size_override("font_size", 16); content.add_child(detail_notes)
	_detail_enter = Button.new(); _detail_enter.text = "进入编辑"; _detail_enter.theme_type_variation = "PrimaryButton"; _detail_enter.pressed.connect(enter_edit); detail.add_child(_detail_enter)
	_detail_remove = Button.new(); _detail_remove.text = "删除关卡"; _detail_remove.tooltip_text = "删除关卡记录及对应的 .tscn 场景文件"; _detail_remove.theme_type_variation = "DangerButton"; _detail_remove.pressed.connect(_ask_delete); detail.add_child(_detail_remove)

func _layout_catalog() -> void:
	# Window scaling is handled above this page; all dimensions here are logical.
	if _catalog_scroll == null or catalog_grid == null or _detail_side == null: return
	catalog_grid.columns = clampi(int((_catalog_scroll.size.x + 18) / 248), 1, 8)
	_detail_side.custom_minimum_size.x = 312 if size.x >= 1220 else 280

func _filter_catalog() -> void:
	if catalog == null or catalog_search == null: return
	var query := catalog_search.text.strip_edges()
	var shown := 0
	for id in _cards:
		var row: Dictionary = catalog.by_id(id)
		var matches := query.is_empty() or (str(row.display_name) + " " + str(row.name) + " " + str(row.level_id)).containsn(query)
		_cards[id].visible = matches
		if matches: shown += 1
	catalog_count.text = "%d 个关卡" % catalog.levels.size() if query.is_empty() else "%d / %d 个关卡" % [shown, catalog.levels.size()]
func set_mode(index: int) -> void:
	mode_stack.current_tab = index
	if index == 1: logic_panel.bind_world(_world)
	for key in mode_buttons: STYLE.select_navigation(mode_buttons[key], key == ("我的关卡" if index == 0 else "关卡编辑"))
	if index != _last_mode: STYLE.reveal(mode_stack.get_current_tab_control()); _last_mode = index
func enter_edit() -> void:
	open_selected(); set_mode(1)
func reload_catalog() -> void:
	var result := LEVELS.load_book(workbook_path)
	if not result.errors.is_empty(): status.text = "; ".join(result.errors); return
	catalog = result.catalog
	selector.clear()
	for child in catalog_grid.get_children(): catalog_grid.remove_child(child); child.queue_free()
	_cards.clear()
	for row in catalog.levels:
		selector.add_item(str(row.display_name) + " (" + str(row.level_id) + ")"); selector.set_item_metadata(selector.item_count - 1, str(row.level_id))
		var card := LEVEL_CARD.new(); card.data = row; card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.selected.connect(select_level); card.activated.connect(func(id: String): select_level(id); enter_edit())
		catalog_grid.add_child(card); _cards[str(row.level_id)] = card
	var add := LEVEL_CARD.new(); add.is_new = true; add.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add.activated.connect(func(_id: String): show_form(false)); catalog_grid.add_child(add)
	if catalog.by_id(selected_level_id).is_empty(): selected_level_id = str(catalog.levels[0].level_id) if not catalog.levels.is_empty() else ""
	_sync_selector(); _detail(false)
	_filter_catalog(); _layout_catalog()
	status.text = ""
func select_level(id: String) -> void:
	if id == selected_level_id: return
	selected_level_id = id; _sync_selector(); _detail(true)
func _detail(animated: bool) -> void:
	var row: Dictionary = catalog.by_id(selected_level_id) if catalog != null else {}
	for id in _cards: _cards[id].is_selected = id == selected_level_id
	var has_level := not row.is_empty()
	_detail_edit.disabled = not has_level; _detail_enter.disabled = not has_level; _detail_remove.disabled = not has_level
	detail.visible = true
	if not has_level:
		detail_title.text = "选择一个关卡"
		detail_info.text = "在左侧选择关卡，查看详情并继续编辑。"
		detail_notes.text = "也可以新建一个空白工作区。"
		detail_cover.texture = LEVEL_CARD.placeholder_texture()
		return
	detail_title.text = str(row.display_name)
	detail_info.text = "ID   " + str(row.level_id) + "\n名称   " + str(row.name)
	var sky: Resource = _world.sky_preset if is_instance_valid(_world) and _world.scene_file_path == str(row.scene_path) else SKY_LIBRARY.bound_preset(str(row.scene_path))
	detail_info.text += "\n天空   " + (str(sky.display_name) if sky != null else "现有光照")
	detail_info.tooltip_text = sky.summary() if sky != null else ""
	var notes := str(row.get("notes", "")).strip_edges()
	detail_notes.text = notes if not notes.is_empty() else "此关卡尚未填写说明。"
	detail_notes.add_theme_color_override("font_color", STYLE.INK if not notes.is_empty() else STYLE.MUTED)
	var path := str(row.get("preview_path", ""))
	detail_cover.texture = LEVEL_CARD.preview_texture(path)
	_detail_uses_file_preview = detail_cover.texture != null
	if detail_cover.texture == null: EditorInterface.get_resource_previewer().queue_resource_preview(str(row.scene_path), self, "_detail_preview", str(row.level_id))
	if detail_cover.texture == null: detail_cover.texture = LEVEL_CARD.placeholder_texture()
	if animated: STYLE.reveal(detail)
	level_heading.text = str(row.display_name) + "   " + str(row.level_id) + "   " + str(row.name)
func _detail_preview(_path: String, texture: Texture2D, _small: Texture2D, id: Variant) -> void:
	if not _detail_uses_file_preview and str(id) == selected_level_id and texture != null: detail_cover.texture = texture
func apply_level_preview(id: String, scene_path: String, path: String, texture: Texture2D) -> void:
	if catalog == null or texture == null: return
	var row: Dictionary = catalog.by_id(id)
	if row.is_empty() or str(row.scene_path) != scene_path: return
	row.preview_path = path
	if _cards.has(id): _cards[id].set_preview(path, texture)
	if selected_level_id == id:
		_detail_uses_file_preview = true
		detail_cover.texture = texture
func _sync_selector() -> void:
	_syncing_selector = true
	for i in selector.item_count:
		if selector.get_item_metadata(i) == selected_level_id: selector.select(i)
	_syncing_selector = false
func _ask_delete() -> void:
	if catalog == null: return
	var row: Dictionary = catalog.by_id(selected_level_id)
	if row.is_empty(): return
	_delete_target = row.duplicate(true)
	delete_dialog.dialog_text = "确定删除关卡「%s」（ID %s）？\n\n将删除关卡目录记录，并把以下场景文件移到系统废纸篓：\n%s\n\n需要恢复时，可从废纸篓找回文件。" % [str(row.display_name), str(row.level_id), str(row.scene_path)]
	delete_dialog.popup_centered()
	delete_dialog.get_cancel_button().grab_focus.call_deferred()
func _confirm_delete() -> void:
	var target := _delete_target.duplicate()
	_delete_target.clear()
	if not target.is_empty(): delete_selected(str(target.level_id), str(target.scene_path))
func delete_selected(id := "", expected_path := "") -> void:
	# An already open editor can retain the old direct confirmed connection after
	# a tool-script reload. It must still use the target displayed in the dialog.
	if id.is_empty() and not _delete_target.is_empty():
		id = str(_delete_target.level_id); expected_path = str(_delete_target.scene_path); _delete_target.clear()
	if id.is_empty(): id = selected_level_id
	var events := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd").load_book()
	if not events.errors.is_empty() or events.catalog == null:
		status.text = "无法检查任务引用，未删除关卡：" + ("; ".join(events.errors) if not events.errors.is_empty() else "事件配表未能载入。")
		return
	for task in events.catalog.tasks:
		if str(task.level_id) == id: status.text = "关卡仍被任务 " + str(task.task_id) + " 引用，请先调整任务所属关卡。"; return
	# Confirm against the latest workbook rather than rewriting a stale UI snapshot.
	var result := LEVELS.load_book(workbook_path)
	if result.catalog == null: status.text = "无法读取关卡目录，未删除：" + "; ".join(result.errors); return
	var fresh: Resource = result.catalog
	var row: Dictionary = fresh.by_id(id)
	if row.is_empty(): status.text = "关卡目录已变化，请刷新后重试。"; return
	var path := str(row.scene_path)
	if not expected_path.is_empty() and path != expected_path: status.text = "关卡场景路径已变化，请重新确认删除。"; return
	if path != path.simplify_path() or not path.begins_with(LEVELS.DIRECTORY + "/") or not path.ends_with(".tscn"):
		status.text = "关卡场景路径无效，未删除。"; return
	var dependents := _scene_dependents(path)
	if not dependents.is_empty(): status.text = "关卡场景仍被以下资源引用，未删除：\n" + "\n".join(dependents); return
	if path in EditorInterface.get_unsaved_scenes() or (is_instance_valid(logic_panel) and logic_panel.dirty and is_instance_valid(_world) and _world.scene_file_path == path):
		status.text = "请先保存或关闭此关卡的三维场景标签，再重新删除。"; return
	# Close the native tab first so a later Save cannot recreate a deleted level.
	if path in EditorInterface.get_open_scenes():
		var previous := EditorInterface.get_edited_scene_root()
		var previous_path := previous.scene_file_path if previous != null else ""
		EditorInterface.open_scene_from_path(path)
		var root := EditorInterface.get_edited_scene_root()
		if root == null or root.scene_file_path != path or EditorInterface.close_scene() != OK or path in EditorInterface.get_open_scenes():
			status.text = "请先保存或关闭此关卡的三维场景标签，再重新删除。"; return
		if not previous_path.is_empty() and previous_path != path: EditorInterface.open_scene_from_path(previous_path)
	var before: Array = fresh.levels.duplicate(true)
	fresh.levels.erase(row)
	var errors: PackedStringArray = fresh.save_book(workbook_path)
	if not errors.is_empty(): status.text = "未删除关卡：" + "; ".join(errors); return
	var error := _trash_scene(path)
	if error != OK:
		fresh.levels.assign(before)
		var rollback: PackedStringArray = fresh.save_book(workbook_path)
		status.text = "场景文件未删除：" + error_string(error)
		if not rollback.is_empty(): status.text += "；恢复关卡目录失败：" + "; ".join(rollback)
		return
	DirAccess.make_dir_recursive_absolute("user://level_archive")
	var file := FileAccess.open("user://level_archive/" + id + ".json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(row, "\t")); file.close()
	EditorInterface.get_resource_filesystem().update_file(path)
	reload_catalog(); levels_changed.emit()
	status.text = "已删除关卡「" + str(row.display_name) + "」，场景文件已移到系统废纸篓。"
func _trash_scene(path: String) -> Error:
	return OS.move_to_trash(ProjectSettings.globalize_path(path))
static func _scene_dependents(target: String, directory := "res://") -> PackedStringArray:
	var result := PackedStringArray()
	var folder := DirAccess.open(directory)
	if folder == null: return PackedStringArray(["无法读取依赖目录：" + directory])
	for name in folder.get_files():
		var path := directory.path_join(name)
		if path == target or name.get_extension().to_lower() not in ["tscn", "tres", "scn", "res"]: continue
		for dependency in ResourceLoader.get_dependencies(path):
			var parts := dependency.split("::")
			var reference := str(parts[-1])
			if reference.begins_with("uid://") and ResourceUID.has_id(ResourceUID.text_to_id(reference)): reference = ResourceUID.get_id_path(ResourceUID.text_to_id(reference))
			if reference == target:
				result.append(path); break
	for name in folder.get_directories():
		if name.begins_with("."): continue
		var child := directory.path_join(name)
		if FileAccess.file_exists(child.path_join(".gdignore")) or folder.is_link(name): continue
		result.append_array(_scene_dependents(target, child))
	return result
func open_selected() -> void:
	if catalog == null: return
	var level: Dictionary = catalog.by_id(selected_level_id)
	if not level.is_empty(): EditorInterface.open_scene_from_path(level.scene_path)
func bind_scene(root: Node) -> void:
	_world = root if root != null and root.get_script() == WORLD else root.get_node_or_null("World") if root != null else null
	if _world != null and catalog != null:
		var row: Dictionary = catalog.for_world(_world)
		if not row.is_empty(): selected_level_id = str(row.level_id); _sync_selector(); _detail(false)
	logic_panel.bind_world(_world, mode_stack.current_tab == 1)
func show_form(editing: bool) -> void:
	if catalog == null: return
	_editing = editing
	var row: Dictionary = catalog.by_id(selected_level_id) if editing else {"level_id": str(catalog.next_id), "name": "", "display_name": ""}
	if row.is_empty(): return
	for child in form.get_children():
		if child is VBoxContainer: child.free()
	fields.clear()
	form.title = "编辑关卡信息" if editing else "新建关卡"
	var box := VBoxContainer.new(); form.add_child(box)
	for key in ["level_id", "name", "display_name", "notes"]:
		var label := Label.new(); label.text = {"level_id": "关卡 ID", "name": "关卡名", "display_name": "关卡中文名", "notes": "备注"}[key]; box.add_child(label)
		var field: Control = TextEdit.new() if key == "notes" else LineEdit.new()
		field.text = str(row.get(key, "")); field.editable = key != "level_id"
		if key == "notes": field.custom_minimum_size.y = 100
		box.add_child(field); fields[key] = field
	var sky_label := Label.new(); sky_label.text = "天空预设"; box.add_child(sky_label)
	sky_picker = OptionButton.new(); sky_picker.add_item("现有光照"); sky_picker.set_item_metadata(0, ""); box.add_child(sky_picker)
	var sky: Resource = SKY_LIBRARY.bound_preset(str(row.get("scene_path", ""))) if editing else load(SKY_LIBRARY.DEFAULT)
	if editing and is_instance_valid(_world) and _world.scene_file_path == str(row.get("scene_path", "")): sky = _world.sky_preset
	_form_sky_path = sky.resource_path if sky != null else ""
	for path in SKY_LIBRARY.paths():
		var preset: Resource = load(path)
		if preset == null or not preset.has_method("solar_angles"): continue
		sky_picker.add_item(preset.display_name); sky_picker.set_item_metadata(sky_picker.item_count - 1, path)
		if path == _form_sky_path: sky_picker.select(sky_picker.item_count - 1)
	var sky_action := Button.new(); sky_action.text = "打开天空编辑器"; sky_action.pressed.connect(func():
		form.hide()
		var suite := get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
		if suite != null: suite.open_tab("天空"))
	box.add_child(sky_action)
	form_error = Label.new(); box.add_child(form_error)
	form.popup_centered()
func apply_form() -> void:
	var name_text := str(fields.name.text).strip_edges()
	var display := str(fields.display_name.text).strip_edges()
	if not name_text.is_valid_identifier() or display.is_empty(): form_error.text = "请填写有效关卡名和中文名。"; return
	for row in catalog.levels:
		if row.name == name_text and (not _editing or str(row.level_id) != selected_level_id): form_error.text = "关卡名已存在。"; return
	var sky_path := str(sky_picker.get_item_metadata(sky_picker.selected))
	var profile: Resource = load(sky_path) if not sky_path.is_empty() else null
	if profile != null and not profile.validate().is_empty(): form_error.text = "; ".join(profile.validate()); return
	if _editing and sky_path != _form_sky_path:
		open_selected()
		for i in 120:
			await get_tree().process_frame
			var root := EditorInterface.get_edited_scene_root()
			if root != null and root.scene_file_path == str(catalog.by_id(selected_level_id).scene_path): break
		bind_scene(EditorInterface.get_edited_scene_root())
		if not is_instance_valid(_world) or _world.scene_file_path != str(catalog.by_id(selected_level_id).scene_path): form_error.text = "无法打开关卡场景"; return
		var history := module.get_undo_redo()
		history.create_action("修改关卡天空", UndoRedo.MERGE_DISABLE, _world)
		history.add_do_property(_world, "sky_preset", profile); history.add_undo_property(_world, "sky_preset", _world.sky_preset); history.commit_action()
		if EditorInterface.save_scene() != OK: form_error.text = "天空绑定尚未保存，请保存关卡场景。"; return
	if _editing:
		var row: Dictionary = catalog.by_id(selected_level_id)
		var before: Dictionary = row.duplicate()
		row.name = name_text; row.display_name = display; row.notes = fields.notes.text
		var errors: PackedStringArray = catalog.save_book(workbook_path)
		if not errors.is_empty(): row.merge(before, true); form_error.text = "; ".join(errors); return
	else:
		var result := create_level(name_text, display, fields.notes.text, profile)
		if not result.errors.is_empty(): form_error.text = "; ".join(result.errors); return
		selected_level_id = str(result.level.level_id)
	form.hide(); reload_catalog(); levels_changed.emit(); open_selected(); set_mode(1)
func create_level(name_text: String, display: String, notes := "", profile: Resource = preload("res://addons/godot_level_editor/resources/sky_presets/builtin/sunny_v2.tres")) -> Dictionary:
	var id: String = catalog.allocate_id()
	var path := LEVELS.DIRECTORY + "/" + id + "_" + name_text + ".tscn"
	if FileAccess.file_exists(path): return {"errors": PackedStringArray(["场景文件已存在"])}
	var world := WORLD.new()
	world.name = name_text.to_pascal_case(); world.level_id = id; world.world_id = "level_" + id; world.start_room_id = ""
	world.sky_preset = profile
	world.topology = GRAPH.new(); world.topology.graph_id = "level_" + id + "_topology"; world.topology.graph_kind = "topology"
	world.events = GRAPH.new(); world.events.graph_id = "level_" + id + "_events"
	world.level_logic = preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_logic_graph.gd").new(); world.level_logic.graph_id = "level_" + id + "_logic"
	var floor := FACTORY.block(world, "layout_floor", Vector3(20, 3.6, 20), Vector3(0, -1.8, 0))
	preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd").group_new_node(world, floor)
	var spawn := SPAWN.new(); spawn.name = "PlayerSpawn"; spawn.object_id = "player_spawn"; spawn.position = Vector3(0, 0.1, 3); FACTORY.add_owned(world, spawn, world)
	var lighting: Node = load("res://addons/godot_level_editor/scenes/lighting/sunlit_miniature_v2.tscn").instantiate(); FACTORY.add_owned(world, lighting, world)
	DirAccess.make_dir_recursive_absolute(LEVELS.DIRECTORY)
	var error := FACTORY.save_scene(world, path)
	world.free()
	if error != OK: return {"errors": PackedStringArray(["无法保存关卡场景"])}
	var row := {"level_id": id, "name": name_text, "display_name": display, "scene_path": path, "notes": notes, "preview_path": ""}
	catalog.levels.append(row)
	var errors: PackedStringArray = catalog.save_book(workbook_path)
	if not errors.is_empty(): catalog.levels.erase(row); DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); return {"errors": errors}
	EditorInterface.get_resource_filesystem().update_file(path)
	level_created.emit(path)
	return {"level": row, "errors": PackedStringArray()}
