@tool
extends EditorPlugin
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")
const BRAND_ICON := preload("res://addons/godot_level_editor/assets/branding/mark.svg")
var window: Window
var tabs: TabContainer
var modules: Dictionary = {}
var event_panel: Control
var task_graph: Control
var level_panel: Control
var level_preview: Node
var asset_panels: Dictionary = {}
var sky_panel: Control
var player_panel: Control
var sky_export: EditorExportPlugin
var reference_drag: Node
var display_adapter: Node
var home_panel: Control
var navigation_buttons: Dictionary = {}
var task_buttons: Dictionary = {}
var task_navigation: HBoxContainer
var _subnavigation_separator: HSeparator
var _last_view := -1
var _header_content: VBoxContainer
var _last_task_page := "事件与任务"
var _moved: Array[Dictionary] = []
var _built := false
var _closing := false
var _starting_play := false
var _was_playing := false
var _page_hosts: Dictionary = {}
var _prepared_pages: Dictionary = {}
const TEST_ARGUMENTS := ["--capture-level-previews", "--warehouse-drag-test", "--scene-reference-test", "--ui-display-test", "--navigation-icon-test", "--navigation-performance-test", "--godot-level-editor-suite-test", "--godot-level-editor-suite-play-test", "--sky-editor-test", "--test-npc-samples-v1", "--independent-mechanism-editor-test"]
func _enter_tree() -> void:
	level_preview = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_preview.gd").new()
	add_child(level_preview)
	scene_saved.connect(_native_saved)
	scene_changed.connect(_remember_level)
	var dock := EditorInterface.get_file_system_dock()
	dock.files_moved.connect(_native_moved)
	dock.folder_moved.connect(_native_moved)
	dock.file_removed.connect(_native_removed)
	dock.folder_removed.connect(_native_removed)
	level_preview.preview_updated.connect(_level_preview_updated)
	sky_export = preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/export_plugin.gd").new()
	add_export_plugin(sky_export)
	add_to_group("godot_level_editor_editor_suite")
	add_tool_menu_item("打开 GodotLevelEditor", show_window)
	# Native placement, runtime/debugger registrations and save protection remain
	# active. The external window is constructed only when it is requested.
	for argument in TEST_ARGUMENTS:
		if OS.get_cmdline_user_args().has(argument):
			_build_workspace.call_deferred()
			break
	if OS.get_cmdline_user_args().has("--startup-lazy-test"): _startup_test.call_deferred()
func _has_main_screen() -> bool: return true
func _get_plugin_name() -> String: return "GodotLevelEditor"
func _get_plugin_icon() -> Texture2D:
	var image := Image.new()
	if image.load_svg_from_string(FileAccess.get_file_as_string(BRAND_ICON.resource_path), EditorInterface.get_editor_scale()) == OK:
		return ImageTexture.create_from_image(image)
	return BRAND_ICON
func _get_unsaved_status(_for_scene: String) -> String:
	if is_instance_valid(player_panel) and player_panel.dirty: return "玩家预设有未保存修改。"
	return "关卡图有未保存修改。" if level_panel != null and is_instance_valid(level_panel.logic_panel) and level_panel.logic_panel.dirty else "天空预设有未保存修改。" if is_instance_valid(sky_panel) and sky_panel.dirty else ""
func _apply_changes() -> void:
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_registry.gd").prepare(EditorInterface.get_edited_scene_root())
func _save_external_data() -> void:
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_registry.gd").prepare(EditorInterface.get_edited_scene_root())
	if level_panel != null and is_instance_valid(level_panel.logic_panel) and level_panel.logic_panel.dirty: level_panel.logic_panel.save_external()
	if is_instance_valid(sky_panel):
		sky_panel.save_external()
	if is_instance_valid(player_panel): player_panel.save_external()
func _make_visible(visible: bool) -> void:
	if visible and not _starting_play and not EditorInterface.is_playing_scene():
		EditorInterface.set_main_screen_editor("3D")
		show_window()
func _build() -> bool:
	_starting_play = true
	if is_instance_valid(window): _hide_dialogs()
	_finish_play_launch.call_deferred()
	return true
