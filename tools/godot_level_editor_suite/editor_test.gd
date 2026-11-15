@tool
extends RefCounted
const CATALOG := preload("res://addons/godot_level_editor_suite/runtime/event_catalog.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)
func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame
func run(suite: EditorPlugin) -> void:
	if OS.get_cmdline_user_args().has("--level-logic"):
		await load("res://tools/level_editor/level_logic_editor_test.gd").new().run(suite)
		return
	if OS.get_cmdline_user_args().has("--task-nodes"):
		await load("res://tools/narrative/task_nodes_editor_test.gd").new().run(suite)
		return
	var tree := suite.get_tree()
	var capture_dir := "res://docs/godot_level_editor_suite"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if OS.get_cmdline_user_args().has("--capture"): DirAccess.make_dir_recursive_absolute(capture_dir)
	tree.create_timer(90, true).timeout.connect(func(): tree.quit(2))
	suite._make_visible(true)
	if OS.get_cmdline_user_args().has("--capture"): suite.window.size = Vector2i(1504, 1000)
	await frames(tree, 10)
	check(EditorInterface.get_editor_viewport_3d(0).get_parent().is_visible_in_tree(), "opening the tool window keeps the native Godot 3D editor available")
	check(suite.window.force_native and not suite.window.transient, "workspace is a nonmodal native system window")
	check(suite.tabs.get_tab_count() == 8 and is_instance_valid(suite.sky_panel), "workspace retains the graph, table and new sky editor pages")
	check(suite.modules.size() == 4, "existing editor backends are retained behind the unified workspace")
	var canvases: Array[Node] = suite.tabs.find_children("*", "GraphEdit", true, false)
	var grids_visible: bool = canvases.size() == 4
	var behavior_unchanged := true
	for control in canvases:
		var canvas := control as GraphEdit
		grids_visible = grids_visible and canvas.show_grid and canvas.grid_pattern == GraphEdit.GRID_PATTERN_LINES and canvas.get_theme_color("grid_major").a > 0.5 and canvas.get_theme_color("grid_minor").a > 0.5 and canvas.get_theme_stylebox("panel").border_width_left > 0
		var behavior_before: Array = [canvas.snapping_enabled, canvas.snapping_distance, canvas.zoom, canvas.scroll_offset, canvas.get_connection_list()]
		suite.STYLE.graph_canvas(canvas)
		behavior_unchanged = behavior_unchanged and behavior_before == [canvas.snapping_enabled, canvas.snapping_distance, canvas.zoom, canvas.scroll_offset, canvas.get_connection_list()]
	check(grids_visible, "level, task, mechanism and NPC canvases show a bordered two-level square grid")
	check(behavior_unchanged, "grid styling preserves snapping, zoom, viewport and all existing connections")
	suite.open_tab("台本")
	var dp: Control = suite.modules.narrative.dialogue_panel
	check(dp.get_window() == suite.window, "dialogue editor is hosted in independent window")
	check(dp.library.xlsx_path.ends_with(".xlsx") and dp.library.validate().is_empty(), "dialogue table loads migrated XLSX authoring data")
	var original_library: Resource = dp.library
	var original_dirty: bool = dp.dirty
	dp.dirty = false
	var copy: Resource = original_library.duplicate(true)
	copy.xlsx_path = "user://suite_dialogue_editor_test.xlsx"
	dp.open_library(copy)
	dp.add_group()
	var id: String = dp.current_comment().lines[0].id
	check(id.is_valid_int(), "new dialogue rows retain automatic numeric IDs")
	dp.undo.undo()
	dp.undo.redo()
	check(dp.current_comment().lines[0].id == id, "moving to native window preserves dialogue undo/redo history")
	dp.save()
	check(not dp.dirty and FileAccess.file_exists(copy.xlsx_path), "save button writes XLSX directly")
	dp.library = original_library
	dp.dirty = original_dirty
	dp.export_dirty = false
	dp.undo.clear_history()
	dp._refresh()
	suite.open_tab("事件与任务")
	var panel: Control = suite.event_panel
	var original_catalog: Resource = panel.catalog
	panel.catalog = CATALOG.new()
	panel.workbook_path = "user://suite_events_editor_test.xlsx"
	panel.add_event()
	check(panel.selected_id == "1001", "event table automatically allocates first event ID 1001")
	panel.add_task()
	panel.fields.name.text = "task_" + panel.fields.id.text
	panel.fields.display_name.text = "测试任务"
	panel.fields.level_id.select_id("2")
	panel.apply_form()
	var first: String = panel.selected_id
	panel.catalog.task_by_id(first).graph_path = "res://tools/godot_level_editor_suite/.editor_task_%d.tres" % OS.get_process_id()
	panel.selected_kind = "event"
	panel.selected_id = "1001"
	panel.add_task()
	panel.fields.name.text = "task_" + panel.fields.id.text
	panel.fields.display_name.text = "测试任务"
	panel.fields.level_id.select_id("2")
	panel.apply_form()
	var second: String = panel.selected_id
	panel.catalog.task_by_id(second).graph_path = "res://tools/godot_level_editor_suite/.editor_second_%d.tres" % OS.get_process_id()
	check(first == "1001001" and second == "1001002", "task table IDs append event-scoped counters")
	panel.move_selected(-1)
	check(panel.catalog.event_tasks("1001")[0].task_id == second and first == "1001001", "reordering task rows keeps their IDs fixed")
	panel.undo.undo()
	check(panel.catalog.event_tasks("1001")[0].task_id == first, "task order edits support undo")
	panel.selected_kind = "task"
	panel.selected_id = second
	panel.delete_selected()
	check(panel.catalog.tasks.size() == 1, "task deletion removes only its catalog row")
	panel.undo.undo()
	check(panel.catalog.tasks.size() == 2, "undo restores deleted task and stable ID")
	panel.show_form()
	panel.fields.display_name.text = "潜入剧院"
	panel.fields.name.text = "TU002"
	panel.apply_form()
	panel.form.hide()
	check(panel.catalog.task_by_id(second).display_name == "潜入剧院" and panel.catalog.task_by_id(second).name == "TU002", "program names and HUD display names are edited independently")
	panel.selected_kind = "event"
	panel.selected_id = "1001"
	panel.show_form()
	panel.fields.name.text = "Tutor_001"
	panel.fields.display_name.text = "新手教学"
	panel.fields.start_type.select(1)
	panel.fields.start_key.text = "atrium"
	panel.apply_form()
	panel.form.hide()
	check(panel.catalog.event_by_id("1001").start_type == "room_enter", "event form independently configures start condition")
	panel.selected_kind = "task"
	panel.selected_id = first
	panel.catalog.task_by_id(first).display_name = "找讲解员说话"
	panel.save()
	check(not panel.dirty, "event/task save persists both sheets to XLSX")
	await frames(tree, 3)
	var edit_click := InputEventMouseButton.new()
	edit_click.button_index = MOUSE_BUTTON_LEFT
	edit_click.pressed = true
	edit_click.position = panel.table.get_item_area_rect(panel.table.get_selected(), 5).get_center()
	panel._context_input(edit_click)
	await frames(tree, 20)
	check(suite.tabs.get_tab_title(suite.tabs.current_tab) == "任务图", "task edit button opens its corresponding graph workspace")
	check(FileAccess.file_exists(panel.catalog.task_by_id(first).graph_path), "missing task graph is created on first edit")
	check(suite.task_graph.bound_task_id == first and suite.task_graph.graph.node_by_id("complete").params.task == first, "new graph is bound to auto-assigned task ID")
	suite.task_graph.selected_id = "complete"
	suite.task_graph._show_parameters()
	check(suite.task_graph._fields.has("task") and not suite.task_graph._fields.task.editable, "graph task ID is read-only and cannot be accidentally renumbered")
	var clean_titles := true
	var no_empty_status := true
	for card in suite.task_graph.canvas.get_children():
		if card is GraphNode:
			clean_titles = clean_titles and not (str(card.title).begins_with("触发 ·") or str(card.title).begins_with("动作 ·"))
			no_empty_status = no_empty_status and not card.get_node("Runtime").visible
	check(clean_titles and not suite.task_graph.legend.visible, "node classification uses color without category prefixes or a persistent legend")
	check(no_empty_status and not suite.task_graph.task_library_label.visible, "edit mode hides empty runtime messages and routine workbook labels")
	suite.task_graph.search.text = "结束当前事件"
	suite.task_graph._filter_choices()
	check(suite.task_graph.choices.item_count == 1, "task graph offers explicit event completion node")
	check(ProjectSettings.get_setting("application/config/name") == "GodotLevelEditor" and suite.window.title == "GodotLevelEditor", "project and native window use the new product name")
	check(not suite.tabs.tabs_visible and suite.navigation_buttons.size() == 7 and suite.navigation_buttons.has("天空"), "custom primary navigation includes the new sky editor")
	var level_dock: Control = suite.modules.level.dock_scroll
	check(level_dock.get_window() != suite.window and level_dock.is_inside_tree(), "whitebox palette remains attached to the native Godot editor")
	check(not FileAccess.file_exists("res://addons/godot_level_editor_suite/level_workspace.gd"), "external viewport implementation is removed")
	suite.navigation_buttons["关卡"].pressed.emit()
	check(suite.tabs.get_tab_title(suite.tabs.current_tab) == "关卡" and suite.navigation_buttons["关卡"].button_pressed, "level navigation opens the complete sandbox level workspace")
	await tree.create_timer(0.26, true).timeout
	var selected_style: StyleBoxFlat = suite.navigation_buttons["关卡"].get_theme_stylebox("pressed")
	var normal_style: StyleBoxFlat = suite.navigation_buttons["台本"].get_theme_stylebox("normal")
	var secondary_style: StyleBoxFlat = suite.level_panel.mode_buttons["我的关卡"].get_theme_stylebox("pressed")
	check(selected_style.bg_color.is_equal_approx(Color("2563eb")) and is_zero_approx(normal_style.bg_color.a) and is_zero_approx(secondary_style.bg_color.a) and secondary_style.border_width_bottom == 2, "primary navigation uses a solid blue active state and secondary navigation uses an underline")
	suite.open_tab("任务图"); suite.open_tab("台本"); suite.open_tab("关卡")
	await tree.create_timer(0.28, true).timeout
	check(suite.navigation_buttons["关卡"].button_pressed and (suite.navigation_buttons["关卡"].get_theme_font("font") as SystemFont).font_weight == 700 and (suite.navigation_buttons["台本"].get_theme_font("font") as SystemFont).font_weight == 400 and selected_style.shadow_size == 0 and selected_style.bg_color.is_equal_approx(Color("2563eb")), "rapid section changes leave only the final menu bold and fully settled")
	suite.navigation_buttons["台本"].pressed.emit()
	check(suite.navigation_buttons["台本"].button_pressed and not suite.navigation_buttons["关卡"].button_pressed and not suite.task_navigation.visible, "navigation keeps exactly one active section")
	suite.open_tab("任务图")
	check(suite.navigation_buttons["任务"].button_pressed and suite.task_buttons["任务图"].button_pressed and suite.task_navigation.visible, "task graph and event table remain under the task section")
	var animated_node: GraphNode = suite.task_graph.canvas.get_node("complete")
	var graph_before: Dictionary = suite.task_graph.graph.snapshot()
	var ports_before: Array = [animated_node.get_child_count(), animated_node.get_input_port_count(), animated_node.get_output_port_count(), animated_node.position_offset, suite.task_graph.canvas.get_connection_list()]
	suite.task_graph.canvas.node_selected.emit(animated_node)
	await tree.create_timer(0.3, true).timeout
	check(suite.task_graph.graph.snapshot() == graph_before and ports_before == [animated_node.get_child_count(), animated_node.get_input_port_count(), animated_node.get_output_port_count(), animated_node.position_offset, suite.task_graph.canvas.get_connection_list()] and animated_node.get_theme_stylebox("panel_selected").shadow_size == 0, "node selection feedback settles without adding children, moving nodes or changing graph data and ports")
	var warehouse: Control = suite.level_panel
	check(warehouse.mode_buttons.size() == 2 and is_instance_valid(warehouse.logic_panel) and warehouse.logic_panel.get_window() == suite.window and warehouse.find_children("*", "GraphEdit", true, false).size() == 1, "level editing contains the persistent logic graph without duplicated scene inventory pages")
	check(warehouse.catalog.levels.size() >= 3 and warehouse.catalog.by_id("1").display_name == "白盒工作区", "level catalog shows ID, program name and Chinese name from one scene directory")
	suite.open_tab("关卡")
	warehouse.set_mode(0)
	await tree.create_timer(0.25, true).timeout
	var first_card: Control = warehouse._cards["1"]
	check(first_card.cover.texture != null and warehouse.detail_cover.texture != null, "level cards and detail panel load real level thumbnails")
	var card_ids: Array = warehouse._cards.keys()
	var old_id: String = warehouse.selected_level_id
	first_card.mouse_entered.emit()
	await tree.create_timer(0.2, true).timeout
	check(first_card.hover_amount > 0.99 and first_card.scale.is_equal_approx(Vector2.ONE), "card hover animates its border and shadow without moving adjacent hit targets")
	first_card.mouse_exited.emit()
	warehouse.select_level(str(card_ids[1]))
	await tree.create_timer(0.25, true).timeout
	check(first_card.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(first_card.selection_amount, 0.0) and is_zero_approx(warehouse._cards[str(card_ids[1])].selection_pulse) and is_equal_approx(warehouse._cards[str(card_ids[1])].selection_amount, 1.0) and is_equal_approx(warehouse.detail.modulate.a, 1.0) and warehouse.catalog.levels.size() == card_ids.size(), "card selection and detail transitions settle without changing level data or hit areas")
	var protected_levels: Resource = warehouse.catalog
	warehouse.catalog = protected_levels.duplicate(true)
	warehouse.workbook_path = "user://suite_protected_levels_test.xlsx"
	warehouse.select_level("1")
	warehouse.delete_selected()
	check(warehouse.catalog.by_id("1").size() > 0 and warehouse.status.text.contains("引用"), "levels referenced by tasks cannot be removed")
	warehouse.catalog = protected_levels
	warehouse.workbook_path = warehouse.LEVELS.PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://suite_protected_levels_test.xlsx"))
	warehouse.select_level(old_id)
	warehouse.status.text = ""
	suite.open_tab("事件与任务")
	panel.selected_kind = "event"; panel.selected_id = "1001"
	var before_count: int = panel.catalog.tasks.size()
	var before_next: String = panel.catalog.next_task_id("1001")
	panel.add_task()
	check(panel.form.force_native and panel.fields.id.text.is_valid_int() and not panel.fields.id.editable, "new task uses native dialog with automatically allocated read-only numeric ID")
	panel.fields.name.text = "level_bound_task"; panel.fields.display_name.text = "跨关卡任务"
	panel.apply_form()
	check(panel.catalog.tasks.size() == before_count and panel.form.visible, "missing level keeps creation dialog open and creates no invalid task")
	panel.fields.level_id.search.text = "白盒"
	panel.fields.level_id.refresh()
	check(panel.fields.level_id.options.item_count == 2, "level dropdown can be searched by Chinese name")
	panel.fields.level_id.select_id("1")
	if OS.get_cmdline_user_args().has("--capture"):
		await frames(tree, 8)
		RenderingServer.force_draw(false)
		panel.form.get_texture().get_image().save_png(capture_dir + "/新建任务.png")
	panel.apply_form()
	check(panel.catalog.tasks.size() == before_count + 1 and panel.catalog.task_by_id(panel.selected_id).level_id == "1", "confirming task creates exactly one level binding")
	check(panel.catalog.task_by_id(panel.selected_id).task_id == before_next, "validation failure does not consume or renumber the displayed task ID")
	check(panel.table.columns == 6 and panel.table.get_column_title(3) == "所属关卡" and panel._level_caption(panel.catalog.event_by_id("1001"), "event").contains("连续世界") and panel._level_caption(panel.catalog.event_by_id("1001"), "event").contains("白盒工作区"), "event level column aggregates its independently bound task levels")
	panel.selected_kind = "event"; panel.selected_id = "1001"; panel.show_form()
	check(not panel.fields.has("level_id"), "event form has no level binding")
	panel.form.hide()
	var original_levels: Resource = warehouse.catalog
	var test_levels: Resource = original_levels.duplicate(true)
	warehouse.catalog = test_levels; warehouse.workbook_path = "user://suite_levels_editor_test.xlsx"
	var created: Dictionary = warehouse.create_level("test_level_" + str(OS.get_process_id()), "测试白盒关卡")
	check(created.errors.is_empty() and FileAccess.file_exists(created.get("level", {}).get("scene_path", "")), "new level saves metadata and scene into the common level directory")
	var level_path := str(created.get("level", {}).get("scene_path", ""))
	if not level_path.is_empty():
		var level: Node3D = load(level_path).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		check(level.level_id == created.level.level_id and level.validate().is_empty() and level.has_node("关卡白盒/LayoutFloor"), "new level has a stable ID, valid world data and a grouped initial whitebox floor")
		var spawn: Node3D = level.get_node("PlayerSpawn")
		spawn.position = Vector3(2, 0.1, 4)
		preload("res://addons/godot_level_editor/scene_factory.gd").save_scene(level, level_path)
		level.free()
		var reloaded: Node3D = ResourceLoader.load(level_path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		check(reloaded.get_node("PlayerSpawn").position == Vector3(2, 0.1, 4), "player spawn edits persist when saving and reopening a level")
		reloaded.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(level_path))
	warehouse.catalog = original_levels; warehouse.workbook_path = warehouse.LEVELS.PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://suite_levels_editor_test.xlsx"))
	check(warehouse.find_children("*", "Tree", true, false).is_empty(), "level logic editor has no scene inventories or placed-entity lists already managed by the wheel")
	suite._hide_window()
	check(not suite.window.visible, "closing workspace hides it without discarding editor controls")
	suite.show_window()
	check(suite.window.visible, "workspace can reopen with existing editor state")
	await preload("res://tools/godot_level_editor_suite/asset_navigation_test.gd").new().run(suite, check, capture_dir)
	if OS.get_cmdline_user_args().has("--capture"):
		panel.catalog = original_catalog
		panel.dirty = false
		panel._refresh()
		suite.task_graph.bound_task_id = "1001001"
		suite.task_graph.open_graph(load("res://resources/task_graphs/1001001.tres"))
		for tab in ["关卡", "台本", "事件与任务", "任务图", "机关", "敌人"]:
			if tab == "机关":
				EditorInterface.open_scene_from_path("res://scenes/mechanisms/lever_plate_door.tscn")
				await frames(tree, 20)
			suite.open_tab(tab)
			suite.window.size = Vector2i(1504, 1000)
			if tab == "任务图": await suite.task_graph.fit_graph()
			await tree.create_timer(0.25, true).timeout
			if suite.window.size != Vector2i(1504, 1000):
				print("WORKSPACE SIZE ", tab, " ", suite.window.size)
				for control in suite.tabs.get_current_tab_control().find_children("*", "Control", true, false):
					if control.get_combined_minimum_size().x > 1300: print(control.get_class(), " ", control.name, " min=", control.get_combined_minimum_size(), " size=", control.size)
			check(suite.window.size == Vector2i(1504, 1000), tab + " fits the standard workspace without forcing a larger window")
			RenderingServer.force_draw(false)
			suite.window.get_texture().get_image().save_png(capture_dir + "/" + tab + ".png")
		suite.open_tab("关卡")
		warehouse.set_mode(0)
		warehouse.select_level("1")
		suite.window.size = Vector2i(1504, 1000)
		await tree.create_timer(0.3, true).timeout
		check(suite.window.size == Vector2i(1504, 1000) and warehouse._cards["1"].size.x < 300 and warehouse.catalog_grid.get_child(3).get_rect().end.x <= warehouse.catalog_grid.size.x + 1, "gallery keeps four equally sized cards within the reference window")
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png(capture_dir + "/我的关卡.png")
		suite.window.size = Vector2i(1100, 760)
		await tree.create_timer(0.3, true).timeout
		var last_column: Control = warehouse.catalog_grid.get_child(warehouse.catalog_grid.columns - 1)
		check(suite.window.size == Vector2i(1100, 760) and warehouse.catalog_grid.columns < 4 and last_column.get_rect().end.x <= warehouse.catalog_grid.size.x + 1, "narrow window reduces gallery columns without cropping cards or detail actions")
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png(capture_dir + "/我的关卡_窄窗口.png")
		suite.window.size = Vector2i(1504, 1000)
		warehouse.enter_edit()
		await frames(tree, 15)
		warehouse.select_level("2")
		warehouse.enter_edit()
		await frames(tree, 15)
		await tree.create_timer(0.25, true).timeout
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png(capture_dir + "/关卡编辑.png")
	if OS.get_cmdline_user_args().has("--capture-motion"): await capture_motion(suite, capture_dir)
	var task_path := "res://tools/godot_level_editor_suite/.editor_task_%d.tres" % OS.get_process_id()
	panel.catalog = original_catalog
	panel.workbook_path = CATALOG.PATH
	panel.dirty = false
	panel.undo.clear_history()
	panel._refresh()
	suite.task_graph.dirty = false
	EditorInterface.open_scene_from_path("res://scenes/main.tscn")
	await frames(tree, 5)
	for target in [task_path, "user://suite_dialogue_editor_test.xlsx", "user://suite_events_editor_test.xlsx"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	print("GODOT_LEVEL_EDITOR SUITE EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)

func capture_motion(suite: EditorPlugin, directory: String) -> void:
	var tree := suite.get_tree()
	var motion_dir := OS.get_user_data_dir().path_join("selection_motion_frames_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(motion_dir)
	var captured_times: Array[int] = []
	suite.open_tab("关卡")
	suite.window.size = Vector2i(1504, 1000)
	suite.level_panel.set_mode(0)
	suite.level_panel.select_level("1")
	await tree.create_timer(0.3, true).timeout
	for frame in 60:
		if frame == 8: suite.level_panel.select_level("2")
		if frame == 24:
			suite.open_tab("事件与任务")
			suite.window.size = Vector2i(1504, 1000)
		if frame == 40:
			suite.open_tab("关卡")
			suite.window.size = Vector2i(1504, 1000)
			suite.level_panel.set_mode(0)
			suite.level_panel.select_level("4")
		await tree.create_timer(1.0 / 30.0, true).timeout
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png(motion_dir + "/frame_%03d.png" % frame)
		captured_times.append(Time.get_ticks_msec())
	var index := FileAccess.open(directory + "/motion_capture.json", FileAccess.WRITE)
	index.store_string(JSON.stringify({"directory": motion_dir, "times_ms": captured_times}))
	index.close()
