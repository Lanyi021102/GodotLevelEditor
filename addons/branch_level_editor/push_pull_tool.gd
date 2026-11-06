@tool
extends RefCounted
const EDIT := preload("res://addons/branch_level_editor/face_edit.gd")
const BLOCK := preload("res://addons/branch_level_editor/runtime/whitebox_block.gd")
var plugin: EditorPlugin
var enabled := false
var picked: Dictionary = {}
var face: Dictionary = {}
var before: Dictionary = {}
var source_faces := PackedVector3Array()
var dragging := false
var amount := 0.0
var start_screen := Vector2.ZERO
var screen_axis := Vector2.ZERO
var world_normal := Vector3.ZERO
var world_faces := PackedVector3Array()
var camera: Camera3D
var overlay_viewport: Viewport

func set_enabled(value: bool) -> void:
	if dragging: finish(true)
	enabled = value
	clear()
	plugin.message.text = "推拉模式：左键选面并拖动，松开确认；Esc / 拖动时右键取消。步长 0.1。" if value else "移动吸附 0.1；点击“推拉面”可选中表面推拉。"
	plugin.update_overlays()

func clear() -> void:
	picked = {}
	face = {}
	world_faces.clear()
	plugin.update_overlays()

func pick(origin: Vector3, direction: Vector3) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null: return {}
	var queue: Array[Node] = [root]
	var result := {}
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		for child in node.get_children():
			if not child.get_meta("branch_generated", false): queue.append(child)
		if node.get_script() != BLOCK: continue
		if node != root and node.owner != root and not root.is_editable_instance(node.owner): continue
		var hit := EDIT.ray_pick(node, origin, direction)
		if not hit.is_empty() and (result.is_empty() or hit.distance < result.distance): result = hit
	return result

func begin(view_camera: Camera3D, screen: Vector2) -> bool:
	camera = view_camera
	overlay_viewport = camera.get_viewport()
	picked = pick(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if picked.is_empty(): clear(); return false
	var block: Node3D = picked.block
	source_faces = block.geometry().get_faces()
	face = EDIT.planar_face(source_faces, picked.triangle)
	before = EDIT.capture(block)
	world_normal = (block.global_basis.inverse().transposed() * face.normal).normalized()
	world_faces.clear()
	for point in face.faces: world_faces.append(block.to_global(point))
	var point := block.to_global(picked.hit)
	start_screen = screen
	screen_axis = camera.unproject_position(point + world_normal) - camera.unproject_position(point)
	# A face viewed head-on has no projected normal; use vertical dragging at
	# the same world/pixel scale, rather than making that face impossible to edit.
	if screen_axis.length() < 12:
		var world_height := camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 2.0 * camera.global_position.distance_to(point) * tan(deg_to_rad(camera.fov) * 0.5)
		screen_axis = Vector2(0, -camera.get_viewport().get_visible_rect().size.y / maxf(world_height, 0.01))
	amount = 0.0
	dragging = true
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(block)
	plugin.update_overlays()
	return true

func drag_to(screen: Vector2) -> void:
	if not dragging or not is_instance_valid(picked.get("block")): return
	var distance := (screen - start_screen).dot(screen_axis) / maxf(screen_axis.length_squared(), 0.01)
	preview_distance(distance)

func preview_distance(distance: float) -> bool:
	var block: Node3D = picked.block
	var state := EDIT.pushed_state(block, source_faces, face, before, distance)
	if state.is_empty():
		plugin.message.text = "已到最小厚度或相邻面将翻转；请向外拖动。"
		return false
	block.apply_face_state(state)
	amount = snappedf(distance, EDIT.STEP)
	plugin.message.text = "推拉 %+.1f · 步长 0.1 · 松开确认，Esc 取消" % amount
	plugin.update_overlays()
	return true

func finish(cancel: bool) -> void:
	if not dragging: return
	dragging = false
	if not is_instance_valid(picked.get("block")): clear(); return
	var block: Node3D = picked.block
	if cancel or is_zero_approx(amount):
		block.apply_face_state(before)
	else:
		var after := EDIT.capture(block)
		var history := plugin.get_undo_redo()
		history.create_action("推拉白盒表面（0.1）", UndoRedo.MERGE_DISABLE, block)
		history.add_do_method(block, "apply_face_state", after)
		history.add_undo_method(block, "apply_face_state", before)
		history.commit_action()
	# Rebuild highlight from the live geometry, including after recentering.
	source_faces = block.geometry().get_faces()
	face = EDIT.planar_face(source_faces, picked.triangle)
	world_faces.clear()
	for point in face.get("faces", []): world_faces.append(block.to_global(point))
	amount = 0.0
	plugin._selection_changed()
	plugin.update_overlays()

func input(view_camera: Camera3D, event: InputEvent) -> bool:
	if not enabled: return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if dragging: finish(true)
		else: clear()
		return true
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and dragging:
			finish(true)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed:
			if event.pressed: return begin(view_camera, event.position)
			if dragging: finish(false); return true
	if event is InputEventMouseMotion and dragging:
		drag_to(event.position)
		return true
	return false

func draw(control: Control) -> void:
	if not enabled or picked.is_empty() or not is_instance_valid(camera) or not is_instance_valid(picked.get("block")): return
	if camera.get_viewport() != overlay_viewport: return
	var view_owner: Node = overlay_viewport.get_parent()
	while view_owner != null and view_owner.get_class() != "Node3DEditorViewport": view_owner = view_owner.get_parent()
	if view_owner == null or not view_owner.is_ancestor_of(control): return
	if not dragging:
		var live_face := EDIT.planar_face(picked.block.geometry().get_faces(), picked.triangle)
		world_faces.clear()
		for point in live_face.get("faces", []): world_faces.append(picked.block.to_global(point))
	var offset := world_normal * amount if dragging else Vector3.ZERO
	var vertices := PackedVector2Array()
	for point in world_faces:
		if camera.is_position_behind(point + offset): return
		vertices.append(camera.unproject_position(point + offset))
	for i in range(0, vertices.size(), 3):
		control.draw_colored_polygon(PackedVector2Array([vertices[i], vertices[i + 1], vertices[i + 2]]), Color(1.0, 0.65, 0.12, 0.34))
	var boundary := {}
	for i in range(0, world_faces.size(), 3):
		for k in 3:
			var key := EDIT.edge_key(world_faces[i + k], world_faces[i + (k + 1) % 3])
			if boundary.has(key): boundary.erase(key)
			else: boundary[key] = [vertices[i + k], vertices[i + (k + 1) % 3]]
	for line in boundary.values(): control.draw_line(line[0], line[1], Color(1, 0.7, 0.12), 2, true)
	if not vertices.is_empty():
		control.draw_string(ThemeDB.fallback_font, vertices[0] + Vector2(8, -10), "推拉 %+.1f  |  0.1" % amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.85, 0.3))
