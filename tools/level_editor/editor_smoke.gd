@tool
extends RefCounted
## Runs in a separate headless editor, using the real EditorInterface/undo manager.
static func run(editor: EditorPlugin) -> void:
	var results := []
	var tree := editor.get_tree()
	for _i in 40:
		if not EditorInterface.get_resource_filesystem().is_scanning(): break
		await tree.create_timer(0.1, true).timeout
	await tree.create_timer(0.3, true).timeout
	var path := "res://tools/level_editor/.editor_smoke_%d.tscn" % OS.get_process_id()
	var factory := preload("res://addons/branch_level_editor/scene_factory.gd")
	var room := factory.room("smoke_room")
	factory.save_scene(room, path)
	room.free()
	EditorInterface.open_scene_from_path(path)
	for attempt in 60:
		var candidate := EditorInterface.get_edited_scene_root()
		if candidate != null and candidate.scene_file_path == path: break
		if attempt % 15 == 14: EditorInterface.open_scene_from_path(path)
		await tree.create_timer(0.05, true).timeout
	var root := EditorInterface.get_edited_scene_root()
	results.append([root != null and root.get_script() == factory.ROOM, "native editor opens authored room"])
	editor._configure_snap()
	results.append([is_equal_approx(EditorInterface.get_node_3d_translate_snap(), 0.1) and EditorInterface.is_node_3d_snap_enabled(), "native 3D translation snap is enabled at 0.1"])
	if root == null or root.get_script() != factory.ROOM:
		push_error("EDITOR SMOKE: temporary room did not open")
		tree.quit(1)
		return
	results.append([editor.shape_grid.get_child_count() == 16, "whitebox library shows all 16 shape previews"])
	var payload: Dictionary = editor.shape_grid.get_child(0).drag_payload()
	results.append([payload.type == "files" and ResourceLoader.load(payload.files[0]) is PackedScene, "preview produces Godot native scene drag data"])
	var room_wireframe := false
	for child in root.get_children():
		if child.get_meta("branch_room_preview", false) and child is MeshInstance3D:
			room_wireframe = child.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_LINES
	results.append([room_wireframe, "Room preview is wireframe rather than a false placement surface"])
	var count := root.get_child_count()
	editor.palette.select(1)
	editor._add_spatial()
	for _i in 3: await tree.process_frame
	results.append([root.get_child_count() == count + 1, "palette adds owned scene object"])
	results.append([root.get_child(root.get_child_count() - 1).size == Vector3.ONE, "adding from palette always starts at unit size"])
	var selected := EditorInterface.get_selection().get_selected_nodes()
	results.append([selected.size() == 1 and selected[0].owner == root, "new object links to native inspector/viewport selection"])
	var manager := editor.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(root))
	history.undo()
	results.append([root.get_child_count() == count, "native scene undo removes placed object"])
	history.redo()
	results.append([root.get_child_count() == count + 1, "native scene redo restores placed object"])
	var source := root.get_child(root.get_child_count() - 1)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(source)
	editor._duplicate_spatial()
	for _i in 3: await tree.process_frame
	var copy := root.get_child(root.get_child_count() - 1)
	results.append([copy != source and copy.object_id != source.object_id, "spatial duplicate receives new stable ID"])
	var original_size: Vector3 = copy.size
	copy.scale = Vector3(1.26, 0.02, 2.34)
	for _i in 2: await tree.process_frame
	results.append([copy.scale.is_equal_approx(Vector3(1.3, 0.1, 2.3)), "native scale gizmo snaps to 0.1 and keeps positive minimum"])
	copy.scale = Vector3.ONE
	var custom_gizmo := EditorNode3DGizmo.new()
	custom_gizmo.set_node_3d(copy)
	copy.size = Vector3(2.26, 1, 1)
	editor.gizmos._commit_handle(custom_gizmo, 0, false, original_size, false)
	results.append([copy.size.is_equal_approx(Vector3(2.3, 1, 1)), "stretch handle commits quantized dimensions"])
	history.undo()
	results.append([copy.size == original_size, "stretch handle uses native scene undo"])
	history.redo()
	results.append([copy.size.is_equal_approx(Vector3(2.3, 1, 1)), "stretch handle redo restores exact dimensions"])
	editor.gizmos._commit_handle(custom_gizmo, 0, false, original_size, true)
	results.append([copy.size == original_size, "cancelled stretch restores original dimensions"])
	var face_edit := preload("res://addons/branch_level_editor/face_edit.gd")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = copy.position + Vector3(2, 3, 2)
	camera.look_at(copy.global_position)
	var screen := camera.unproject_position(copy.global_position + Vector3(0, 0.5, 0))
	editor.push_pull.set_enabled(true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen
	results.append([editor._forward_3d_gui_input(camera, press) == EditorPlugin.AFTER_GUI_INPUT_STOP and editor.push_pull.dragging and editor.push_pull.picked.get("block") == copy, "viewport click selects the actual whitebox face and starts push pull"])
	var face_before := face_edit.capture(copy)
	var motion := InputEventMouseMotion.new()
	motion.position = screen + editor.push_pull.screen_axis * 0.26
	var pushed: bool = editor._forward_3d_gui_input(camera, motion) == EditorPlugin.AFTER_GUI_INPUT_STOP and is_equal_approx(editor.push_pull.amount, 0.3)
	var after_faces: PackedVector3Array = copy.geometry().get_faces()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = screen
	editor._forward_3d_gui_input(camera, release)
	results.append([pushed and copy.has_mesh_edit() and not editor.push_pull.dragging, "face push pull commits a real geometry edit on mouse release"])
	history.undo()
	results.append([copy.mesh_edit == face_before.mesh_edit and copy.transform == face_before.transform, "native undo restores face geometry and anchored transform together"])
	history.redo()
	results.append([copy.geometry().get_faces() == after_faces, "native redo restores exact pushed vertices"])
	editor.push_pull.begin(camera, camera.unproject_position(copy.global_position + Vector3(0, copy.size.y * 0.5, 0)))
	var cancel_before := face_edit.capture(copy)
	var cancel_version := history.get_version()
	editor.push_pull.preview_distance(0.2)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	editor._forward_3d_gui_input(camera, escape)
	results.append([face_edit.capture(copy) == cancel_before and not editor.push_pull.dragging and history.get_version() == cancel_version, "Escape cancels a push without adding history or leaving changed vertices"])
	editor.push_pull.set_enabled(false)
	camera.free()
	if OS.get_cmdline_user_args().has("--capture-face"):
		EditorInterface.set_main_screen_editor("3D")
		for _i in 5: await tree.process_frame
		var view := EditorInterface.get_editor_viewport_3d(0)
		var view_camera := view.get_camera_3d()
		editor.push_buttons[0].button_pressed = true
		var started: bool = editor.push_pull.begin(view_camera, view_camera.unproject_position(copy.global_position + Vector3(0, copy.size.y * 0.5, 0)))
		if started:
			editor.push_pull.preview_distance(0.3)
		for tabs in EditorInterface.get_base_control().find_children("*", "TabContainer", true, false):
			for tab_index in tabs.get_tab_count():
				var tab: Control = tabs.get_tab_control(tab_index)
				if tab == editor.dock_scroll or tab.is_ancestor_of(editor.dock_scroll): tabs.current_tab = tab_index
		for _i in 6: await tree.process_frame
		await RenderingServer.frame_post_draw
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://docs/level_editor/face_push_pull.png")
		editor.push_pull.finish(true)
		editor.push_buttons[0].button_pressed = false
	var saved_count: int = root.get_children().filter(func(child: Node): return child.owner == root).size()
	editor._save_scene()
	for _i in 5: await tree.process_frame
	root = EditorInterface.get_edited_scene_root()
	var reloaded: Node = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	results.append([reloaded.get_child_count() == saved_count and root.get_children().filter(func(child: Node): return child.owner == root).size() == saved_count, "native save reload keeps placed and copied objects"])
	reloaded.free()
	EditorInterface.close_scene()
	EditorInterface.set_main_screen_editor("关卡与世界")
	EditorInterface.open_scene_from_path("res://scenes/level_editor/continuous_world.tscn")
	for _i in 10: await tree.process_frame
	editor.panel.dirty = false
	editor.panel.use_current_world()
	editor.panel.mode.select(1)
	editor.panel._switch_graph()
	if OS.get_cmdline_user_args().has("--save-demo-layout"):
		await editor.panel.arrange_all()
		editor.panel.save_graph()
		editor.panel.mode.select(0)
		editor.panel._switch_graph()
		await editor.panel.arrange_all()
		editor.panel.save_graph()
		editor.panel.mode.select(1)
		editor.panel._switch_graph()
	var world := EditorInterface.get_edited_scene_root()
	var goal: Node = world.object_by_id("puzzle_3/goal_region")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(goal)
	for _i in 3: await tree.process_frame
	results.append([editor.panel.selected_id == "goal_3", "3D object selection locates corresponding graph node"])
	editor.panel._select_graph_node(editor.panel.canvas.get_node("source_1"))
	selected = EditorInterface.get_selection().get_selected_nodes()
	results.append([selected.has(world.object_by_id("puzzle_1/door")), "graph node selection locates native 3D object"])
	editor.panel._show_picker()
	editor.panel.search.text = "比较两个数值"
	editor.panel._filter_choices()
	results.append([editor.panel.choices.item_count == 1, "search menu filters node palette"])
	var nodes_before: int = editor.panel.graph.nodes.size()
	editor.panel._add_choice()
	results.append([editor.panel.graph.nodes.size() == nodes_before + 1, "search palette adds graph node"])
	editor.panel.undo.undo()
	results.append([editor.panel.graph.nodes.size() == nodes_before, "graph add is undoable inside editor"])
	editor.panel.search.text = ""
	editor.panel.node_category.select(1)
	editor.panel._filter_choices()
	var only_triggers: bool = editor.panel.choices.item_count > 0
	for i in editor.panel.choices.item_count:
		only_triggers = only_triggers and editor.GRAPH.category(editor.panel.choices.get_item_metadata(i)) == "触发"
	results.append([only_triggers, "node library filters readable trigger category"])
	editor.panel.picker.hide()
	editor.panel.dirty = false
	EditorInterface.open_scene_from_path("res://scenes/level_editor/logic_playground.tscn")
	for _i in 8: await tree.process_frame
	editor.panel.use_current_world()
	editor.panel.mode.select(1)
	editor.panel._switch_graph()
	editor.panel._select_graph_node(editor.panel.canvas.get_node("enter"))
	results.append([EditorInterface.get_selection().get_selected_nodes().has(EditorInterface.get_edited_scene_root().rooms()[0]), "player-enters-Room node selects the actual 3D Room"])
	var demo_world := EditorInterface.get_edited_scene_root()
	var original_room: Node = demo_world.rooms()[0]
	var original_room_id: String = original_room.room_id
	editor._duplicate_spatial()
	for _i in 3: await tree.process_frame
	var copied_room: Node = demo_world.rooms().back()
	results.append([demo_world.rooms().size() == 2 and copied_room.room_id != original_room_id and copied_room.object_by_id("floor") != null, "Room copy keeps contents with a fresh instance scope"])
	results.append([copied_room.object_by_id("floor").owner == demo_world, "copied Room contents remain owned and serializable"])
	var demo_history := manager.get_history_undo_redo(manager.get_object_history_id(demo_world))
	demo_history.undo()
	results.append([demo_world.rooms().size() == 1, "Room copy participates in native undo"])
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(original_room)
	editor.panel._show_picker()
	editor.panel.search.text = "玩家进入房间时"
	editor.panel._filter_choices()
	editor.panel._add_choice()
	results.append([editor.panel.graph.nodes.back().params.room == original_room_id, "new trigger automatically binds the selected Room"])
	editor.panel.undo.undo()
	editor.panel.picker.hide()
	editor.panel.dirty = false
	var layout_before: Dictionary = editor.panel.graph.snapshot()
	var semantic_before: String = editor.panel.graph.semantic_hash()
	await editor.panel.arrange_all()
	for _i in 3: await tree.process_frame
	results.append([editor.panel.graph.semantic_hash() == semantic_before, "automatic layout preserves execution semantics"])
	editor.panel.undo.undo()
	results.append([editor.panel.graph.positions == layout_before.positions, "automatic layout is undoable"])
	editor.panel.dirty = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var failed := 0
	for result in results:
		if not result[0]: failed += 1
		print("[PASS] " if result[0] else "[FAIL] ", result[1])
	print("LEVEL EDITOR NATIVE: %d passed / %d failed" % [results.size() - failed, failed])
	if OS.get_cmdline_user_args().has("--capture-v2"):
		EditorInterface.set_main_screen_editor("关卡与世界")
		editor.panel.show()
		await editor.panel.arrange_all()
		if OS.get_cmdline_user_args().has("--save-demo-layout"): editor.panel.save_graph()
		editor.panel.canvas.zoom = 0.65
		editor.panel.focus_object(original_room)
		editor.panel.status.text = "触发 → 判断 → 操作。白盒缩略图可以直接拖入 3D 场景。"
		editor.message.text = "白盒拖入场地后，面手柄拉伸／角点整体缩放；0.1 吸附。"
		for tabs in EditorInterface.get_base_control().find_children("*", "TabContainer", true, false):
			for index in tabs.get_tab_count():
				var tab: Control = tabs.get_tab_control(index)
				if tab == editor.dock_scroll or tab.is_ancestor_of(editor.dock_scroll): tabs.current_tab = index
		for _i in 10: await tree.process_frame
		await RenderingServer.frame_post_draw
		var screenshot := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		screenshot.save_png("res://docs/level_editor/editor_v2.png")
		print("V2 EDITOR CAPTURE: saved")
		editor.panel.dirty = false
	if OS.get_cmdline_user_args().has("--capture-presentation"):
		var capture: Script = load("res://tools/level_editor/capture_presentation.gd")
		if not await capture.run(editor): failed += 1
	tree.quit(1 if failed else 0)
