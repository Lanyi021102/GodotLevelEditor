@tool
extends RefCounted
const GROUPS := preload("res://addons/godot_level_editor/scene_groups.gd")
static func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(60, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.5, true).timeout
	var path := "res://tools/godot_level_editor_suite/native_drag_probe_%d.tscn" % OS.get_process_id()
	var source: Node3D = load("res://addons/godot_level_editor/runtime/world.gd").new()
	source.name = "DragProbe"
	source.world_id = "drag_probe"; source.start_room_id = ""
	source.topology = load("res://addons/godot_level_editor/runtime/level_graph.gd").new(); source.topology.graph_kind = "topology"
	source.events = load("res://addons/godot_level_editor/runtime/level_graph.gd").new()
	preload("res://addons/godot_level_editor/scene_factory.gd").block(source, "floor", Vector3(20, 0.4, 20), Vector3(0, -0.2, 0))
	preload("res://addons/godot_level_editor/scene_factory.gd").save_scene(source, path)
	source.free()
	EditorInterface.get_resource_filesystem().update_file(path)
	for i in 10: await tree.process_frame
	EditorInterface.open_scene_from_path(path)
	for i in 100:
		var candidate := EditorInterface.get_edited_scene_root()
		if candidate != null and candidate.scene_file_path == path: break
		if i % 20 == 19: EditorInterface.open_scene_from_path(path)
		await tree.create_timer(0.05, true).timeout
	EditorInterface.set_main_screen_editor("3D")
	suite.open_tab("关卡")
	for i in 10: await tree.process_frame
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		print("WAREHOUSE NATIVE DROP: FAIL temporary scene did not open actual=",root.scene_file_path if root != null else "null"); tree.quit(1); return
	var failures := 0
	var checks := 0
	var editor: EditorPlugin = suite.modules.level
	var undo: UndoRedo = editor.get_undo_redo().get_history_undo_redo(editor.get_undo_redo().get_object_history_id(root))
	var recent_before: PackedStringArray = editor.radial_tool.recent.duplicate()
	var main := EditorInterface.get_base_control().get_window()
	var target: Control = EditorInterface.get_editor_viewport_3d(0).get_parent()
	var point := target.get_global_rect().get_center()
	suite.level_panel.set_mode(1)
	suite.window.hide()
	main.grab_focus()
	await tree.create_timer(0.3, true).timeout
	var assets := preload("res://addons/godot_level_editor/asset_catalog.gd")
	for category in assets.CATEGORIES:
		if EditorInterface.get_edited_scene_root() != root:
			print("WAREHOUSE NATIVE DROP: fixture switched unexpectedly to ", EditorInterface.get_edited_scene_root().scene_file_path)
			tree.quit(1); return
		var asset: Dictionary = assets.assets(category)[0]
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(root)
		var before := root.find_children("*", "Node3D", true, false).size()
		var group_kind: String = GROUPS.CATEGORIES.get(category, "")
		var group_before := GROUPS.find_group(root, group_kind) if not group_kind.is_empty() else null
		var preview := Label.new(); preview.text = asset.title
		# Native viewport receives the exact standard Godot files payload from the warehouse card.
		target.force_drag({"type": "files", "files": PackedStringArray([asset.path])}, preview)
		for i in 3: await tree.process_frame
		var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point; main.push_input(motion, true)
		for i in 3: await tree.process_frame
		var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = point; press.global_position = point
		main.push_input(press, true)
		press.pressed = false; main.push_input(press, true)
		for i in 20: await tree.process_frame
		var selected := EditorInterface.get_selection().get_selected_nodes()
		var placed: Node3D = selected[0] if selected.size() == 1 else null
		var ok: bool = placed != null and root.find_children("*", "Node3D", true, false).size() > before and (group_kind.is_empty() or (placed.get_parent() == GROUPS.find_group(root, group_kind) and GROUPS.is_group(placed.get_parent())))
		print("[PASS] " if ok else "[FAIL] ", "native viewport drop from wheel catalog ", category)
		if not ok: failures += 1
		checks += 1
		if ok:
			var at: Transform3D = placed.global_transform
			undo.undo()
			var undo_ok: bool = not placed.is_inside_tree() and (group_kind.is_empty() or GROUPS.find_group(root, group_kind) == group_before)
			undo.redo()
			var redo_ok: bool = placed.is_inside_tree() and placed.global_transform.is_equal_approx(at)
			print("[PASS] " if undo_ok and redo_ok else "[FAIL] ", "drop grouping shares one undo action and preserves transform: ", category)
			checks += 1
			if not undo_ok or not redo_ok: failures += 1
	var before_batch: Array[Node] = GROUPS.contents(root)
	var preview_batch := Label.new(); preview_batch.text = "批量素材"
	target.force_drag({"type": "files", "files": PackedStringArray([assets.assets("Layout 白盒")[1].path, assets.assets("常驻 NPC")[0].path])}, preview_batch)
	for i in 3: await tree.process_frame
	var batch_motion := InputEventMouseMotion.new(); batch_motion.position = point; batch_motion.global_position = point; main.push_input(batch_motion, true)
	for i in 3: await tree.process_frame
	var batch_click := InputEventMouseButton.new(); batch_click.button_index = MOUSE_BUTTON_LEFT; batch_click.pressed = true; batch_click.position = point; batch_click.global_position = point; main.push_input(batch_click, true)
	batch_click.pressed = false; main.push_input(batch_click, true)
	for i in 20: await tree.process_frame
	var batch_selection := EditorInterface.get_selection().get_selected_nodes()
	var added: Array[Node] = GROUPS.contents(root).filter(func(node: Node): return not before_batch.has(node))
	var batch_ok: bool = added.size() == 2 and added.all(func(node: Node): return GROUPS.is_group(node.get_parent()))
	print("BATCH selection=", batch_selection.size(), " added=", added.size(), " before=", before_batch.size(), " after=", GROUPS.contents(root).size())
	undo.undo()
	print("BATCH undo count=", GROUPS.contents(root).size(), " equals=", GROUPS.contents(root) == before_batch)
	batch_ok = batch_ok and GROUPS.contents(root) == before_batch
	undo.redo()
	batch_ok = batch_ok and GROUPS.contents(root).size() == before_batch.size() + 2
	print("[PASS] " if batch_ok else "[FAIL] ", "mixed-category batch drop groups each asset and undoes atomically")
	checks += 1
	if not batch_ok: failures += 1
	for i in 3: await tree.process_frame
	var idle_ok: bool = editor.asset_drop_tool.surfaces.all(func(surface: Control): return surface.mouse_filter == Control.MOUSE_FILTER_IGNORE) and editor.radial_tool.active_asset.is_empty() and not is_instance_valid(editor.radial_tool.ghost)
	print("[PASS] " if idle_ok else "[FAIL] ", "drop interception and temporary preview are cleared after the gesture")
	checks += 1
	if not idle_ok: failures += 1
	var npc_group := GROUPS.find_group(root, "npc")
	var npc: Node3D = npc_group.get_child(0)
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(npc)
	editor._duplicate_spatial()
	for i in 3: await tree.process_frame
	var npc_copy: Node3D = EditorInterface.get_selection().get_selected_nodes()[0]
	var copy_ok: bool = npc_copy != npc and npc_copy.get_parent() == npc_group and npc_copy.object_id != npc.object_id and npc_copy.get_node("EntityProperties").owner == root
	var copy_path := root.get_path_to(npc_copy)
	var packed := PackedScene.new(); var pack_error := packed.pack(root)
	var restored := packed.instantiate()
	copy_ok = copy_ok and pack_error == OK and restored.has_node(copy_path) and restored.get_node(copy_path).object_id == npc_copy.object_id and restored.get_node(copy_path).has_node("EntityProperties")
	restored.free()
	undo.undo(); copy_ok = copy_ok and not npc_copy.is_inside_tree()
	undo.redo(); copy_ok = copy_ok and npc_copy.is_inside_tree() and npc_copy.get_parent() == npc_group
	print("[PASS] " if copy_ok else "[FAIL] ", "grouped NPC duplication preserves binding ownership, new IDs, serialization and undo")
	checks += 1
	if not copy_ok: failures += 1
	var legacy_ok: bool = root.get_node("Floor").get_parent() == root
	print("[PASS] " if legacy_ok else "[FAIL] ", "existing root content stays in its original hierarchy")
	checks += 1
	if not legacy_ok: failures += 1
	if OS.get_cmdline_user_args().has("--capture-groups"):
		var directory := "res://docs/level_editor/content_groups_2026-11-16"
		DirAccess.make_dir_recursive_absolute(directory)
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(npc_group); EditorInterface.edit_node(npc_group)
		await tree.create_timer(0.3, true).timeout
		RenderingServer.force_draw(false)
		main.get_texture().get_image().save_png(directory + "/自动分组_原生编辑器.png")
	editor.radial_tool.recent = recent_before
	EditorInterface.get_editor_settings().set_project_metadata(editor.radial_tool.METADATA, "recent", recent_before)
	EditorInterface.open_scene_from_path("res://scenes/main.tscn")
	for i in 10: await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("WAREHOUSE NATIVE DROP: ", checks, " checks, ", failures, " failures")
	tree.quit(0 if failures == 0 else 1)
