@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor_suite/level_warehouse.gd"
## Browse native maps without owning their creation, saving or file operations.
const TEMPLATE := "res://addons/godot_level_editor/templates/empty_level.tscn"
var browser: Control
var sky_info: Label
var _refresh_pending := false
var _refresh_scheduled := false
var _catalog_signature := ""
var _catalog_errors := PackedStringArray()

func _ready() -> void:
	_ensure_navigation()
	mode_stack = TabContainer.new(); mode_stack.tabs_visible = false; mode_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(mode_stack)
	browser = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_browser.gd").new()
	browser.name = "我的关卡"; mode_stack.add_child(browser)
	browser.open_requested.connect(_open_browser_level)
	browser.new_requested.connect(_new_browser_level)
	browser.refresh_requested.connect(reload_catalog)
	var editor_view := VBoxContainer.new(); editor_view.name = "关卡编辑"; mode_stack.add_child(editor_view)
	level_heading = Label.new(); level_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; editor_view.add_child(level_heading)
	sky_info = Label.new(); sky_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; editor_view.add_child(sky_info)
	var bar := HBoxContainer.new(); editor_view.add_child(bar)
	_button(bar, "定位当前场景", func():
		var root := EditorInterface.get_edited_scene_root()
		if root != null and not root.scene_file_path.is_empty(): EditorInterface.select_file(root.scene_file_path))
	_button(bar, "打开空白模板位置", func(): EditorInterface.select_file(TEMPLATE))
	logic_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor/level_logic_panel.gd").new()
	logic_panel.plugin = module; logic_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL; editor_view.add_child(logic_panel)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status)
	module.scene_changed.connect(_native_scene_changed)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_queue_refresh)
	visibility_changed.connect(_flush_refresh)
	_native_scene_changed(EditorInterface.get_edited_scene_root())
	reload_catalog()
	set_mode(0)

func _ensure_navigation() -> void:
	if mode_bar == null: mode_bar = HBoxContainer.new(); add_child(mode_bar)
	for index in 2:
		var title: String = ["我的关卡", "关卡编辑"][index]
		var button := mode_buttons.get(title) as Button
		if not is_instance_valid(button):
			button = Button.new(); button.text = title; STYLE.navigation(button, 34, false); button.custom_minimum_size.x = 110
			button.pressed.connect(func(): set_mode(index))
			mode_bar.add_child(button); mode_buttons[title] = button
		mode_bar.move_child(button, index)
		STYLE.select_navigation(button, index == (mode_stack.current_tab if mode_stack != null else 0))

func _native_scene_changed(root: Node) -> void:
	_world = root if root != null and root.get_script() == WORLD else null
	if _world == null and root != null: _world = root.get_node_or_null("World")
	if _world != null and _world.get_script() != WORLD: _world = null
	if logic_panel != null:
		logic_panel.bind_world(_world, false)
		logic_panel.visible = _world != null
	_detail(false)

func _detail(_animated: bool) -> void:
	if level_heading == null or status == null: return
	var path := _world.scene_file_path if is_instance_valid(_world) else ""
	level_heading.text = "当前关卡：" + (path.get_file().get_basename() if not path.is_empty() else "未保存的关卡" if is_instance_valid(_world) else "未打开关卡场景")
	var sky: Resource = _world.sky_preset if is_instance_valid(_world) else null
	if sky_info != null:
		sky_info.visible = is_instance_valid(_world)
		sky_info.text = "天空：" + (str(sky.display_name) if sky != null else "现有光照")
	status.text = "; ".join(_catalog_errors)
	if status.text.is_empty():
		if not is_instance_valid(_world): status.text = "在“我的关卡”打开已有地图，或新建关卡后使用 Godot 原生另存为。"
		elif path.is_empty() or path.begins_with("res://addons/"): status.text = "新关卡尚未保存，请使用 Godot“场景 → 另存为”保存到自己的作品目录。"

func reload_catalog() -> void:
	var result := LEVELS.load_book(workbook_path, false)
	_catalog_errors = result.errors
	if result.catalog != null: catalog = result.catalog
	elif catalog == null: catalog = LEVELS.new()
	if is_instance_valid(browser): browser.load_files(catalog, _world.scene_file_path if is_instance_valid(_world) else "")
	var signature := JSON.stringify(catalog.sheets())
	if signature != _catalog_signature:
		_catalog_signature = signature
		levels_changed.emit()
	_refresh_pending = false
	_detail(false)

func set_mode(index: int) -> void:
	_ensure_navigation()
	if mode_stack == null: _upgrade_existing_page()
	if mode_stack == null: return
	mode_stack.current_tab = clampi(index, 0, 1)
	for title in mode_buttons: STYLE.select_navigation(mode_buttons[title], title == ("我的关卡" if mode_stack.current_tab == 0 else "关卡编辑"))
	if mode_stack.current_tab == 0: reload_catalog()
	_native_scene_changed(EditorInterface.get_edited_scene_root())

func _upgrade_existing_page() -> void:
	# Preserve the existing graph control and its UndoRedo through a tool reload.
	if not is_instance_valid(logic_panel): return
	var previous := get_children()
	mode_stack = TabContainer.new(); mode_stack.tabs_visible = false; mode_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(mode_stack)
	browser = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_browser.gd").new(); browser.name = "我的关卡"; mode_stack.add_child(browser)
	browser.open_requested.connect(_open_browser_level); browser.new_requested.connect(_new_browser_level); browser.refresh_requested.connect(reload_catalog)
	var editor_view := VBoxContainer.new(); editor_view.name = "关卡编辑"; mode_stack.add_child(editor_view)
	for child in previous:
		if child == status or child == mode_bar: continue
		child.set_meta("godot_level_editor_reparenting", true); child.reparent(editor_view); child.remove_meta("godot_level_editor_reparenting")
	if not is_instance_valid(sky_info):
		sky_info = Label.new(); sky_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; editor_view.add_child(sky_info); editor_view.move_child(sky_info, 1)
	var filesystem := EditorInterface.get_resource_filesystem()
	if not filesystem.filesystem_changed.is_connected(_queue_refresh): filesystem.filesystem_changed.connect(_queue_refresh)
	if not visibility_changed.is_connected(_flush_refresh): visibility_changed.connect(_flush_refresh)
	reload_catalog()

func _open_browser_level(path: String) -> void:
	if not FileAccess.file_exists(path): reload_catalog(); status.text = "场景文件已移动或删除，请重新选择。"; return
	EditorInterface.open_scene_from_path(path)
	set_mode(1)

func _new_browser_level() -> void:
	EditorInterface.open_scene_from_path(TEMPLATE, true)
	set_mode(1)

func _queue_refresh() -> void:
	_refresh_pending = true
	if _refresh_scheduled: return
	_refresh_scheduled = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_scheduled = false
	if _refresh_pending and is_visible_in_tree() and mode_stack != null and mode_stack.current_tab == 0: reload_catalog()

func apply_level_preview(_id: String, scene_path: String, path: String, texture: Texture2D) -> void:
	if is_instance_valid(browser): browser.update_preview(scene_path, path, texture)