func _finish_play_launch() -> void:
	_starting_play = false
func _process(_delta: float) -> void:
	var playing := EditorInterface.is_playing_scene()
	if playing and not _was_playing and is_instance_valid(window): _hide_dialogs()
	_was_playing = playing
func _build_workspace() -> void:
	if _built: return
	for module in get_tree().get_nodes_in_group("godot_level_editor_suite_modules"):
		modules[str(module.get_meta("godot_level_editor_module"))] = module
	if modules.size() < 4:
		await get_tree().process_frame
		_build_workspace.call_deferred()
		return
	window = Window.new()
	window.hide()
	window.name = "GodotLevelEditorWorkspace"
	window.title = "GodotLevelEditor"
	window.theme = STYLE.theme()
	window.force_native = true
	window.transient = false
	window.exclusive = false
	window.size = Vector2i(1504, 1000)
	window.min_size = Vector2i(1100, 760)
	EditorInterface.get_base_control().add_child(window)
	display_adapter = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/display_adapter.gd").new()
	window.add_child(display_adapter)
	display_adapter.configure(window)
	reference_drag = preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_reference_drag.gd").new()
	EditorInterface.get_base_control().add_child(reference_drag)
	reference_drag.configure(EditorInterface.get_base_control().get_viewport(), window)
	window.close_requested.connect(_hide_window)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(outer)
	var header := PanelContainer.new()
	var header_style := STYLE.box(STYLE.PAPER, 0, 14)
	header_style.content_margin_left = 20; header_style.content_margin_right = 20
	header_style.border_color = STYLE.BORDER; header_style.border_width_bottom = 1
	header.add_theme_stylebox_override("panel", header_style)
	outer.add_child(header)
	_header_content = VBoxContainer.new(); _header_content.add_theme_constant_override("separation", 10); header.add_child(_header_content)
	var navigation := HBoxContainer.new(); navigation.add_theme_constant_override("separation", 6); _header_content.add_child(navigation)
	for title in ["工作台", "关卡", "玩家", "任务", "机关", "台本", "敌人", "天空", "其他"]:
		var button := Button.new()
		button.text = "NPC" if title == "敌人" else title
		button.tooltip_text = button.text + "编辑器"
		STYLE.navigation(button)
		var icon_file: String = {"工作台": "home", "关卡": "level", "玩家": "player", "任务": "task", "机关": "mechanism", "台本": "dialogue", "敌人": "npc", "天空": "sky", "其他": "other"}[title]
		var icon_image := Image.new()
		icon_image.load_svg_from_string(FileAccess.get_file_as_string("res://addons/godot_level_editor/assets/branding/navigation/" + icon_file + ".svg"), 2.0)
		button.icon = ImageTexture.create_from_image(icon_image)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", 26)
		button.pressed.connect(func():
			open_tab(_last_task_page if title == "任务" else title)
			if title == "关卡": level_panel.set_mode(0)
			elif asset_panels.has(title): asset_panels[title].ensure_catalog(); asset_panels[title].set_mode(0))
		navigation.add_child(button); navigation_buttons[title] = button
		preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/navigation_icon.gd").install(button, icon_file)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; navigation.add_child(spacer)
	var more := MenuButton.new(); more.text = "···"; more.tooltip_text = "更多"; more.custom_minimum_size = Vector2(40, 36); navigation.add_child(more)
	more.get_popup().add_item("保存全部", 0); more.get_popup().add_item("打开配表文件夹", 1)
	more.get_popup().id_pressed.connect(func(id: int):
		if id == 0: save_all()
		else: OS.shell_open(ProjectSettings.globalize_path("res://content/tables")))
	_subnavigation_separator = HSeparator.new()
	_subnavigation_separator.add_theme_stylebox_override("separator", STYLE.box(STYLE.BORDER, 0, 1))
	_subnavigation_separator.add_theme_constant_override("separation", 2)
	_header_content.add_child(_subnavigation_separator)
	task_navigation = HBoxContainer.new(); _header_content.add_child(task_navigation)
	for title in ["事件与任务", "任务图"]:
		var button := Button.new(); button.text = title; STYLE.navigation(button, 34, false); button.custom_minimum_size.x = 120
		button.pressed.connect(func(): open_tab(title))
		task_navigation.add_child(button); task_buttons[title] = button
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.add_theme_stylebox_override("panel", STYLE.box(STYLE.BACKGROUND, 0, 20))
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)
	home_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/home_panel.gd").new()
	home_panel.name = "工作台"; home_panel.suite = self; tabs.add_child(home_panel)
	task_graph = modules.narrative.task_panel
	_prepared_pages["工作台"] = true
	for title in ["事件与任务", "任务图", "关卡", "玩家", "机关", "台本", "敌人", "天空", "其他"]:
		var host := VBoxContainer.new(); host.name = title; tabs.add_child(host)
		_page_hosts[title] = host
	var other: Control = _page_hosts["其他"]
	_button(other, "HUD 编辑", func(): EditorInterface.open_scene_from_path("res://addons/godot_level_editor/scenes/hud.tscn"); EditorInterface.set_main_screen_editor("2D"))
	_button(other, "角色场景", func(): EditorInterface.open_scene_from_path("res://addons/godot_level_editor/scenes/humanoid_player.tscn"); EditorInterface.set_main_screen_editor("3D"))
	_button(other, "打开配表文件夹", func(): OS.shell_open(ProjectSettings.globalize_path("res://content/tables")))
	tabs.tab_changed.connect(_tab_changed)
	tabs.current_tab = 0
	_built = true
	_tab_changed(tabs.current_tab)
	var metadata := EditorInterface.get_editor_settings().get_project_metadata("godot_level_editor_suite", "window", Rect2i(Vector2i(90, 90), window.size))
	if metadata is Rect2i:
		display_adapter.restore_geometry(metadata, EditorInterface.get_editor_settings().get_project_metadata("godot_level_editor_suite", "layout_version", 0) == 2)
	EditorInterface.get_editor_settings().set_project_metadata("godot_level_editor_suite", "layout_version", 2)
	# Legacy integration checks inspect all panels directly. Explicitly prepare
	# them for those checks; normal startup and navigation keep the lazy path.
	for argument in TEST_ARGUMENTS:
		if OS.get_cmdline_user_args().has(argument):
			prepare_all_pages()
			break
	if OS.get_cmdline_user_args().has("--capture-level-previews"): _capture_previews.call_deferred()
	if OS.get_cmdline_user_args().has("--warehouse-drag-test"): _drag_test.call_deferred()
	if OS.get_cmdline_user_args().has("--scene-reference-test"): _reference_test.call_deferred()
	if OS.get_cmdline_user_args().has("--ui-display-test"): _display_test.call_deferred()
	if OS.get_cmdline_user_args().has("--navigation-icon-test"): _icon_test.call_deferred()
	if OS.get_cmdline_user_args().has("--navigation-performance-test"): _performance_test.call_deferred()
	if OS.get_cmdline_user_args().has("--godot-level-editor-suite-test"): _test.call_deferred()
	if OS.get_cmdline_user_args().has("--godot-level-editor-suite-play-test"):
		_play_test.call_deferred()
	if OS.get_cmdline_user_args().has("--sky-editor-test"):
		_sky_test.call_deferred()

