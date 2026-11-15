@tool
extends RefCounted

func frames(tree: SceneTree, count := 12) -> void:
	for i in count: await tree.process_frame

func run(suite: EditorPlugin, check: Callable, capture_dir: String) -> void:
	var tree := suite.get_tree()
	var mechanism: Control = suite.asset_panels["机关"]
	var npc: Control = suite.asset_panels["敌人"]
	var editor: Control = suite.modules.enemies.panel
	var mechanism_path := "res://scenes/mechanisms/lever_plate_door.tscn"
	var npc_path := "res://resources/enemies/guard_default.tres"
	var second_npc := "res://resources/enemies/new_enemy.tres"
	check.call(mechanism.editor_host.is_ancestor_of(suite.modules.mechanisms.panel) and npc.editor_host.is_ancestor_of(editor), "asset catalog wrappers retain the original module editor controls")
	for title in ["机关", "敌人"]:
		var workspace: Control = suite.asset_panels[title]
		suite.navigation_buttons[title].pressed.emit()
		check.call(workspace.mode_stack.current_tab == 0 and workspace.mode_bar.visible and suite._subnavigation_separator.visible and workspace.mode_buttons[0].button_pressed, title + " primary navigation opens its My Assets catalog and secondary navigation")
	check.call(mechanism.entries.has(mechanism_path) and not mechanism.entries.has("res://scenes/mechanisms/lever.tscn") and npc.entries.has(npc_path) and npc.entries.has(second_npc), "catalogs list editable mechanism assemblies and NPC definitions without blank component graphs")
	npc.editing_path = ""; npc.set_mode(0); npc.mode_buttons[1].pressed.emit()
	check.call(npc.mode_stack.current_tab == 0 and npc.mode_buttons[1].disabled, "NPC edit page cannot open before a concrete resource is opened")
	var before_path: String = editor.file_path
	npc.cards[npc_path].selected.emit(npc_path)
	check.call(editor.file_path == before_path and npc.mode_stack.current_tab == 0 and npc.selected_path == npc_path, "single-click selects an NPC card without loading it or entering edit mode")
	npc.cards[npc_path].activated.emit(npc_path)
	await frames(tree)
	check.call(editor.file_path == npc_path and npc.mode_stack.current_tab == 1 and npc.mode_buttons[1].button_pressed and editor.workspaces.is_visible_in_tree(), "double-click opens the selected NPC in the NPC edit page")
	var definition: Resource = editor.definition
	var initial_title: String = definition.display_name
	definition.display_name += " draft"; editor._update_dirty()
	suite.navigation_buttons["敌人"].pressed.emit()
	check.call(npc.mode_stack.current_tab == 0 and editor.dirty and editor.definition == definition, "returning to My NPCs preserves the current unsaved draft")
	npc.select_asset(second_npc); npc.enter_button.pressed.emit()
	check.call(editor.discard_dialog.visible and editor.file_path == npc_path and npc.mode_stack.current_tab == 0, "entering another NPC waits for the existing unsaved-changes dialog")
	editor.discard_dialog.canceled.emit(); editor.discard_dialog.hide()
	check.call(editor.definition == definition and editor.definition.display_name == initial_title + " draft" and npc._pending_path.is_empty(), "canceling the switch retains the NPC draft and catalog page")
	npc.mode_buttons[1].pressed.emit()
	check.call(npc.mode_stack.current_tab == 1 and editor.file_path == npc_path, "NPC edit secondary tab resumes the opened draft rather than the merely selected card")
	suite.navigation_buttons["敌人"].pressed.emit(); npc.enter_edit()
	editor.discard_dialog.confirmed.emit(); editor.discard_dialog.hide()
	check.call(editor.file_path == second_npc and npc.editing_path == second_npc and npc.mode_stack.current_tab == 1 and not editor.dirty, "confirming a switch enters the requested NPC after a successful load")
	npc.search.text = "no matching npc 473"; npc._filter()
	check.call(npc.empty_label.visible and not npc.cards[npc_path].visible, "catalog search handles no matches while preserving the New NPC card")
	npc.search.text = ""; npc._filter()
	suite.navigation_buttons["机关"].pressed.emit()
	var root_before := EditorInterface.get_edited_scene_root()
	mechanism.cards[mechanism_path].selected.emit(mechanism_path)
	check.call(EditorInterface.get_edited_scene_root() == root_before and mechanism.mode_stack.current_tab == 0, "single-click selects a mechanism without switching the native scene")
	mechanism.enter_button.pressed.emit()
	await frames(tree, 50)
	check.call(mechanism.mode_stack.current_tab == 1 and mechanism.editing_path == mechanism_path and suite.modules.mechanisms.panel.assembly == EditorInterface.get_edited_scene_root(), "Enter Edit opens the selected mechanism scene and its original bound graph")
	var panel: Control = suite.modules.mechanisms.panel
	var known_hash: String = panel._known_hash
	panel.dirty = true; panel._known_hash = "changed-on-disk"
	suite.navigation_buttons["机关"].pressed.emit()
	mechanism.select_asset("res://scenes/mechanisms/new_mechanism1.tscn"); mechanism.enter_edit()
	await frames(tree)
	check.call(mechanism.mode_stack.current_tab == 0 and panel.dirty and panel.assembly.scene_file_path == mechanism_path and not mechanism.status.text.is_empty(), "mechanism save conflicts keep the original draft and block resource switching")
	panel.dirty = false; panel._known_hash = known_hash
	mechanism.select_asset(mechanism_path); mechanism.enter_edit()
	await frames(tree)
	suite.navigation_buttons["关卡"].pressed.emit()
	check.call(suite.level_panel.mode_stack.current_tab == 0 and not mechanism.mode_bar.visible and not npc.mode_bar.visible, "level primary navigation also returns to My Levels with only its own secondary bar visible")
	var new_npc := "res://resources/enemies/asset_navigation_test_%d.tres" % OS.get_process_id()
	var new_mechanism := "res://scenes/mechanisms/asset_navigation_test_%d.tscn" % OS.get_process_id()
	npc.create_asset(new_npc)
	await frames(tree)
	check.call(npc.entries.has(new_npc) and editor.file_path == new_npc and npc.mode_stack.current_tab == 1, "New NPC saves a valid named resource and opens that resource in edit mode")
	editor.definition.display_name = "目录刷新测试"; editor._update_dirty(); editor.save()
	check.call(npc.entries[new_npc].display_name == "目录刷新测试", "saving an NPC refreshes its catalog title from disk without stale resource cache data")
	var new_hash := FileAccess.get_sha256(new_npc)
	npc.create_asset(new_npc)
	check.call(FileAccess.get_sha256(new_npc) == new_hash and npc.status.text.contains("已存在"), "New NPC refuses to overwrite an existing resource")
	mechanism._opening = true; mechanism.create_asset(new_mechanism); mechanism._opening = false
	var created := preload("res://addons/godot_level_editor_mechanisms/store.gd").load_pair(new_mechanism)
	check.call(created != null and mechanism.entries.has(new_mechanism), "New Mechanism creates a valid scene and paired graph listed in the catalog")
	if created != null: created.free()
	editor.request_open(npc_path)
	# Let the native filesystem finish inspecting the generated pair before deleting it.
	for attempt in 600:
		if not EditorInterface.get_resource_filesystem().is_scanning(): break
		await tree.process_frame
	await tree.create_timer(0.3, true).timeout
	for path in [new_npc, new_mechanism, new_mechanism.get_basename() + ".graph.tres"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	EditorInterface.get_resource_filesystem().scan()
	for attempt in 600:
		if not EditorInterface.get_resource_filesystem().is_scanning(): break
		await tree.process_frame
	mechanism.reload_catalog(); npc.reload_catalog()
	mechanism.status.text = ""; npc.status.text = ""; panel.status.text = ""
	if OS.get_cmdline_user_args().has("--capture"):
		for title in ["机关", "敌人"]:
			var workspace: Control = suite.asset_panels[title]
			suite.navigation_buttons[title].pressed.emit()
			workspace.select_asset(mechanism_path if title == "机关" else npc_path)
			suite.window.size = Vector2i(1504, 1000)
			await tree.create_timer(0.3, true).timeout
			RenderingServer.force_draw(false)
			suite.window.get_texture().get_image().save_png(capture_dir + "/我的" + workspace.kind + ".png")
			suite.window.size = Vector2i(1100, 760)
			await tree.create_timer(0.3, true).timeout
			check.call(suite.window.size == Vector2i(1100, 760) and workspace.catalog_grid.columns < 4 and workspace.enter_button.get_global_rect().end.x < 1100, title + " catalog fits the narrow workspace with visible detail actions")
			RenderingServer.force_draw(false)
			suite.window.get_texture().get_image().save_png(capture_dir + "/我的" + workspace.kind + "_窄窗口.png")
			suite.window.size = Vector2i(1504, 1000)
			workspace.enter_edit(); await frames(tree, 40)
			if title == "机关": panel._fit_graph(false); await frames(tree)
			await tree.create_timer(0.3, true).timeout
			RenderingServer.force_draw(false)
			suite.window.get_texture().get_image().save_png(capture_dir + "/" + workspace.kind + "编辑.png")
	EditorInterface.open_scene_from_path("res://scenes/main.tscn")
	await frames(tree, 20)
	check.call(mechanism.mode_stack.current_tab == 0 and mechanism.mode_buttons[1].disabled, "switching away from the mechanism scene returns to its catalog instead of showing an empty graph")
