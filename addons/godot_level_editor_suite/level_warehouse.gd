@tool
extends VBoxContainer
signal levels_changed
const LEVELS := preload("res://addons/godot_level_editor_suite/runtime/level_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/runtime/world.gd")
const FACTORY := preload("res://addons/godot_level_editor/scene_factory.gd")
const GRAPH := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
const SPAWN := preload("res://addons/godot_level_editor/runtime/spawn_marker.gd")
const STYLE := preload("res://addons/godot_level_editor_suite/editor_style.gd")
const LEVEL_CARD := preload("res://addons/godot_level_editor_suite/level_card.gd")
const SKY_LIBRARY := preload("res://addons/godot_level_editor_sky/library.gd")
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
	logic_panel = preload("res://addons/godot_level_editor/level_logic_panel.gd").new()
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
	delete_dialog = ConfirmationDialog.new(); delete_dialog.title = "删除关卡"; delete_dialog.confirmed.connect(delete_selected); add_child(delete_dialog)
	add_child(form)
	module.scene_changed.connect(bind_scene)
	reload_catalog()
	bind_scene(EditorInterface.get_edited_scene_root())
	set_mode(0)
func _button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new(); button.text = title; button.pressed.connect(action); parent.add_child(button)
func _build_catalog() -> void:
	var page := HBoxContainer.new(); page.name = "我的关卡"; page.add_theme_constant_override("separation", 20); mode_stack.add_child(page)
	var scroll := ScrollContainer.new(); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER; page.add_child(scroll)
	catalog_grid = GridContainer.new(); catalog_grid.columns = 4; catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; catalog_grid.add_theme_constant_override("h_separation", 16); catalog_grid.add_theme_constant_override("v_separation", 16); scroll.add_child(catalog_grid)
	scroll.resized.connect(func(): catalog_grid.columns = clampi(int((scroll.size.x + 16) / 246), 1, 4))
	var side := PanelContainer.new(); side.custom_minimum_size.x = 280; side.add_theme_stylebox_override("panel", STYLE.bordered(STYLE.PAPER, STYLE.BORDER, 10, 16)); page.add_child(side)
	detail = VBoxContainer.new(); detail.add_theme_constant_override("separation", 14); side.add_child(detail)
	var eyebrow := Label.new(); eyebrow.text = "关卡详情"; eyebrow.add_theme_font_size_override("font_size", 13); eyebrow.add_theme_color_override("font_color", STYLE.MUTED); detail.add_child(eyebrow)
	detail_cover = TextureRect.new(); detail_cover.custom_minimum_size.y = 158; detail_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; detail_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; detail.add_child(detail_cover)
	var material := ShaderMaterial.new(); material.shader = preload("res://addons/godot_level_editor_suite/rounded_preview.gdshader"); material.set_shader_parameter("radius", 6.0); detail_cover.material = material; detail_cover.resized.connect(func(): material.set_shader_parameter("rect_size", detail_cover.size))
	var title_row := HBoxContainer.new(); detail.add_child(title_row)
	detail_title = Label.new(); detail_title.add_theme_font_size_override("font_size", 20); detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_row.add_child(detail_title)
	var edit := Button.new(); edit.text = "编辑"; edit.add_theme_font_size_override("font_size", 13); edit.tooltip_text = "编辑关卡信息"; edit.pressed.connect(func(): show_form(true)); title_row.add_child(edit)
	detail_info = Label.new(); detail_info.add_theme_font_size_override("font_size", 13); detail_info.add_theme_color_override("font_color", STYLE.MUTED); detail_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; detail.add_child(detail_info)
	detail.add_child(HSeparator.new())
	var notes_scroll := ScrollContainer.new(); notes_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; detail.add_child(notes_scroll)
	detail_notes = Label.new(); detail_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail_notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL; detail_notes.add_theme_font_size_override("font_size", 14); notes_scroll.add_child(detail_notes)
	var actions := HBoxContainer.new(); detail.add_child(actions)
	var remove := Button.new(); remove.text = "删除关卡"; remove.theme_type_variation = "DangerButton"; remove.pressed.connect(_ask_delete); actions.add_child(remove)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_child(spacer)
	var enter := Button.new(); enter.text = "进入编辑"; enter.theme_type_variation = "PrimaryButton"; enter.pressed.connect(enter_edit); actions.add_child(enter)
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
	status.text = ""
func select_level(id: String) -> void:
	if id == selected_level_id: return
	selected_level_id = id; _sync_selector(); _detail(true)