func prepare_all_pages() -> void:
	if not _built: _build_workspace()
	for title in _page_hosts: _ensure_page(title)
	_tab_changed(tabs.current_tab)

func _ensure_page(title: String) -> void:
	if _prepared_pages.has(title) or not _page_hosts.has(title): return
	_prepared_pages[title] = true
	var host: Control = _page_hosts[title]
	match title:
		"玩家":
			player_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor_player/panel.gd").new()
			player_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			player_panel.suite = self
			host.add_child(player_panel)
		"事件与任务":
			event_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/event_panel.gd").new()
			event_panel.name = title; host.add_child(event_panel)
			event_panel.edit_task_requested.connect(edit_task)
			task_graph.event_editor = event_panel
		"任务图": _adopt(task_graph, title, host)
		"关卡":
			level_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_panel.gd").new()
			level_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			level_panel.mode_bar = HBoxContainer.new(); _header_content.add_child(level_panel.mode_bar)
			level_panel.name = title; level_panel.module = modules.level; level_panel.suite = self
			host.add_child(level_panel)
			level_panel.native_focus_requested.connect(focus_native_3d)
			level_panel.levels_changed.connect(func():
				if is_instance_valid(event_panel): event_panel._refresh())
			modules.narrative.debugger.state_received.connect(level_panel.logic_panel.receive_runtime)
			modules.narrative.debugger.instance_removed.connect(level_panel.logic_panel.remove_runtime)
			modules.narrative.debugger.session_cleared.connect(level_panel.logic_panel.clear_session)
			modules.narrative.debugger.session_paused.connect(level_panel.logic_panel.set_session_paused)
		"机关": _asset_workspace(title, modules.mechanisms, host)
		"台本": _adopt(modules.narrative.dialogue_panel, title, host)
		"敌人": _asset_workspace(title, modules.enemies, host)
		"天空":
			sky_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/panel.gd").new()
			sky_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			sky_panel.name = title; sky_panel.suite = self; host.add_child(sky_panel)
