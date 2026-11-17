@tool
extends RefCounted
var checks := 0
var failures := 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", title)
func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(90, true).timeout.connect(func(): EditorInterface.stop_playing_scene(); tree.quit(2))
	await frames(tree, 10)
	suite.open_tab("台本")
	check(suite.window.visible, "manual editor entry still opens the native workspace")
	suite.event_panel.selected_kind = "event"
	suite.event_panel.selected_id = str(suite.event_panel.catalog.events[0].event_id)
	suite.event_panel.add_task()
	check(suite.event_panel.form.visible, "new task dialog opens as an independent native window")
	suite._build()
	check(not suite.event_panel.form.visible, "play launch also hides pending native task dialogs")
	check(suite.window.visible, "play build keeps the workspace open")
	suite._make_visible(true)
	check(suite.window.visible, "launch-time callback preserves workspace visibility")
	await frames(tree)
	suite._hide_window()
	suite._build()
	suite._make_visible(true)
	suite.modules.level._make_visible(true)
	check(not suite.window.visible, "launch callbacks do not reopen a workspace the user closed")
	await frames(tree)
	suite.show_window()
	check(suite.window.visible, "explicit menu can reopen the workspace")
	var page: int = suite.tabs.current_tab
	EditorInterface.play_main_scene()
	for i in 100:
		if EditorInterface.is_playing_scene(): break
		await tree.create_timer(0.05).timeout
	await tree.create_timer(2.0).timeout
	check(EditorInterface.is_playing_scene(), "main game launches through the editor play command")
	check(suite.window.visible, "native workspace stays open while main game runs")
	suite._make_visible(true)
	suite.modules.level._make_visible(true)
	await frames(tree)
	check(suite.window.visible and suite.tabs.current_tab == page, "automatic callbacks preserve the current editor page during play")
	suite._hide_window()
	suite._make_visible(true)
	suite.modules.level._make_visible(true)
	await frames(tree)
	check(not suite.window.visible, "a manually closed workspace stays closed during play")
	EditorInterface.stop_playing_scene()
	await tree.create_timer(1.0).timeout
	suite.show_window()
	check(suite.window.visible, "manual entry reopens the same workspace after stopping play")
	var path := "res://content/scenes/levels/4_TestLevel.tscn"
	var before := FileAccess.get_sha256(path)
	EditorInterface.open_scene_from_path(path)
	for i in 60:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path: break
		await tree.process_frame
	check(EditorInterface.get_edited_scene_root().scene_file_path == path, "the authored 4_TestLevel scene opens for F6")
	EditorInterface.play_current_scene()
	for i in 100:
		if EditorInterface.is_playing_scene(): break
		await tree.create_timer(0.05).timeout
	await tree.create_timer(2.0).timeout
	check(EditorInterface.is_playing_scene() and suite.window.visible, "F6 authored level play keeps the workspace open")
	EditorInterface.stop_playing_scene()
	await tree.create_timer(1.0).timeout
	check(suite.window.visible and FileAccess.get_sha256(path) == before, "stopping F6 preserves workspace and authored scene contents")
	print("GODOT_LEVEL_EDITOR PLAY FOCUS: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