func _detail(animated: bool) -> void:
	var row: Dictionary = catalog.by_id(selected_level_id) if catalog != null else {}
	for id in _cards: _cards[id].is_selected = id == selected_level_id
	detail.visible = not row.is_empty()
	if row.is_empty(): return
	detail_title.text = str(row.display_name)
	detail_info.text = "关卡ID " + str(row.level_id) + "\n关卡名 " + str(row.name)
	var sky: Resource = _world.sky_preset if is_instance_valid(_world) and _world.scene_file_path == str(row.scene_path) else SKY_LIBRARY.bound_preset(str(row.scene_path))
	detail_info.text += "\n天空 " + (str(sky.display_name) if sky != null else "现有光照")
	detail_info.tooltip_text = sky.summary() if sky != null else ""
	detail_notes.text = str(row.get("notes", ""))
	var path := str(row.get("preview_path", ""))
	detail_cover.texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path))) if not path.is_empty() and FileAccess.file_exists(path) else null
	if detail_cover.texture == null: EditorInterface.get_resource_previewer().queue_resource_preview(str(row.scene_path), self, "_detail_preview", str(row.level_id))
	if animated: STYLE.reveal(detail)
	level_heading.text = str(row.display_name) + "   " + str(row.level_id) + "   " + str(row.name)
func _detail_preview(_path: String, texture: Texture2D, _small: Texture2D, id: Variant) -> void:
	if str(id) == selected_level_id and texture != null: detail_cover.texture = texture
func _sync_selector() -> void:
	_syncing_selector = true
	for i in selector.item_count:
		if selector.get_item_metadata(i) == selected_level_id: selector.select(i)
	_syncing_selector = false
func _ask_delete() -> void:
	if catalog.by_id(selected_level_id).is_empty(): return
	delete_dialog.dialog_text = "从我的关卡中移除此关卡？场景文件会保留。"
	delete_dialog.popup_centered()
func delete_selected() -> void:
	var events := preload("res://addons/godot_level_editor_suite/runtime/event_catalog.gd").load_book()
	if events.catalog != null:
		for task in events.catalog.tasks:
			if str(task.level_id) == selected_level_id: status.text = "关卡仍被任务 " + str(task.task_id) + " 引用，请先调整任务所属关卡。"; return
	var row: Dictionary = catalog.by_id(selected_level_id)
	if row.is_empty(): return
	var before: Array = catalog.levels.duplicate(true)
	catalog.levels.erase(row)
	var errors: PackedStringArray = catalog.save_book(workbook_path)
	if not errors.is_empty(): catalog.levels.assign(before); status.text = "; ".join(errors); return
	DirAccess.make_dir_recursive_absolute("user://level_archive")
	var file := FileAccess.open("user://level_archive/" + selected_level_id + ".json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(row, "\t")); file.close()
	reload_catalog(); levels_changed.emit()
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
func create_level(name_text: String, display: String, notes := "", profile: Resource = preload("res://resources/sky_presets/builtin/sunny_v2.tres")) -> Dictionary:
	var id: String = catalog.allocate_id()
	var path := LEVELS.DIRECTORY + "/" + id + "_" + name_text + ".tscn"
	if FileAccess.file_exists(path): return {"errors": PackedStringArray(["场景文件已存在"])}
	var world := WORLD.new()
	world.name = name_text.to_pascal_case(); world.level_id = id; world.world_id = "level_" + id; world.start_room_id = ""
	world.sky_preset = profile
	world.topology = GRAPH.new(); world.topology.graph_id = "level_" + id + "_topology"; world.topology.graph_kind = "topology"
	world.events = GRAPH.new(); world.events.graph_id = "level_" + id + "_events"
	world.level_logic = preload("res://addons/godot_level_editor/runtime/level_logic_graph.gd").new(); world.level_logic.graph_id = "level_" + id + "_logic"
	var floor := FACTORY.block(world, "layout_floor", Vector3(20, 3.6, 20), Vector3(0, -1.8, 0))
	preload("res://addons/godot_level_editor/scene_groups.gd").group_new_node(world, floor)
	var spawn := SPAWN.new(); spawn.name = "PlayerSpawn"; spawn.object_id = "player_spawn"; spawn.position = Vector3(0, 0.1, 3); FACTORY.add_owned(world, spawn, world)
	var lighting: Node = load("res://scenes/lighting/sunlit_miniature_v2.tscn").instantiate(); FACTORY.add_owned(world, lighting, world)
	DirAccess.make_dir_recursive_absolute(LEVELS.DIRECTORY)
	var error := FACTORY.save_scene(world, path)
	world.free()
	if error != OK: return {"errors": PackedStringArray(["无法保存关卡场景"])}
	var row := {"level_id": id, "name": name_text, "display_name": display, "scene_path": path, "notes": notes, "preview_path": ""}
	catalog.levels.append(row)
	var errors: PackedStringArray = catalog.save_book(workbook_path)
	if not errors.is_empty(): catalog.levels.erase(row); DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); return {"errors": errors}
	EditorInterface.get_resource_filesystem().update_file(path)
	return {"level": row, "errors": PackedStringArray()}
