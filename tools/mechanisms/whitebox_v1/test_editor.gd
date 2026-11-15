@tool
extends RefCounted
var checks := 0
var failures := 0
func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", title)
func frames(tree: SceneTree, count := 12) -> void:
	for index in count: await tree.process_frame
func select_option(field: OptionButton, value: String) -> bool:
	for index in field.item_count:
		if str(field.get_item_metadata(index)) == value:
			field.select(index); field.item_selected.emit(index); return true
	return false

func run(panel: Control, plugin: EditorPlugin) -> void:
	var tree := panel.get_tree()
	var suite: EditorPlugin = tree.get_first_node_in_group("godot_level_editor_editor_suite")
	for attempt in 120:
		if suite != null and suite._built: break
		await tree.process_frame
	suite.show_window(); suite.navigation_buttons["机关"].pressed.emit(); await frames(tree, 25)
	var warehouse: Control = suite.asset_panels["机关"]
	var all_assets := true
	for kind in panel.Schema.COMPONENT_KINDS: all_assets = all_assets and warehouse.entries.has("res://scenes/mechanisms/" + kind + ".tscn")
	check(all_assets and warehouse.mode_stack.current_tab == 0, "My Mechanisms lists all seven first-batch scene assets before entering edit mode")
	warehouse.select_asset("res://scenes/mechanisms/button_door.tscn"); warehouse.enter_edit(); await frames(tree, 35)
	check(panel.assembly != null and panel.assembly.bindings.size() == 2 and warehouse.mode_stack.current_tab == 1, "button-door sample opens with its real bound scene components")
	panel.selected_id = "button_component"; panel._render_details()
	check(panel.details.find_children("*", "OptionButton", true, false).size() >= 4, "component details expose initial state and authored transition selectors")
	var button: Node = panel.assembly.bindings.button
	panel.set_component_property(button, "locked", true)
	check(button.locked and panel.dirty, "editing a component property marks the paired scene dirty")
	panel._history(false); check(not button.locked, "component property changes participate in native scene undo")
	panel._history(true); check(button.locked, "component property changes participate in native scene redo")
	panel._history(false); await frames(tree)
	panel.add_kind("state_changed"); var event_id: String = panel.selected_id
	check(panel.assembly.definition.find_node(event_id).params.has("from_state"), "state-change nodes expose old/new state filters")
	panel._history(false); panel._history(true)
	check(not panel.assembly.definition.find_node(event_id).is_empty(), "new state-event nodes retain their parameters through undo/redo")
	panel._history(false)
	var before: int = panel.assembly.bindings.size()
	panel._duplicate_nodes(["button_component"])
	var copied: Dictionary = panel.assembly.definition.nodes.back()
	check(panel.assembly.bindings.size() == before + 1 and copied.params.object_id != "button" and panel.assembly.bindings[copied.params.object_id].has_method("get_state"), "duplicating a new component creates an independent physical object and stable binding")
	panel._history(false); await frames(tree)
	panel.selected_id = "button_component"; panel._refresh_preview(); panel._preview_interact(); panel._preview.step()
	check(panel._preview.bindings.button.get_state() == "pressed" and panel._preview.bindings.door.get_state() == "opening", "isolated preview interaction runs named-state wiring")
	for step in 100:
		for item in panel._preview.bindings.values():
			if item.has_method("get_state"): item.advance(1.0 / 60.0)
		panel._preview.step()
	check(panel._preview.bindings.door.get_state() == "open", "isolated preview reaches the door's real final state")
	var copy_path := "res://tools/mechanisms/whitebox_v1/editor_roundtrip_%d.tscn" % OS.get_process_id()
	panel._new_file = false; panel._save_to(copy_path); await frames(tree, 25)
	var reloaded: Node3D = panel.Store.load_pair(copy_path)
	check(panel.status.text.begins_with("已保存") and reloaded != null and reloaded.definition.validate(reloaded.bindings, true).is_empty(), "saving and reopening preserves new component types, events, actions and graph links")
	if reloaded != null: reloaded.free()
	EditorInterface.open_scene_from_path("res://scenes/levels/mechanism_whitebox_v1.tscn"); await frames(tree, 35)
	var task: Control = suite.task_graph; task.use_current_world(); task.bound_task_id = ""
	task.open_graph(load("res://resources/mechanisms/whitebox_v1/button_door.task.tres")); task.selected_id = "wait"; task._show_parameters()
	check(task._fields.mechanism is OptionButton and task._fields.state is OptionButton and task._fields.mechanism.item_count >= 8, "task mechanism selection enumerates current level instances and components")
	check(select_option(task._fields.mechanism, "$world/terminal_lift::lift") and select_option(task._fields.state, "at_end"), "changing the target offers the actual lift state names")
	task._apply_parameters()
	check(task.graph.node_by_id("wait").params.mechanism == "$world/terminal_lift::lift" and task.graph.node_by_id("wait").params.state == "at_end", "applying target/state selection updates the executable task definition")
	task.undo.undo(); check(task.graph.node_by_id("wait").params.state == "open", "task target/state parameter edits retain undo")
	task.undo.redo(); check(task.graph.node_by_id("wait").params.state == "at_end", "task target/state parameter edits retain redo")
	var invalid: Dictionary = task.graph.node_by_id("wait").duplicate(true); invalid.params.state = "nonexistent"
	check(not preload("res://addons/godot_level_editor_mechanisms/task_nodes.gd").validate_bindings(task.world, invalid).is_empty(), "saving rejects stale component state bindings")
	var found := true
	for kind in preload("res://addons/godot_level_editor_mechanisms/task_nodes.gd").DEFINITIONS:
		task.search.text = kind; task._filter_choices(); found = found and task.choices.item_count > 0
	check(found, "all new task mechanism node types are searchable and selectable")
	var capture := OS.get_cmdline_user_args().has("--capture")
	if capture:
		var directory := "res://docs/mechanism_editor/whitebox_v1"
		DirAccess.make_dir_recursive_absolute(directory)
		suite.navigation_buttons["机关"].pressed.emit(); suite.window.size = Vector2i(1504, 1000); await tree.create_timer(0.35, true).timeout
		RenderingServer.force_draw(false); suite.window.get_texture().get_image().save_png(directory + "/我的机关.png")
		warehouse.select_asset("res://scenes/mechanisms/button_door.tscn"); warehouse.enter_edit(); await frames(tree, 30)
		panel.selected_id = "pressed"; panel._render_details(); panel._fit_graph(false)
		await tree.create_timer(0.3, true).timeout; RenderingServer.force_draw(false); suite.window.get_texture().get_image().save_png(directory + "/按钮开门编辑.png")
		panel.selected_id = "button_component"; panel._render_details(); await frames(tree)
		RenderingServer.force_draw(false); suite.window.get_texture().get_image().save_png(directory + "/组件状态配置.png")
		EditorInterface.open_scene_from_path("res://scenes/levels/mechanism_whitebox_v1.tscn"); await frames(tree, 25)
		task.use_current_world(); task.selected_id = "wait"; task._show_parameters(); suite.open_tab("任务图"); await task.fit_graph(); await frames(tree)
		RenderingServer.force_draw(false); suite.window.get_texture().get_image().save_png(directory + "/任务等待机关状态.png")
		check(suite.window.size == Vector2i(1504, 1000), "new mechanism and task parameter panels fit the standard native workspace")
	task.dirty = false; panel.dirty = false
	EditorInterface.open_scene_from_path("res://scenes/main.tscn"); await frames(tree, 15)
	print("MECHANISM WHITEBOX EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