func _adopt(control: Control, name_text: String, target: Node = null) -> void:
	_moved.append({"node": control, "parent": control.get_parent(), "index": control.get_index()})
	control.set_meta("godot_level_editor_reparenting", true)
	control.reparent(tabs if target == null else target)
	control.remove_meta("godot_level_editor_reparenting")
	control.name = name_text
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	control.show()
	STYLE.workspace(control)
func _asset_workspace(title: String, module: EditorPlugin, host: Control = null) -> void:
	var workspace := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/asset_workspace.gd").new()
	workspace.name = title; workspace.kind = "NPC" if title == "敌人" else title
	workspace.module = module; workspace.editor = module.panel
	workspace.mode_bar = HBoxContainer.new(); _header_content.add_child(workspace.mode_bar)
	(tabs if host == null else host).add_child(workspace); asset_panels[title] = workspace
	_adopt(module.panel, workspace.kind + "编辑", workspace.editor_host)
	for button in module.panel.library_actions: button.hide()
func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
func show_window() -> void:
	if not _built:
		_build_workspace()
		if not _built: await get_tree().process_frame
		if not _built: return
	var opening := not window.visible
	window.show()
	if opening: STYLE.reveal(tabs)
	window.grab_focus()
	_tab_changed(tabs.current_tab)

func _remember_level(root: Node) -> void:
	if root == null or root.get_script() != preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd"): return
	var path := root.scene_file_path
	if path.is_empty() or path.begins_with("res://addons/") or not FileAccess.file_exists(path): return
	var uid := ResourceLoader.get_resource_uid(path)
	var key := ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else path
	var settings := EditorInterface.get_editor_settings()
	if settings.get_project_metadata("godot_level_editor_suite", "recent_level", "") != key:
		settings.set_project_metadata("godot_level_editor_suite", "recent_level", key)

func recent_level() -> String:
	var key := str(EditorInterface.get_editor_settings().get_project_metadata("godot_level_editor_suite", "recent_level", ""))
	if key.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(key)
		if not ResourceUID.has_id(uid): return ""
		key = ResourceUID.get_id_path(uid)
	return key if not key.is_empty() and FileAccess.file_exists(key) else ""

func resume_level() -> void:
	var path := recent_level()
	if path.is_empty():
		home_panel._refresh()
		return
	open_native_level(path)

