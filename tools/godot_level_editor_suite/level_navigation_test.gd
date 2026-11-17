@tool
extends RefCounted
const FIXTURE := "res://content/scenes/levels/navigation_fixture.tscn"
const OTHER := "res://content/scenes/navigation_nonlevel.tscn"
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame
func open_scene(tree: SceneTree, path: String) -> void:
	EditorInterface.get_resource_filesystem().update_file(path)
	await frames(tree)
	EditorInterface.open_scene_from_path(path)
	for attempt in 100:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path: break
		await tree.create_timer(0.03, true).timeout
	await frames(tree)
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	await tree.create_timer(0.7, true).timeout
	check(not suite._built and suite.level_panel == null, "normal startup preserves lazy window and level-page creation")
	suite.show_window(); await frames(tree)
	check(suite._prepared_pages.keys() == ["工作台"] and suite.level_panel == null, "opening the workspace initially prepares only the workbench")
	var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://addons/godot_level_editor/templates/empty_level.tscn" id="1"]\n[node name="NavigationFixture" instance=ExtResource("1")]\n'); file.close()
	file = FileAccess.open(OTHER, FileAccess.WRITE); file.store_string('[gd_scene format=3]\n[node name="NonLevel" type="Node3D"]\n'); file.close()
	await open_scene(tree, FIXTURE)
	var root := EditorInterface.get_edited_scene_root()
	check(root != null and root.scene_file_path == FIXTURE, "a private inherited level opens through the native editor")
	if root == null or root.scene_file_path != FIXTURE: tree.quit(1); return
	var digest := FileAccess.get_sha256(FIXTURE)
	var snapshot: Dictionary = root.level_logic.snapshot()
	var semantic: String = root.level_logic.semantic_hash()
	suite.navigation_buttons["关卡"].pressed.emit(); await frames(tree)
	var panel: Control = suite.level_panel
	check(panel != null and panel.mode_bar.visible and panel.mode_bar.get_child_count() == 2, "first level visit displays both secondary navigation entries")
	var button := panel.mode_buttons.get("关卡编辑") as Button
	check(button != null and button.text == "关卡编辑" and button.visible and button.size.x > 0 and button.size.y > 0, "the Level Editing entry is visible with a usable hit area")
	check(panel.mode_buttons["我的关卡"].button_pressed and panel.mode_stack.current_tab == 0, "primary Levels opens the My Levels browser")
	button.pressed.emit(); await frames(tree)
	check(button != null and button.button_pressed, "Level Editing has the selected secondary-navigation state after activation")
	check(panel.logic_panel.visible and panel.logic_panel.world == root and panel.logic_panel.graph == root.level_logic, "the secondary entry corresponds to the current native scene logic")
	check(panel.mode_buttons.size() == 2 and panel.browser.entries.has(FIXTURE), "My Levels browses the existing native scene files")
	# Reproduce an existing window whose earlier script created an empty row.
	for entry in panel.mode_bar.get_children(): entry.free()
	panel.mode_buttons.clear()
	suite.navigation_buttons["关卡"].pressed.emit(); await frames(tree)
	button = panel.mode_buttons.get("关卡编辑") as Button
	check(button != null and panel.mode_buttons["我的关卡"].button_pressed and panel.mode_bar.get_child_count() == 2, "an already open empty navigation row repairs itself on the next level visit")
	if button != null: button.pressed.emit()
	suite.navigation_buttons["关卡"].pressed.emit(); await frames(tree)
	if button != null: button.pressed.emit()
	check(suite.level_panel == panel and panel.logic_panel.graph == root.level_logic and panel.mode_bar.get_child_count() == 2, "repeated primary and secondary clicks reuse the panel without duplicate entries")
	check(button != null and button.button_pressed and not panel.logic_panel.dirty and root.level_logic.semantic_hash() == semantic and root.level_logic.positions == snapshot.positions, "reopening the entry preserves graph semantics, node positions and clean state")
	suite.open_tab("事件与任务"); await frames(tree)
	check(not panel.mode_bar.visible and suite.task_navigation.visible, "task navigation replaces the level row")
	suite.open_tab("工作台"); await frames(tree)
	check(not panel.mode_bar.visible and not suite._subnavigation_separator.visible, "workbench hides the secondary row and separator")
	suite.open_tab("关卡图"); await frames(tree)
	check(panel.mode_bar.visible and button != null and button.button_pressed, "legacy level-graph navigation also restores the secondary row")
	await open_scene(tree, OTHER)
	check(panel.mode_bar.visible and button != null and button.button_pressed and not panel.logic_panel.visible and not panel.status.text.is_empty(), "secondary navigation remains visible with guidance when the active scene is not a level")
	if button != null: button.pressed.emit()
	await open_scene(tree, FIXTURE)
	check(panel.logic_panel.visible and panel.logic_panel.world == EditorInterface.get_edited_scene_root() and panel.mode_bar.visible, "switching back to a level rebinds the same navigation and graph panel")
	check(FileAccess.get_sha256(FIXTURE) == digest, "navigation and scene switching do not rewrite the level file")
	if DisplayServer.get_name() != "headless":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--qa-output="):
				RenderingServer.force_draw(false)
				suite.window.get_texture().get_image().save_png(arg.trim_prefix("--qa-output=").path_join("level_navigation.png"))
	print("LEVEL NAVIGATION TEST: ", checks, " checks, ", failures, " failures")
	tree.quit(0 if failures == 0 else 1)
