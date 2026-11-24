@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor_suite/level_warehouse.gd"
## Browse native maps without owning their creation, saving or file operations.
const TEMPLATE := "res://addons/godot_level_editor/templates/empty_level.tscn"
const PLAYER_PRESET := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/preset.gd")
const PLAYER_BINDING := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/scene_binding.gd")
signal native_focus_requested
var suite: EditorPlugin
var browser: Control
var sky_info: Label
var _player_controls: HBoxContainer
var _player_select: OptionButton
var _refresh_pending := false
var _refresh_scheduled := false
var _catalog_signature := ""
var _catalog_errors := PackedStringArray()
var _performance_button: CheckButton
var performance_panel: Control

func _ready() -> void:
	_ensure_navigation()
	mode_stack = TabContainer.new(); mode_stack.tabs_visible = false; mode_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(mode_stack)
	browser = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_browser.gd").new()
	browser.name = "我的关卡"; mode_stack.add_child(browser)
	browser.open_requested.connect(_open_browser_level)
	browser.logic_requested.connect(_open_browser_level.bind(false))
	browser.new_requested.connect(_new_browser_level)
	browser.refresh_requested.connect(reload_catalog)
	var editor_view := VBoxContainer.new(); editor_view.name = "关卡编辑"; mode_stack.add_child(editor_view)
	level_heading = Label.new(); level_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; editor_view.add_child(level_heading)
	sky_info = Label.new(); sky_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; editor_view.add_child(sky_info)
	_add_player_controls(editor_view)
	var bar := HBoxContainer.new(); editor_view.add_child(bar)
	_button(bar, "定位当前场景", func():
		var root := EditorInterface.get_edited_scene_root()
		if root != null and not root.scene_file_path.is_empty(): EditorInterface.select_file(root.scene_file_path))
	_button(bar, "打开空白模板位置", func(): EditorInterface.select_file(TEMPLATE))
	_performance_button = CheckButton.new()
	_performance_button.text = "演出时间轴"
	_performance_button.toggled.connect(_show_performance)
	bar.add_child(_performance_button)
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
	if is_instance_valid(_world) and _world.player_preset_changed.is_connected(_refresh_player_presets):
		_world.player_preset_changed.disconnect(_refresh_player_presets)
	_world = root if root != null and root.get_script() == WORLD else null
	if _world == null and root != null: _world = root.get_node_or_null("World")
	if _world != null and _world.get_script() != WORLD: _world = null
	if is_instance_valid(_world): _world.player_preset_changed.connect(_refresh_player_presets)
	if logic_panel != null:
		logic_panel.bind_world(_world, false)
		logic_panel.visible = _world != null and (_performance_button == null or not _performance_button.button_pressed)
	if is_instance_valid(performance_panel): performance_panel.bind_world(_world if root == _world else null)
	_detail(false)
	_refresh_player_presets()

func _show_performance(value: bool) -> void:
	if value and not is_instance_valid(performance_panel):
		performance_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/panel.gd").new()
		performance_panel.suite = suite
		performance_panel.module = module
		logic_panel.get_parent().add_child(performance_panel)
		performance_panel.bind_world(_world if EditorInterface.get_edited_scene_root() == _world else null)
	if is_instance_valid(performance_panel): performance_panel.visible = value
	logic_panel.visible = not value and _world != null
	_detail(false)
	_refresh_player_presets()
	if logic_panel.visible: logic_panel._rebuild()

func _add_player_controls(parent: Control) -> void:
	if _player_controls != null: return
	_player_controls = HBoxContainer.new()
	parent.add_child(_player_controls)
	parent.move_child(_player_controls, 2)
	var title := Label.new()
	title.text = "玩家预设"
	_player_controls.add_child(title)
	_player_select = OptionButton.new()
	_player_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_select.item_selected.connect(func(index: int):
		if suite == null: return
		var path := str(_player_select.get_item_metadata(index))
		var preset := load(path) if not path.is_empty() else null
		PLAYER_BINDING.apply(suite.get_undo_redo(), EditorInterface.get_edited_scene_root(), preset))
	_player_controls.add_child(_player_select)
	_button(_player_controls, "打开玩家预设库", func():
		if suite != null: suite.open_tab("玩家"))