func create_level() -> void:
	open_native_level(preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_panel.gd").TEMPLATE, true)

func open_native_level(path: String, inherited := false) -> void:
	EditorInterface.open_scene_from_path(path, inherited)
	focus_native_3d()

func focus_native_3d() -> void:
	EditorInterface.set_main_screen_editor("3D")
	_hide_window()
	EditorInterface.get_base_control().get_window().grab_focus()

func open_tab(name_text: String) -> void:
	# Keep old callers compatible with the single-scene level workflow.
	var level_graph := name_text == "关卡图"
	if level_graph: name_text = "关卡"
	if not _built: _build_workspace()
	if not _built: return
	_ensure_page(name_text)
	if not window.visible or not window.has_focus(): show_window()
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == name_text: tabs.current_tab = i; break
	if level_graph:
		level_panel.set_mode(1)
func _tab_changed(index: int) -> void:
	var title := tabs.get_tab_title(index)
	_ensure_page(title)
	var is_task := title in ["事件与任务", "任务图"]
	if is_task: _last_task_page = title
	task_navigation.visible = is_task
	_subnavigation_separator.visible = is_task or title == "关卡" or asset_panels.has(title)
	if level_panel != null: level_panel.mode_bar.visible = title == "关卡"
	for key in asset_panels: asset_panels[key].mode_bar.visible = title == key
	if index != _last_view:
		STYLE.reveal(tabs.get_current_tab_control())
		_last_view = index
	for key in navigation_buttons:
		STYLE.select_navigation(navigation_buttons[key], key == ("任务" if is_task else title))
	for key in task_buttons:
		STYLE.select_navigation(task_buttons[key], key == title)
func _hide_window() -> void:
	if is_instance_valid(sky_panel): sky_panel.stop_preview()
	EditorInterface.get_editor_settings().set_project_metadata("godot_level_editor_suite", "window", Rect2i(window.position, window.size))
	_hide_dialogs()
	window.hide()
func _hide_dialogs() -> void:
	if is_instance_valid(sky_panel): sky_panel.stop_preview()
	for child in window.find_children("*", "Window", true, false): child.hide()
func save_all() -> void:
	if is_instance_valid(sky_panel):
		sky_panel.stop_preview()
		if sky_panel.dirty: sky_panel.save_external()
	if is_instance_valid(player_panel) and not player_panel.save_external(): return
	EditorInterface.save_all_scenes()
	modules.narrative._save_external_data()
	if is_instance_valid(event_panel) and event_panel.dirty: event_panel.save()
	if is_instance_valid(level_panel) and level_panel.logic_panel.dirty: level_panel.logic_panel.save_graph()
	if modules.mechanisms.panel.dirty: modules.mechanisms.panel.save_before_editor()
	if modules.enemies.panel.dirty: modules.enemies.panel.save()
func edit_task(task: Dictionary) -> void:
	_ensure_page("任务图")
	if task_graph.dirty and str(task_graph.graph.resource_path) != str(task.graph_path):
		open_tab("任务图")
		task_graph.confirm_graph_switch(edit_task.bind(task.duplicate(true)))
		return
	if not FileAccess.file_exists(str(task.graph_path)):
		var graph := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd").new()
		graph.graph_id = "task_" + str(task.task_id)
		graph.nodes = [{"id": "start", "kind": "start", "params": {}}, {"id": "complete", "kind": "task_complete", "params": {"task": str(task.task_id)}}]
		graph.positions = {"start": Vector2(80, 100), "complete": Vector2(700, 100)}
		DirAccess.make_dir_recursive_absolute(str(task.graph_path).get_base_dir())
		if ResourceSaver.save(graph, str(task.graph_path)) != OK: event_panel.status.text = "无法创建任务图"; return
		EditorInterface.get_resource_filesystem().update_file(str(task.graph_path))
	var graph: Resource = task_graph.graph if task_graph.graph != null and task_graph.graph.resource_path == str(task.graph_path) else ResourceLoader.load(str(task.graph_path), "", ResourceLoader.CACHE_MODE_IGNORE)
	if graph == null or graph.get_script() != task_graph.TASK:
		event_panel.status.text = "无法打开任务图，请选择有效的任务图资源。"
		return
	task_graph.bound_task_id = str(task.task_id)
	if graph != task_graph.graph: task_graph.open_graph(graph)
	var levels := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	if levels.catalog != null:
		var level: Dictionary = levels.catalog.by_id(str(task.get("level_id", "")))
		if not level.is_empty():
			EditorInterface.open_scene_from_path(str(level.scene_path))
			for attempt in 60:
				var root := EditorInterface.get_edited_scene_root()
				if root != null and root.scene_file_path == str(level.scene_path): break
				await get_tree().process_frame
	task_graph.use_current_world()
	open_tab("任务图")
func _exit_tree() -> void:
	_closing = true
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_card.gd").clear_preview_cache()
	if is_instance_valid(level_preview):
		level_preview.dispose()
		level_preview.queue_free()
	if is_instance_valid(reference_drag): reference_drag.queue_free()
	if sky_export != null: remove_export_plugin(sky_export)
	if is_instance_valid(sky_panel): sky_panel.stop_preview()
	remove_tool_menu_item("打开 GodotLevelEditor")
	# Restore native controls before freeing the external workspace or disabling modules.
	for item in _moved:
		if is_instance_valid(item.node) and not item.node.is_queued_for_deletion() and is_instance_valid(item.parent):
			item.node.set_meta("godot_level_editor_reparenting", true)
			item.node.reparent(item.parent)
			item.parent.move_child(item.node, mini(int(item.index), item.parent.get_child_count() - 1))
			item.node.hide()
			item.node.remove_meta("godot_level_editor_reparenting")
	for module in [modules.get("mechanisms"), modules.get("enemies")]:
		if is_instance_valid(module) and is_instance_valid(module.panel):
			for button in module.panel.library_actions: button.show()
	if is_instance_valid(window): window.queue_free()
func _test() -> void:
	get_tree().create_timer(90, true).timeout.connect(func(): get_tree().quit(2))
	await load("res://tools/godot_level_editor_suite/editor_test.gd").new().run(self)
func _performance_test() -> void:
	get_tree().create_timer(120, true).timeout.connect(func(): get_tree().quit(2))
	await load("res://tools/godot_level_editor_suite/navigation_performance_test.gd").new().run(self)
func _startup_test() -> void:
	get_tree().create_timer(120, true).timeout.connect(func(): get_tree().quit(2))
	await load("res://tools/godot_level_editor_suite/startup_test.gd").new().run(self)
func _play_test() -> void:
	await load("res://tools/godot_level_editor_suite/play_focus_test.gd").new().run(self)

func _sky_test() -> void:
	await load("res://tools/sky_editor/editor_test.gd").new().run(self)

func _drag_test() -> void:
	await load("res://tools/godot_level_editor_suite/native_drag_test.gd").run(self)

func _reference_test() -> void:
	await load("res://tools/level_editor/scene_reference_editor_test.gd").new().run(self)

func _display_test() -> void:
	await load("res://tools/godot_level_editor_suite/display_test.gd").new().run(self)

func _icon_test() -> void:
	await load("res://tools/godot_level_editor_suite/navigation_icon_test.gd").new().run(self)

func _capture_previews() -> void:
	await load("res://tools/godot_level_editor_suite/capture_level_previews.gd").run(self)

func _level_preview_updated(id: String, scene_path: String, path: String, texture: Texture2D) -> void:
	if not _closing and is_instance_valid(level_panel): level_panel.apply_level_preview(id, scene_path, path, texture)

func _native_saved(path: String) -> void:
	# The root's POST_SAVE hook finishes Save As identity assignment first.
	_native_saved_finished.call_deferred(path)

func _native_saved_finished(path: String) -> void:
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_registry.gd").saved(path)
	_remember_level(EditorInterface.get_edited_scene_root())
	if is_instance_valid(level_panel): level_panel._native_scene_changed(EditorInterface.get_edited_scene_root())
	if is_instance_valid(player_panel): player_panel._scene_changed(EditorInterface.get_edited_scene_root())
	_native_refresh()
	if is_instance_valid(level_preview): level_preview.request(path)

func _native_moved(old: String, target: String) -> void:
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_registry.gd").moved(old, target)
	_native_refresh()

func _native_removed(path: String) -> void:
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_registry.gd").removed(path)
	_native_refresh()

func _native_refresh() -> void:
	if is_instance_valid(level_panel): level_panel.reload_catalog()
	elif is_instance_valid(event_panel): event_panel._refresh()
