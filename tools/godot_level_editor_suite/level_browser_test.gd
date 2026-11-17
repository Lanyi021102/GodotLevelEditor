@tool
extends RefCounted
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const TEMPLATE := "res://addons/godot_level_editor/templates/empty_level.tscn"
const FIRST := "res://content/scenes/levels/browser_first.tscn"
const COPY := "res://content/scenes/levels/browser_copy.tscn"
const CUSTOM := "res://custom_maps/browser_custom.tscn"
const MOVED := "res://custom_maps/browser_moved.tscn"
var checks := 0
var failures := 0
var output := ""
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(tree: SceneTree, count := 8) -> void:
	for i in count: await tree.process_frame
func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(text); file.close()
func inherited(path: String) -> void:
	write(path, '[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="' + TEMPLATE + '" id="1"]\n[node name="BrowserFixture" instance=ExtResource("1")]\n')
func open(tree: SceneTree, path: String) -> Node:
	EditorInterface.get_resource_filesystem().update_file(path)
	await frames(tree)
	EditorInterface.open_scene_from_path(path)
	for i in 100:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path: await frames(tree); return root
		await tree.create_timer(0.03, true).timeout
	return null
func save(tree: SceneTree, path: String) -> void:
	EditorInterface.save_scene_as(path, false)
	await frames(tree, 18)
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	await tree.create_timer(1.0, true).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await frames(tree, 2)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="): output = arg.trim_prefix("--qa-output=")
	check(not suite._built, "normal startup leaves the browser uninitialized")
	var template_hash := FileAccess.get_sha256(TEMPLATE)
	inherited(FIRST); inherited(CUSTOM)
	write("res://content/scenes/levels/browser_not_level.tscn", '[gd_scene format=3]\n[node name="Other" type="Node3D"]\n')
	var workbook_before := FileAccess.get_sha256(LEVELS.PATH)
	var first_before := FileAccess.get_sha256(FIRST)
	suite.show_window(); suite.navigation_buttons["关卡"].pressed.emit(); await frames(tree)
	var panel: Control = suite.level_panel
	var browser: Control = panel.browser
	check(panel.mode_buttons.keys() == ["我的关卡", "关卡编辑"] and panel.mode_stack.current_tab == 0, "primary Levels opens My Levels beside Level Editing")
	check(browser.entries.has(FIRST) and browser.entries.has(CUSTOM), "browser discovers native inherited maps before ID registration, including custom folders")
	check(not browser.entries.has(TEMPLATE) and not browser.entries.has("res://content/scenes/levels/browser_not_level.tscn"), "browser excludes plugin templates and ordinary non-level scenes")
	check(browser.entries.values().all(func(row): return FileAccess.file_exists(str(row.scene_path))), "every browser entry is backed by an existing native scene file")
	check(browser.cards.values().all(func(card): return not card.data.get("native_preview", true)), "level cards use saved bird's-eye images without queuing parallel generic scene previews")
	check(FileAccess.get_sha256(LEVELS.PATH) == workbook_before and FileAccess.get_sha256(FIRST) == first_before, "browsing does not register IDs or rewrite map files")
	var active_before := EditorInterface.get_edited_scene_root()
	browser.cards[FIRST].selected.emit(FIRST)
	check(browser.selected_path == FIRST and EditorInterface.get_edited_scene_root() == active_before, "single-click selects details without changing the active scene")
	browser.cards[FIRST].activated.emit(FIRST)
	await frames(tree, 16)
	var root := EditorInterface.get_edited_scene_root()
	check(root != null and root.scene_file_path == FIRST and panel.mode_stack.current_tab == 1 and panel.logic_panel.world == root, "double-click opens the native map and its existing logic editor")
	if root == null or root.scene_file_path != FIRST: tree.quit(1); return
	check(panel.sky_info.text == "天空：" + str(root.sky_preset.display_name), "current level information reads the actual bound sky preset")
	await save(tree, FIRST)
	var original_id := str(root.level_id)
	var index := LEVELS.load_book()
	check(not original_id.is_empty() and index.catalog != null and index.catalog.by_id(original_id).scene_path == FIRST, "one native save registers the level identity and path")
	var original_hash := FileAccess.get_sha256(FIRST)
	panel.set_mode(0); await frames(tree)
	check(str(browser.entries[FIRST].level_id) == original_id and browser.details.text.contains("天空："), "browser refreshes ID metadata after native save and shows sky information")
	browser.search.text = "browser_first"; browser._filter()
	panel.reload_catalog()
	check(browser.cards[FIRST].visible and not browser.cards[CUSTOM].visible and browser.search.text == "browser_first", "search filters paths and survives refresh")
	browser.search.text = "no_such_level_qa"; browser._filter()
	check(browser.empty.visible and browser.cards.values().all(func(card: Control): return not card.visible), "empty search results are explicit")
	browser.search.text = ""; browser._filter()
	panel.mode_buttons["关卡编辑"].pressed.emit()
	var graph: Resource = panel.logic_panel.graph
	panel.logic_panel.search.text = "constant"; panel.logic_panel._filter_choices()
	for i in panel.logic_panel.choices.item_count:
		if panel.logic_panel.choices.get_item_metadata(i) == "constant": panel.logic_panel.choices.select(i); break
	var before: int = graph.nodes.size(); panel.logic_panel._add_choice()
	panel.set_mode(0); panel.set_mode(1)
	check(panel.logic_panel.graph == graph and graph.nodes.size() == before + 1 and panel.logic_panel.dirty, "switching browser/editor preserves authored graph changes")
	panel.logic_panel.undo.undo()
	check(graph.nodes.size() == before, "graph UndoRedo survives browser/editor switches")
	# Reproduce the one-page layout retained by an already open tool window.
	var previous_logic: Control = panel.logic_panel
	var previous_stack: TabContainer = panel.mode_stack
	for child in previous_stack.get_child(1).get_children():
		child.set_meta("godot_level_editor_reparenting", true); child.reparent(panel); child.remove_meta("godot_level_editor_reparenting")
	previous_stack.free(); panel.mode_stack = null; panel.browser = null
	panel.set_mode(0); await frames(tree)
	browser = panel.browser
	check(panel.logic_panel == previous_logic and panel.logic_panel.graph == graph and panel.logic_panel.dirty, "upgrading an existing one-page window retains the graph control and unsaved edits")
	panel.logic_panel.undo.redo()
	check(graph.nodes.size() == before + 1, "UndoRedo remains usable after the existing window gains its browser")
	panel.logic_panel.undo.undo()
	await save(tree, COPY)
	var copy_id := str(root.level_id)
	index = LEVELS.load_book()
	check(copy_id != original_id and index.catalog.by_id(copy_id).scene_path == COPY and FileAccess.get_sha256(FIRST) == original_hash, "native Save As creates an independent indexed map and preserves the original file")
	check(panel.logic_panel.graph == root.level_logic, "Save As rebinds the existing logic editor to the native graph copy")
	panel.set_mode(0); await frames(tree)
	check(browser.entries.has(FIRST) and browser.entries.has(COPY) and browser.entries[COPY].level_id == copy_id, "browser shows original and Save As copy with distinct registered IDs")
	# FileSystem signals are the same notification path used by native file operations.
	await open(tree, CUSTOM); await save(tree, CUSTOM)
	var custom_id := str(EditorInterface.get_edited_scene_root().level_id)
	await open(tree, FIRST)
	check(DirAccess.rename_absolute(ProjectSettings.globalize_path(CUSTOM), ProjectSettings.globalize_path(MOVED)) == OK, "private scene moves on disk")
	EditorInterface.get_file_system_dock().files_moved.emit(CUSTOM, MOVED)
	await frames(tree)
	panel.set_mode(0)
	check(browser.entries.has(MOVED) and not browser.entries.has(CUSTOM) and str(browser.entries[MOVED].level_id) == custom_id, "native move notifications refresh the browser and retain stable IDs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MOVED))
	EditorInterface.get_file_system_dock().file_removed.emit(MOVED)
	await frames(tree)
	check(not browser.entries.has(MOVED) and LEVELS.load_book().catalog.by_id(custom_id).is_empty(), "native delete notifications remove stale browser/index entries")
	# New uses Godot's inherited-scene command; no file is written before native Save As.
	panel._new_browser_level(); await frames(tree, 16)
	var created := EditorInterface.get_edited_scene_root()
	check(created != null and created.get_script() == WORLD and created.scene_file_path.is_empty() and panel.mode_stack.current_tab == 1, "New Level opens an unsaved native inherited scene in Level Editing")
	check(FileAccess.get_sha256(TEMPLATE) == template_hash, "creating a map never overwrites the built-in template")
	var new_path := "res://content/scenes/levels/browser_new.tscn"
	await save(tree, new_path)
	var created_id := str(EditorInterface.get_edited_scene_root().level_id)
	panel.set_mode(0); await frames(tree)
	var saved: PackedScene = ResourceLoader.load(new_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved != null and saved.get_state().get_base_scene_state() != null and browser.entries.has(new_path) and not created_id.is_empty(), "native Save As keeps template inheritance and adds the new map to the browser")
	browser.select_file(new_path)
	await frames(tree)
	check(browser.selected_path == new_path and browser.details.text.contains(new_path), "selected details stay synchronized after save and file refresh")
	if DisplayServer.get_name() != "headless" and not output.is_empty():
		# Use a visible registered card for the library screenshot when author maps exist in this private copy.
		browser.select_file(str(browser.entries.keys()[0])); await frames(tree)
		var bounds: Rect2 = suite.window.get_visible_rect()
		check(bounds.encloses(browser.open_button.get_global_rect()) and bounds.encloses(browser.locate_button.get_global_rect()), "detail actions stay within the visible window")
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png(output.path_join("my_levels.png"))
	panel.set_mode(1); await frames(tree)
	if DisplayServer.get_name() != "headless" and not output.is_empty():
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png(output.path_join("level_editor.png"))
	check(panel.logic_panel.graph == EditorInterface.get_edited_scene_root().level_logic and panel.mode_buttons["关卡编辑"].button_pressed, "returning from the browser retains the current native graph editor")
	print("LEVEL BROWSER TEST: ", checks, " checks, ", failures, " failures")
	tree.quit(0 if failures == 0 else 1)
