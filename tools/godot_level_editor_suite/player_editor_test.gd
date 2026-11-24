@tool
extends RefCounted

const TEMPLATE := preload("res://addons/godot_level_editor/templates/empty_level.tscn")
const LEVEL_PATH := "res://content/scenes/levels/player_library_editor_test.tscn"
var total := 0
var fails := 0

func check(ok: bool, title: String) -> void:
	total += 1
	fails += int(not ok)
	print("[PASS] " if ok else "[FAIL] ", title)

func frames(tree: SceneTree, n := 4) -> void:
	for i in n: await tree.process_frame

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(45).timeout.connect(func(): tree.quit(2))
	var level := TEMPLATE.instantiate()
	var packed := PackedScene.new()
	assert(packed.pack(level) == OK and ResourceSaver.save(packed, LEVEL_PATH) == OK)
	level.free()
	EditorInterface.open_scene_from_path(LEVEL_PATH)
	await frames(tree, 10)
	suite.open_tab("玩家")
	var panel: Control = suite.player_panel
	panel.new_preset()
	var jump := panel.find_child("jump", true, false) as CheckButton
	var crouch := panel.find_child("crouch", true, false) as CheckButton
	check(jump != null and crouch != null, "player page exposes independent ability controls")
	jump.button_pressed = false
	crouch.button_pressed = true
	panel.draft.display_name = "室内探索"
	check(panel.save_external() and FileAccess.file_exists(panel.selected_path), "editor saves authored preset outside the plugin")
	var first: String = panel.selected_path
	panel.apply_current()
	var world := EditorInterface.get_edited_scene_root()
	check(world.player_preset.resource_path == first, "Apply updates the actual native level root")
	var history := suite.get_undo_redo().get_history_undo_redo(suite.get_undo_redo().get_object_history_id(world))
	history.undo()
	check(world.player_preset == null, "native Undo clears the binding")
	history.redo()
	check(world.player_preset.resource_path == first, "native Redo restores the binding")
	check(EditorInterface.save_scene() == OK, "native Save serializes the preset reference")
	var scene := ResourceLoader.load(LEVEL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var copy := scene.instantiate()
	check(copy.player_preset.resource_path == first and not copy.player_preset.settings().jump, "reopening the scene restores external preset and ability values")
	copy.free()
	panel.duplicate_preset()
	panel.draft.display_name = "平台探索"
	panel.draft.values.jump = true
	check(panel.save_external() and panel.selected_path != first, "duplicate has its own file")
	var second: String = panel.selected_path
	check(not ResourceLoader.load(first, "", ResourceLoader.CACHE_MODE_IGNORE).settings().jump, "copy edits leave original ability changes intact")
	suite.open_tab("关卡图")
	var level_panel: Control = suite.level_panel
	var dropdown: OptionButton = level_panel._player_select
	for i in dropdown.item_count:
		if dropdown.get_item_metadata(i) == second: dropdown.item_selected.emit(i); break
	check(world.player_preset.resource_path == second, "switching the native level dropdown applies the other preset")
	panel._add_climb_zone()
	check(world.find_child("ClimbZone", false, false) != null, "climb zone is added as an owned level node")
	history.undo()
	check(world.find_child("ClimbZone", false, false) == null, "adding climb zone is undoable")
	suite.open_tab("玩家")
	panel._tabs.current_tab = 3
	panel._show_animation("dodge")
	await frames(tree, 8)
	check(panel._preview_player.is_playing() and panel._preview_player.current_animation == "moves/Roll", "animation page plays the assigned roll on the real skeleton")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--player-capture="):
			await RenderingServer.frame_post_draw
			check(suite.window.get_texture().get_image().save_png(arg.trim_prefix("--player-capture=")) == OK, "real player editor window captured")
	print("PLAYER EDITOR: %d checks, %d failures" % [total, fails])
	tree.quit(1 if fails else 0)