func _refresh_player_presets() -> void:
	if not is_instance_valid(_player_select): return
	var root := EditorInterface.get_edited_scene_root()
	_player_controls.visible = is_instance_valid(_world) and (_performance_button == null or not _performance_button.button_pressed)
	if not _player_controls.visible: return
	_player_select.disabled = not PLAYER_BINDING.editable_root(root)
	var current: Resource = _world.player_preset
	_player_select.clear()
	_player_select.add_item("默认第三人称")
	_player_select.set_item_metadata(0, "")
	var chosen := 0
	for path in PLAYER_PRESET.library_paths():
		var data := ResourceLoader.load(path)
		if data == null or data.get_script() != PLAYER_PRESET: continue
		var index := _player_select.item_count
		_player_select.add_item(data.display_name)
		_player_select.set_item_metadata(index, path)
		if current != null and current.resource_path == path: chosen = index
	if current != null and chosen == 0:
		chosen = _player_select.item_count
		_player_select.add_item(current.display_name)
		_player_select.set_item_disabled(chosen, true)
	_player_select.select(chosen)

func _detail(_animated: bool) -> void:
	if level_heading == null or status == null: return
	var path := _world.scene_file_path if is_instance_valid(_world) else ""
	level_heading.text = "当前关卡：" + (path.get_file().get_basename() if not path.is_empty() else "未保存的关卡" if is_instance_valid(_world) else "未打开关卡场景")
	var sky: Resource = _world.sky_preset if is_instance_valid(_world) else null
	if sky_info != null:
		sky_info.visible = is_instance_valid(_world) and (_performance_button == null or not _performance_button.button_pressed)
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
	browser.open_requested.connect(_open_browser_level)
	browser.logic_requested.connect(_open_browser_level.bind(false))
	browser.new_requested.connect(_new_browser_level)
	browser.refresh_requested.connect(reload_catalog)
	var editor_view := VBoxContainer.new(); editor_view.name = "关卡编辑"; mode_stack.add_child(editor_view)
	for child in previous:
		if child == status or child == mode_bar: continue
		child.set_meta("godot_level_editor_reparenting", true); child.reparent(editor_view); child.remove_meta("godot_level_editor_reparenting")
	if not is_instance_valid(sky_info):
		sky_info = Label.new(); sky_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; editor_view.add_child(sky_info); editor_view.move_child(sky_info, 1)
	_add_player_controls(editor_view)
	var filesystem := EditorInterface.get_resource_filesystem()
	if not filesystem.filesystem_changed.is_connected(_queue_refresh): filesystem.filesystem_changed.connect(_queue_refresh)
	if not visibility_changed.is_connected(_flush_refresh): visibility_changed.connect(_flush_refresh)
	reload_catalog()

func _open_browser_level(path: String, focus_native := true) -> void:
	if not FileAccess.file_exists(path): reload_catalog(); status.text = "场景文件已移动或删除，请重新选择。"; return
	EditorInterface.open_scene_from_path(path)
	set_mode(1)
	if focus_native: native_focus_requested.emit()

func _new_browser_level() -> void:
	EditorInterface.open_scene_from_path(TEMPLATE, true)
	set_mode(1)
	native_focus_requested.emit()

func _queue_refresh() -> void:
	_refresh_pending = true
	if _refresh_scheduled: return
	_refresh_scheduled = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_scheduled = false
	if _refresh_pending and is_visible_in_tree() and mode_stack != null and mode_stack.current_tab == 1: _refresh_player_presets()
	if _refresh_pending and is_visible_in_tree() and mode_stack != null and mode_stack.current_tab == 0: reload_catalog()

func apply_level_preview(_id: String, scene_path: String, path: String, texture: Texture2D) -> void:
	if is_instance_valid(browser): browser.update_preview(scene_path, path, texture)
