@tool
extends RefCounted
const FACTORY := preload("res://addons/godot_level_editor/scene_factory.gd")
const EDIT := preload("res://addons/godot_level_editor/face_edit.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)

func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame

func gizmo_scale(camera: Camera3D, pivot: Vector3) -> float:
	var cam_z := -camera.global_basis.z.normalized()
	var depth := absf(Plane(cam_z, camera.global_position).distance_to(pivot))
	var point := camera.global_position + cam_z * depth
	var pixels := absf(camera.unproject_position(point).y - camera.unproject_position(point - camera.global_basis.y).y)
	var ui_scale := maxf(1, EditorInterface.get_editor_scale())
	var height: float = camera.get_viewport().get_parent().size.y
	return float(EditorInterface.get_editor_settings().get_setting("editors/3d/manipulator_gizmo_size")) / maxf(pixels, 0.00001) * ui_scale * minf(400 * ui_scale, height) / (400 * ui_scale)

func run(editor: EditorPlugin) -> void:
	var tree := editor.get_tree()
	tree.create_timer(90, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.5, true).timeout
	var suite := tree.get_first_node_in_group("godot_level_editor_editor_suite")
	if suite != null: suite.window.hide()
	EditorInterface.set_main_screen_editor("3D")
	await frames(tree, 10)
	var original_step: float = editor.edit_step
	editor._set_edit_step(0.1)
	check(editor.radial_tool.button.text == "呼出轮盘" and editor.selection_buttons.face[0].text == "选中面" and editor.selection_buttons.edge[0].text == "选中线" and editor.selection_buttons.point[0].text == "选中点", "viewport toolbar exposes the wheel and all three selection modes")
	check(editor.step_input.get_parent().get_index() == editor.selection_buttons.point[0].get_index() + 1, "editable step controls sit immediately to the right of the selection modes")
	for index in editor.STEP_PRESETS.size():
		editor.step_presets.get_popup().id_pressed.emit(index)
		check(is_equal_approx(editor.edit_step, editor.STEP_PRESETS[index]) and is_equal_approx(EditorInterface.get_node_3d_translate_snap(), editor.STEP_PRESETS[index]), "step preset %s updates native translation snapping" % editor.STEP_PRESETS[index])
	editor.step_input.text = "0.25"; editor.step_input.text_submitted.emit("0.25")
	check(is_equal_approx(editor.edit_step, 0.25) and is_equal_approx(EditorInterface.get_node_3d_translate_snap(), 0.25), "custom typed step updates the actual native snapping value")
	editor.step_input.text = "0"; editor.step_input.text_submitted.emit("0")
	check(is_equal_approx(editor.edit_step, 0.25) and editor.step_input.text == "0.25", "invalid zero input restores the last valid step")
	editor._set_edit_step(0.1)
	var path := "res://tools/level_editor/face_gizmo_probe_%d.tscn" % OS.get_process_id()
	var source := Node3D.new(); source.name = "FaceGizmoProbe"
	FACTORY.block(source, "box", Vector3(4, 2, 4), Vector3(0, 1, 0))
	FACTORY.block(source, "other", Vector3(2, 2, 2), Vector3(-5, 1, 0))
	FACTORY.save_scene(source, path); source.free()
	EditorInterface.get_resource_filesystem().update_file(path)
	for i in 200:
		if not EditorInterface.get_resource_filesystem().is_scanning(): break
		await tree.create_timer(0.05, true).timeout
	await frames(tree, 10)
	EditorInterface.open_scene_from_path(path)
	for attempt in 600:
		var candidate := EditorInterface.get_edited_scene_root()
		if candidate != null and candidate.scene_file_path == path: break
		if attempt % 20 == 19: EditorInterface.open_scene_from_path(path)
		await tree.create_timer(0.05, true).timeout
	EditorInterface.set_main_screen_editor("3D")
	await frames(tree, 15)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		push_error("FACE GIZMO: fixture did not open; actual=" + (root.scene_file_path if root != null else "null")); tree.quit(1); return
	var block: Node3D = root.get_node("Box")
	var other: Node3D = root.get_node("Other")
	var view := EditorInterface.get_editor_viewport_3d(0)
	var view_camera := view.get_camera_3d()
	var tool: RefCounted = editor.push_pull
	var camera := Camera3D.new(); view.add_child(camera)
	camera.position = Vector3(7, 6, 8); camera.look_at(Vector3(0, 1, 0))
	var manager := editor.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(root))
	var before := EDIT.capture(block)
	var version := history.get_version()
	tool.set_enabled(true)
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	press.position = camera.unproject_position(Vector3(0, 2, 0))
	check(editor._forward_3d_gui_input(camera, press) == EditorPlugin.AFTER_GUI_INPUT_STOP and tool.picked.get("block") == block and not tool.dragging, "first click selects a face without starting a geometry drag")
	await frames(tree)
	tool.refresh()
	var gizmo: EditorNode3DGizmo = tool.gizmo_for(block)
	check(gizmo != null and gizmo.is_subgizmo_selected(tool.picked.triangle), "native transform gizmo selects the face subgizmo instead of the object pivot")
	var id: int = tool.picked.triangle
	var pivot: Transform3D = editor.gizmos._get_subgizmo_transform(gizmo, id)
	var restores: Array[Transform3D] = [pivot]
	check(block.to_global(pivot.origin).is_equal_approx(Vector3(0, 2, 0)), "axes are centered on the selected face")
	check(EDIT.capture(block) == before and history.get_version() == version, "face selection changes neither mesh nor undo history")
	for pair in [[0.25, 0.38, 0.5], [0.05, 0.03, 0.05]]:
		editor._set_edit_step(pair[0])
		tool.begin(camera, press.position)
		tool.preview_distance(pair[1])
		var pushed_pivot: Transform3D = editor.gizmos._get_subgizmo_transform(gizmo, id)
		check(is_equal_approx(tool.amount, pair[2]) and absf(block.to_global(pushed_pivot.origin).y - 2.0 - float(pair[2])) < 0.0001, "custom step %s changes real face displacement rather than just its label" % pair[0])
		tool.finish(true)
	editor._set_edit_step(0.1)
	await frames(tree)
	var target := pivot; target.origin += Vector3(0.3, 0.2, 0)
	editor.gizmos._set_subgizmo_transform(gizmo, id, target)
	check(tool.dragging and block.has_mesh_edit(), "native translation callback edits the selected surface")
	# A second preview must use the original vertices, despite block recentering.
	target.origin = pivot.origin + Vector3(0.4, 0.3, 0)
	editor.gizmos._set_subgizmo_transform(gizmo, id, target)
	var live_pivot: Transform3D = editor.gizmos._get_subgizmo_transform(gizmo, id)
	check(block.to_global(live_pivot.origin).distance_to(Vector3(0.4, 2.3, 0)) < 0.0001, "repeated previews do not accumulate displacement from recentering")
	editor.gizmos._commit_subgizmos(gizmo, PackedInt32Array([id]), restores, false)
	var translated := EDIT.capture(block)
	check(not tool.dragging and history.get_version() == version + 1, "one completed face drag creates one native undo action")
	history.undo()
	check(EDIT.capture(block) == before and gizmo.is_subgizmo_selected(id), "undo restores geometry and keeps the face selected")
	history.redo()
	check(EDIT.capture(block) == translated, "redo restores the translated face exactly")
	pivot = editor.gizmos._get_subgizmo_transform(gizmo, id)
	target = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15)) * pivot.basis, pivot.origin)
	editor.gizmos._set_subgizmo_transform(gizmo, id, target)
	var rotated := EDIT.capture(block)
	check(rotated != translated and tool.face.normal.distance_to(Vector3.UP) > 0.1, "rotation ring callback tilts the face around its center")
	editor.gizmos._commit_subgizmos(gizmo, PackedInt32Array([id]), restores, false)
	history.undo(); check(EDIT.capture(block) == translated, "face rotation is undoable independently of translation")
	history.redo(); check(EDIT.capture(block) == rotated, "face rotation redo restores exact saved vertices")
	version = history.get_version()
	pivot = editor.gizmos._get_subgizmo_transform(gizmo, id)
	target = pivot; target.origin += Vector3(0, 0.2, 0)
	editor.gizmos._set_subgizmo_transform(gizmo, id, target)
	editor.gizmos._commit_subgizmos(gizmo, PackedInt32Array([id]), restores, true)
	check(EDIT.capture(block) == rotated and history.get_version() == version, "native drag cancellation restores the mesh without history")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	var escape_result := editor._forward_3d_gui_input(camera, escape)
	await frames(tree)
	check(escape_result == EditorPlugin.AFTER_GUI_INPUT_STOP and tool.picked.is_empty() and not gizmo.is_subgizmo_selected(id) and EditorInterface.get_selection().get_selected_nodes().has(block), "Escape deselects only the face, restoring the original object manipulator")
	tool.select_face(camera, camera.unproject_position(block.to_global(EDIT.planar_face(block.geometry().get_faces(), id).center)))
	editor.gizmos._subgizmos_intersect_ray(gizmo, camera, Vector2(-10000, -10000))
	await frames(tree)
	check(tool.picked.is_empty() and not gizmo.is_subgizmo_selected(id) and EditorInterface.get_selection().get_selected_nodes().has(block), "clicking empty space restores object axes and keeps the object selected")
	tool.select_face(camera, camera.unproject_position(block.to_global(EDIT.planar_face(block.geometry().get_faces(), id).center)))
	editor.gizmos._subgizmos_intersect_ray(gizmo, camera, camera.unproject_position(other.global_position + Vector3(0, 1, 0)))
	await frames(tree)
	check(tool.picked.get("block") == other and EditorInterface.get_selection().get_selected_nodes() == [other], "one face click can switch directly to another block")
	tool.set_enabled(false)
	var packed := PackedScene.new(); packed.pack(root)
	var disk_path := "/tmp/branch_face_gizmo_saved_%d.tscn" % OS.get_process_id()
	ResourceSaver.save(packed, disk_path)
	var saved: Node3D = ResourceLoader.load(disk_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(saved.get_node("Box").mesh_edit == block.mesh_edit and saved.get_node("Box").transform == block.transform, "save and reload preserve translated and rotated face geometry")
	saved.free(); DirAccess.remove_absolute(disk_path)
	await component_checks(editor, block, camera, history, before)
	# Exercise actual native viewport input and render the real face manipulator.
	block.apply_face_state(before)
	tool.set_enabled(true)
	var window := EditorInterface.get_base_control().get_window()
	await frame_selection(view, window, tree)
	var zoom := InputEventMouseButton.new(); zoom.button_index = MOUSE_BUTTON_WHEEL_DOWN; zoom.pressed = true
	zoom.position = view.get_parent().get_global_transform() * (Vector2(view.size) * 0.5); zoom.global_position = zoom.position
	for i in 8: window.push_input(zoom, true)
	await frames(tree, 10)
	var face_screen := view_camera.unproject_position(Vector3(0.8, 2, 0.4))
	var click_point: Vector2 = view.get_parent().get_global_transform() * face_screen
	var motion := InputEventMouseMotion.new(); motion.position = click_point; motion.global_position = click_point
	window.push_input(motion, true)
	press.position = click_point; press.global_position = click_point; window.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate(); release.pressed = false; window.push_input(release, true)
	await frames(tree, 10)
	check(tool.picked.get("block") == block and not tool.dragging, "real native viewport click selects a face and leaves it ready for axis editing")
	if tool.picked.is_empty():
		print("NATIVE PICK DEBUG screen=", face_screen, " view=", view.size, " camera=", view_camera.global_transform, " mode=", tool.mode, " enabled=", tool.enabled)
		tree.quit(1); return
	# Hit a real native arrow, then move the mouse and release through the window.
	var frame: Transform3D = editor.gizmos._get_subgizmo_transform(gizmo, tool.picked.triangle)
	var world_pivot := block.to_global(frame.origin)
	var local_mode := false
	var local_key := InputEventKey.new(); local_key.keycode = KEY_T
	for button in editor.spatial_tools.get_parent().find_children("*", "Button", true, false):
		if button.shortcut != null and button.shortcut.matches_event(local_key): local_mode = button.button_pressed
	var axis: Vector3 = (block.global_basis * frame.basis.y).normalized() if local_mode else Vector3.UP
	var arrow := world_pivot + axis * gizmo_scale(view_camera, world_pivot) * 1.575
	var arrow_screen := view_camera.unproject_position(arrow)
	var move_screen := view_camera.unproject_position(arrow + axis * 0.4)
	var native_before := EDIT.capture(block)
	motion.position = view.get_parent().get_global_transform() * arrow_screen; motion.global_position = motion.position
	window.push_input(motion, true)
	press.position = motion.position; press.global_position = motion.position; window.push_input(press, true)
	motion.relative = move_screen - arrow_screen
	motion.position = view.get_parent().get_global_transform() * move_screen; motion.global_position = motion.position; motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	window.push_input(motion, true)
	await frames(tree)
	var native_dragged: bool = tool.dragging
	release.position = motion.position; release.global_position = motion.position; window.push_input(release, true)
	await frames(tree)
	check(native_dragged and not tool.dragging and EDIT.capture(block) != native_before, "real native arrow drag changes only the face and commits on mouse release")
	if not native_dragged: print("NATIVE ARROW DEBUG arrow=", arrow_screen, " end=", move_screen, " world=", arrow, " local=", local_mode, " face=", tool.picked, " viewport=", view.size)
	tool.clear()
	await frames(tree)
	# The restored manipulator must also work while face mode stays enabled.
	native_before = EDIT.capture(block)
	world_pivot = block.global_position
	axis = block.global_basis.y.normalized() if local_mode else Vector3.UP
	arrow = world_pivot + axis * gizmo_scale(view_camera, world_pivot) * 1.575
	arrow_screen = view_camera.unproject_position(arrow)
	move_screen = view_camera.unproject_position(arrow + axis * 0.4)
	motion.button_mask = 0; motion.position = view.get_parent().get_global_transform() * arrow_screen; motion.global_position = motion.position
	window.push_input(motion, true)
	press.position = motion.position; press.global_position = motion.position; window.push_input(press, true)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT; motion.relative = move_screen - arrow_screen
	motion.position = view.get_parent().get_global_transform() * move_screen; motion.global_position = motion.position; window.push_input(motion, true)
	release.position = motion.position; release.global_position = motion.position; window.push_input(release, true)
	await frames(tree)
	check(tool.picked.is_empty() and block.mesh_edit == native_before.mesh_edit and block.transform != native_before.transform, "restored original axes move the whole object while face mode remains enabled")
	# Capture a visible side so the entire manipulator fits within the viewport.
	var toward_camera := view_camera.global_position - block.global_position
	var side := Vector3.RIGHT * signf(toward_camera.x) if absf(toward_camera.x) > absf(toward_camera.z) else Vector3.BACK * signf(toward_camera.z)
	tool.select_face(view_camera, view_camera.unproject_position(block.global_position + side * 2))
	if OS.get_cmdline_user_args().has("--capture-face-gizmo"):
		await frames(tree, 10); RenderingServer.force_draw()
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://docs/level_editor/selection_tools_2026-11-16/selected_face.png")
		tool.clear(); await frames(tree, 10); RenderingServer.force_draw()
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://docs/level_editor/selection_tools_2026-11-16/object_axes.png")
	for mode in ["edge", "point"]:
		tool.set_mode(mode)
		await frames(tree)
		var bottom: Vector3 = block.global_position + Vector3(2 if mode == "point" else 0, -block.size.y * 0.5, 2)
		var screen_point := view_camera.unproject_position(bottom)
		motion.button_mask = 0; motion.position = view.get_parent().get_global_transform() * screen_point; motion.global_position = motion.position
		window.push_input(motion, true)
		press.position = motion.position; press.global_position = motion.position; window.push_input(press, true)
		release.position = motion.position; release.global_position = motion.position; window.push_input(release, true)
		await frames(tree)
		check(tool.picked.get("kind") == mode and not tool.dragging, "real native viewport click selects a visible %s" % mode)
		if tool.picked.get("kind") != mode: print("NATIVE COMPONENT DEBUG mode=", mode, " world=", bottom, " screen=", screen_point, " direct=", tool.pick_element(view_camera, screen_point), " picked=", tool.picked, " camera=", view_camera.global_position)
		if OS.get_cmdline_user_args().has("--capture-face-gizmo"):
			await frames(tree, 10); RenderingServer.force_draw()
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://docs/level_editor/selection_tools_2026-11-16/selected_%s.png" % mode)
	tool.set_mode("face")
	tool.set_enabled(false); camera.free()
	editor._set_edit_step(original_step)
	EditorInterface.close_scene()
	await frames(tree)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("FACE GIZMO: ", checks, " checks, ", failures, " failures")
	tree.quit(0 if failures == 0 else 1)

func component_checks(editor: EditorPlugin, block: Node3D, camera: Camera3D, history: UndoRedo, original: Dictionary) -> void:
	var tool: RefCounted = editor.push_pull
	var tree := editor.get_tree()
	for mode in ["edge", "point"]:
		block.apply_face_state(original)
		editor.selection_buttons[mode][0].button_pressed = true
		check(tool.enabled and tool.mode == mode and not editor.selection_buttons.face[0].button_pressed, "%s mode is active exclusively through its toolbar button" % mode)
		var point := Vector3(2 if mode == "point" else 0, 2, 2)
		var selected: bool = tool.select_face(camera, camera.unproject_position(point))
		check(selected and tool.picked.get("block") == block and tool.face.points.size() == (2 if mode == "edge" else 1), "screen picking resolves the requested %s on the visible whitebox surface" % mode)
		if not selected: continue
		await frames(tree)
		var gizmo: EditorNode3DGizmo = tool.gizmo_for(block)
		var id: int = tool.selection_id()
		var frame: Transform3D = editor.gizmos._get_subgizmo_transform(gizmo, id)
		var centered := block.to_global(frame.origin).distance_to(point) < 0.0001 and gizmo.is_subgizmo_selected(id)
		if not centered: print("COMPONENT PIVOT ", mode, " id=", id, " expected=", point, " actual=", block.to_global(frame.origin), " vertices=", tool.face.get("vertices"), " selection=", gizmo.get_subgizmo_selection())
		check(centered, "%s manipulator uses the element center instead of the object center" % mode)
		var faces: PackedVector3Array = block.geometry().get_faces()
		var element: Dictionary = tool.face.duplicate(true)
		var old_global := block.global_transform
		var target := frame; target.origin += Vector3(0, 0.3, 0)
		editor.gizmos._set_subgizmo_transform(gizmo, id, target)
		var live: PackedVector3Array = block.geometry().get_faces()
		var matches := true
		for i in faces.size():
			var expected: Vector3 = old_global * faces[i] + (Vector3(0, 0.3, 0) if element.points.has(EDIT.point_key(faces[i])) else Vector3.ZERO)
			matches = matches and block.to_global(live[i]).distance_to(expected) < 0.0001
		check(matches and tool.dragging, "native %s translation moves only its welded vertices" % mode)
		var restores: Array[Transform3D] = [frame]
		editor.gizmos._commit_subgizmos(gizmo, PackedInt32Array([id]), restores, false)
		var moved := EDIT.capture(block)
		history.undo(); await frames(tree)
		check(EDIT.capture(block) == original, "%s undo restores all geometry and the anchored transform" % mode)
		history.redo(); await frames(tree)
		check(EDIT.capture(block) == moved, "%s redo restores the exact edited vertices" % mode)
		frame = editor.gizmos._get_subgizmo_transform(gizmo, id)
		target = Transform3D(Basis(Vector3.UP, deg_to_rad(15)) * frame.basis, frame.origin)
		var version := history.get_version()
		editor.gizmos._set_subgizmo_transform(gizmo, id, target)
		editor.gizmos._commit_subgizmos(gizmo, PackedInt32Array([id]), restores, false)
		if mode == "edge":
			check(EDIT.capture(block) != moved and history.get_version() != version, "edge rotation changes both endpoints around the midpoint and is undoable")
		else:
			check(EDIT.capture(block) == moved and history.get_version() == version, "rotating a single point around itself changes neither geometry nor history")
		tool.clear(); await frames(tree)
		check(not gizmo.is_subgizmo_selected(id) and EditorInterface.get_selection().get_selected_nodes().has(block), "clearing %s selection restores the original object axes" % mode)
	tool.set_mode("face")

func frame_selection(view: SubViewport, window: Window, tree: SceneTree) -> void:
	EditorInterface.set_main_screen_editor("3D")
	await frames(tree)
	var surface: Control = view.get_parent()
	while surface.get_parent() is Control and surface.get_class() != "Node3DEditorViewport": surface = surface.get_parent()
	var transform_key := InputEventKey.new(); transform_key.keycode = KEY_Q
	var editor_3d: Node = surface.get_parent()
	while editor_3d != null and editor_3d.get_class() != "Node3DEditor": editor_3d = editor_3d.get_parent()
	if editor_3d != null:
		for button in editor_3d.find_children("*", "Button", true, false):
			if button.shortcut != null and button.shortcut.matches_event(transform_key):
				button.button_pressed = true; button.pressed.emit(); break
	for candidate in surface.find_children("*", "Control", true, false):
		if candidate.is_visible_in_tree() and candidate.focus_mode == Control.FOCUS_ALL and candidate.size.x > surface.size.x * 0.9 and candidate.size.y > surface.size.y * 0.9:
			candidate.grab_focus(); break
	for modified in [false, true]:
		var key := InputEventKey.new(); key.keycode = KEY_F; key.pressed = true; key.meta_pressed = modified
		window.push_input(key, true); key.pressed = false; window.push_input(key, true)
	await tree.create_timer(0.3, true).timeout
	await frames(tree, 10)
