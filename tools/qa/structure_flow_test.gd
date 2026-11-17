@tool
extends RefCounted
const ROOT := "res://addons/godot_level_editor"
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
var checks := 0
var failures := 0
var output := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func frames(tree: SceneTree, count := 8) -> void:
	for index in count: await tree.process_frame

func open_scene(tree: SceneTree, path: String) -> Node:
	EditorInterface.get_resource_filesystem().update_file(path)
	await frames(tree)
	EditorInterface.open_scene_from_path(path)
	for attempt in 200:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path:
			await frames(tree)
			return root
		await tree.create_timer(0.03, true).timeout
	return null

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(85, true).timeout.connect(func(): tree.quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="): output = arg.trim_prefix("--qa-output=")
	await tree.create_timer(4.0, true).timeout
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await tree.process_frame
	var directory := "res://content/scenes/levels/qa_structure_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var original_path := directory + "/original.tscn"
	var copy_path := directory + "/copy.tscn"
	var file: FileAccess
	EditorInterface.open_scene_from_path(ROOT + "/templates/empty_level.tscn", true)
	await frames(tree, 20)
	var root := EditorInterface.get_edited_scene_root()
	check(root != null and root.get_script() == load(ROOT + "/modules/godot_level_editor/runtime/world.gd"), "native New Inherited Scene opens the plugin template")
	if root == null: tree.quit(1); return
	suite.open_tab("关卡")
	await frames(tree)
	var initial_panel: Control = suite.level_panel.logic_panel
	check(not initial_panel.save_graph() and initial_panel.status.text.contains("另存为"), "unsaved level graph Save explains the required native Save As")
	EditorInterface.save_scene_as(original_path, false)
	check(FileAccess.file_exists(original_path), "first native save finishes")
	await frames(tree, 20)
	var original_id := str(root.level_id)
	var book := LEVELS.load_book()
	check(not original_id.is_empty() and book.catalog != null and str(book.catalog.by_id(original_id).get("scene_path", "")) == original_path, "first native save registers the level for task selection")
	if DisplayServer.get_name() != "headless":
		for attempt in 600:
			if not suite.level_preview.is_busy(): break
			await tree.process_frame
		book = LEVELS.load_book()
		check(FileAccess.file_exists(str(book.catalog.by_id(original_id).get("preview_path", ""))), "native save automatically publishes the map thumbnail")
	var original_bytes := FileAccess.get_file_as_bytes(original_path)
	var original_graph: Resource = root.level_logic
	var original_semantic: String = original_graph.semantic_hash()
	suite.open_tab("关卡")
	await frames(tree)
	EditorInterface.save_scene_as(copy_path, false)
	check(FileAccess.file_exists(copy_path), "native Save As finishes without a second user save")
	await frames(tree, 20)
	var packed: PackedScene = ResourceLoader.load(copy_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var disk: Node = packed.instantiate()
	var copy_id := str(disk.level_id)
	book = LEVELS.load_book()
	print("STRUCTURE_SAVE_AS original=", original_id, " live=", root.level_id, " disk=", copy_id)
	check(not copy_id.is_empty() and copy_id != original_id, "Save As writes a distinct level ID on its first save")
	check(str(root.level_id) == copy_id, "Save As leaves live and disk identities consistent")
	check(book.catalog != null and str(book.catalog.by_id(copy_id).get("scene_path", "")) == copy_path, "Save As immediately registers its new path for task selection")
	check(book.catalog != null and str(book.catalog.by_id(original_id).get("scene_path", "")) == original_path and FileAccess.get_file_as_bytes(original_path) == original_bytes, "Save As preserves the original level identity and authored bytes")
	check(original_graph.semantic_hash() == original_semantic, "Save As does not mutate the original shared graph")
	check(root.level_logic != original_graph and root.level_logic.graph_id != original_graph.graph_id, "Save As owns independent graph resources and graph IDs")
	disk.free()
	suite.open_tab("关卡")
	await frames(tree)
	var panel: Control = suite.level_panel.logic_panel
	check(panel.world == root and panel.graph == root.level_logic, "level page edits the current native scene graph")
	panel.node_category.select(0); panel.search.text = "constant"; panel._filter_choices()
	for index in panel.choices.item_count:
		if panel.choices.get_item_metadata(index) == "constant": panel.choices.select(index); break
	var before: int = panel.graph.nodes.size()
	panel._add_choice()
	check(panel.graph.nodes.size() == before + 1 and panel.dirty, "node search and add use the current level graph")
	check(original_graph.semantic_hash() == original_semantic, "editing the copied level leaves the original graph unchanged")
	panel.undo.undo(); check(panel.graph.nodes.size() == before, "level graph Undo restores the graph")
	panel.undo.redo(); check(panel.graph.nodes.size() == before + 1, "level graph Redo restores the authored node")
	check(panel.save_graph(), "level graph Save uses the native scene save route")
	await frames(tree)
	packed = ResourceLoader.load(copy_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	disk = packed.instantiate()
	check(disk.level_logic.nodes.size() == before + 1, "level graph node persists after reopening the scene from disk")
	disk.free()
	panel.save_reload()
	check(panel.graph.nodes.size() == before + 1, "level graph Save and Reload preserves the authored node")
	var inherited_path := directory + "/inherited_copy.tscn"
	file = FileAccess.open(inherited_path, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="' + original_path + '" id="1"]\n[node name="InheritedCopy" instance=ExtResource("1")]\n')
	file.close()
	var inherited := await open_scene(tree, inherited_path)
	check(inherited != null, "a second generation inherited level opens")
	if inherited != null:
		EditorInterface.save_scene_as(inherited_path, false)
		await frames(tree, 20)
		book = LEVELS.load_book()
		check(str(inherited.level_id) != original_id and str(inherited.level_id) != copy_id and str(book.catalog.by_id(str(inherited.level_id)).get("scene_path", "")) == inherited_path, "saving an inherited copy registers a third independent level")
		check(FileAccess.get_file_as_bytes(original_path) == original_bytes, "saving an inherited copy preserves its source scene")
		packed = ResourceLoader.load(inherited_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		check(packed.get_state().get_node_instance(0) != null, "identity assignment retains native scene inheritance")
	# Overwrite a registered destination in this disposable project. Its tasks
	# must keep their destination ID rather than leaving two index rows per path.
	var custom_directory := "res://qa_native_maps_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(custom_directory)
	var overwrite_path := custom_directory + "/overwrite.tscn"
	book = LEVELS.load_book()
	var destination_id: String = book.catalog.allocate_id()
	file = FileAccess.open(overwrite_path, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="' + ROOT + '/templates/empty_level.tscn" id="1"]\n[node name="OverwriteDestination" instance=ExtResource("1")]\nlevel_id = "' + destination_id + '"\n')
	file.close()
	load(ROOT + "/modules/godot_level_editor_suite/native_level_registry.gd").saved(overwrite_path)
	root = await open_scene(tree, original_path)
	EditorInterface.save_scene_as(overwrite_path, false)
	await frames(tree, 20)
	book = LEVELS.load_book()
	check(book.catalog != null and str(root.level_id) == destination_id and str(book.catalog.by_id(destination_id).get("scene_path", "")) == overwrite_path, "Save As over an indexed destination preserves its task level ID")
	var matches := 0
	if book.catalog != null:
		for row in book.catalog.levels:
			if str(row.scene_path) == overwrite_path: matches += 1
	check(matches == 1, "overwriting a level keeps one valid index row for its native path")
	check(FileAccess.get_file_as_bytes(original_path) == original_bytes, "overwriting another destination preserves the source scene")
	if DisplayServer.get_name() != "headless":
		for attempt in 600:
			if not suite.level_preview.is_busy(): break
			await tree.process_frame
		book = LEVELS.load_book()
		check(FileAccess.file_exists(str(book.catalog.by_id(destination_id).get("preview_path", ""))), "native save publishes thumbnails for maps outside the default levels folder")
	var npc_path := "res://content/resources/enemies/qa_structure_%d.tres" % OS.get_process_id()
	var npc: Resource = ResourceLoader.load(ROOT + "/resources/enemies/samples_v1/human_medium_female.tres", "", ResourceLoader.CACHE_MODE_IGNORE).duplicate(true)
	npc.appearance.height = 2.6
	var store = load(ROOT + "/modules/enemy_editor/definition_store.gd")
	check(store.save_definition(npc, npc_path) == OK, "a personal copy of a rigged NPC saves outside the addon")
	suite.open_tab("敌人")
	await frames(tree)
	var workspace: Control = suite.asset_panels["敌人"]
	workspace.reload_catalog()
	var npc_entry: Dictionary = workspace.entries.get(npc_path, {})
	check(str(npc_entry.get("metadata", "")).contains("2.60 m") and str(npc_entry.get("preview_path", "")).is_empty(), "personal NPC cards show current height and do not reuse the source sample thumbnail")
	for title in ["工作台", "事件与任务", "任务图", "机关", "台本", "敌人", "天空", "其他", "关卡"]:
		suite.open_tab(title); await frames(tree)
		check(suite.tabs.get_tab_title(suite.tabs.current_tab) == title, "normal navigation opens " + title)
	if DisplayServer.get_name() != "headless" and not output.is_empty():
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png(output.path_join("native_level_flow.png"))
	print("STRUCTURE FLOW: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
