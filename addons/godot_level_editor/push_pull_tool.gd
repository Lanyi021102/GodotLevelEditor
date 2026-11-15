@tool
extends RefCounted
const EDIT := preload("res://addons/godot_level_editor/face_edit.gd")
const BLOCK := preload("res://addons/godot_level_editor/runtime/whitebox_block.gd")
const ELEMENTS := preload("res://addons/godot_level_editor/mesh_elements.gd")
const MODE_LABELS := {"face": "面", "edge": "线", "point": "点"}
var plugin: EditorPlugin
var enabled := false
var selection_pending := false
var mode := "face"
var hovered: Dictionary = {}
var topology_cache := {}
var selecting := false
var picked: Dictionary = {}
var face: Dictionary = {}
var before: Dictionary = {}
var before_frame := Transform3D.IDENTITY
var source_faces := PackedVector3Array()
var dragging := false
var amount := 0.0
var world_normal := Vector3.ZERO
var world_faces := PackedVector3Array()
var camera: Camera3D
var overlay_viewport: Viewport

func set_enabled(value: bool) -> void:
	if dragging: finish(true)
	clear()
	enabled = value
	selection_pending = value
	plugin._sync_selection_buttons()
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		for node in [root] + root.find_children("*", "Node3D", true, false):
			if node.get_script() == BLOCK: node.update_gizmos()
	plugin.message.text = "选中%s：点击元素，再拖中心操作轴；Esc / 点击空白恢复物体轴。" % MODE_LABELS[mode] if value else "选择面、线或点进行编辑；右侧可填写编辑步长。"
	plugin.update_overlays()

func set_mode(value: String) -> void:
	if not MODE_LABELS.has(value): return
	if enabled and mode == value: return
	if dragging: finish(true)
	clear()
	mode = value
	set_enabled(true)

func clear() -> void:
	selection_pending = false
	var block: Node3D = picked.get("block")
	picked = {}
	face = {}
	hovered = {}
	topology_cache.clear()
	world_faces.clear()
	if is_instance_valid(block):
		block.clear_subgizmo_selection()
		block.update_gizmos()
	plugin.update_overlays()

func editable_blocks() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var root := EditorInterface.get_edited_scene_root()
	if root == null: return result
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		for child in node.get_children():
			if not child.get_meta("godot_level_editor_generated", false): queue.append(child)
		if node.get_script() != BLOCK: continue
		if node != root and node.owner != root and not root.is_editable_instance(node.owner): continue
		if node.is_visible_in_tree() and node.visual_scene == null: result.append(node)
	return result

func topology(block: Node3D) -> Dictionary:
	var mesh: Mesh = block.geometry()
	var id := block.get_instance_id()
	if not topology_cache.has(id) or topology_cache[id].mesh != mesh:
		topology_cache[id] = {"mesh": mesh, "data": ELEMENTS.build(mesh.get_faces())}
	return topology_cache[id].data

func selection_id() -> int:
	return int(picked.get("element", picked.get("triangle", -1)))

func selected_geometry(block: Node3D, id: int) -> Dictionary:
	return ELEMENTS.selection(block.geometry().get_faces(), mode, id, topology(block) if mode == "edge" else {})

func element_frame(block: Node3D, id: int) -> Transform3D:
	return ELEMENTS.frame(selected_geometry(block, id))

func pick_element(view_camera: Camera3D, screen: Vector2) -> Dictionary:
	if mode == "face": return pick(view_camera.project_ray_origin(screen), view_camera.project_ray_normal(screen))
	var tolerance := (10.0 if mode == "point" else 8.0) * EditorInterface.get_editor_scale()
	var candidates: Array[Dictionary] = []
	for block in editable_blocks():
		var data := topology(block)
		for item in data.vertices if mode == "point" else data.edges:
			var a: Vector3 = item.point if mode == "point" else item.a
			var b: Vector3 = a if mode == "point" else item.b
			var wa := block.to_global(a); var wb := block.to_global(b)
			if view_camera.is_position_behind(wa) or view_camera.is_position_behind(wb): continue
			var sa := view_camera.unproject_position(wa); var sb := view_camera.unproject_position(wb)
			var near: Vector2 = sa if mode == "point" else Geometry2D.get_closest_point_to_segment(screen, sa, sb)
			var pixels := screen.distance_to(near)
			if pixels > tolerance: continue
			var fraction := 0.0 if sa.is_equal_approx(sb) else clampf((near - sa).dot(sb - sa) / sa.distance_squared_to(sb), 0, 1)
			var point := a.lerp(b, fraction)
			if not ELEMENTS.front_facing(item.normals, block, view_camera, point): continue
			var world := block.to_global(point)
			var ray_screen := view_camera.unproject_position(world)
			var origin := view_camera.project_ray_origin(ray_screen)
			var distance := origin.distance_to(world)
			var surface := pick(origin, view_camera.project_ray_normal(ray_screen))
			if not surface.is_empty() and surface.distance < distance - 0.001: continue
			candidates.append({"block": block, "triangle": int(item.id) / 3, "element": item.id, "kind": mode, "hit": point, "pixels": pixels, "distance": distance})
	if candidates.is_empty(): return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		var bucket_a := roundi(float(a.pixels) * 2); var bucket_b := roundi(float(b.pixels) * 2)
		return a.distance < b.distance if bucket_a == bucket_b else bucket_a < bucket_b)
	return candidates[0]

func pick(origin: Vector3, direction: Vector3) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null: return {}
	var queue: Array[Node] = [root]
	var result := {}
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		for child in node.get_children():
			if not child.get_meta("godot_level_editor_generated", false): queue.append(child)
		if node.get_script() != BLOCK: continue
		if node != root and node.owner != root and not root.is_editable_instance(node.owner): continue
		var hit := EDIT.ray_pick(node, origin, direction)
		if not hit.is_empty() and (result.is_empty() or hit.distance < result.distance): result = hit
	return result

func gizmo_for(block: Node3D) -> EditorNode3DGizmo:
	for gizmo in block.get_gizmos():
		if gizmo is EditorNode3DGizmo and gizmo.get_plugin() == plugin.gizmos: return gizmo
	return null

func uses_native_gizmo() -> bool:
	if not enabled: return false
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	return nodes.size() == 1 and nodes[0].get_script() == BLOCK and gizmo_for(nodes[0]) != null

func select_face(view_camera: Camera3D, screen: Vector2) -> bool:
	var hit := pick_element(view_camera, screen)
	if hit.is_empty(): clear(); return false
	_select_hit(hit, view_camera)
	return true

func _select_hit(hit: Dictionary, view_camera: Camera3D) -> void:
	if not enabled or not is_instance_valid(hit.get("block")): return
	clear()
	camera = view_camera
	overlay_viewport = camera.get_viewport()
	picked = hit
	var block: Node3D = picked.block
	selecting = true
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(block)
	selecting = false
	refresh()
	plugin.message.text = "已选%s：拖箭头移动（步长 %s），Esc / 点击空白恢复物体轴。%s" % [MODE_LABELS[mode], String.num(plugin.edit_step, 3), "单点绕自身旋转不改变形状。" if mode == "point" else "拖圆环旋转。"]

## Runs after native axis hit-testing, so face selection never steals an axis drag.
func intersect_face(gizmo: EditorNode3DGizmo, view_camera: Camera3D, screen: Vector2) -> int:
	if not enabled: return -1
	var hit := pick_element(view_camera, screen)
	if hit.is_empty(): clear.call_deferred(); return -1
	if hit.block != gizmo.get_node_3d():
		_select_hit.call_deferred(hit, view_camera)
		return -1
	camera = view_camera
	overlay_viewport = camera.get_viewport()
	picked = hit
	# Keep this a single-face tool even when native Shift selection is held.
	# Node3D applies the selection after native gizmo traversal has completed.
	refresh()
	return selection_id()

func refresh(update_selection := true) -> void:
	if picked.is_empty() or not is_instance_valid(picked.get("block")): return
	var block: Node3D = picked.block
	face = selected_geometry(block, selection_id())
	world_faces.clear()
	for point in face.get("faces", []): world_faces.append(block.to_global(point))
	if not face.is_empty(): world_normal = (block.global_basis.inverse().transposed() * face.normal).normalized()
	if update_selection and not dragging and EditorInterface.get_selection().get_selected_nodes().has(block):
		var gizmo := gizmo_for(block)
		if gizmo != null: block.set_subgizmo_selection(gizmo, selection_id(), ELEMENTS.frame(face))
	plugin.update_overlays()

func _start_drag() -> void:
	var block: Node3D = picked.block
	source_faces = block.geometry().get_faces()
	face = selected_geometry(block, selection_id())
	before = EDIT.capture(block)
	before_frame = ELEMENTS.frame(face)
	amount = 0.0
	dragging = true

func preview_transform(target: Transform3D) -> bool:
	if picked.is_empty() or not is_instance_valid(picked.get("block")): return false
	if not dragging: _start_drag()
	var block: Node3D = picked.block
	var source_face := ELEMENTS.selection(source_faces, mode, selection_id())
	var state := EDIT.transformed_state(block, source_faces, source_face, before, target * before_frame.affine_inverse())
	if state.is_empty():
		plugin.message.text = "已到最小厚度或相邻面将翻转；请减小移动或旋转幅度。"
		return false
	block.apply_face_state(state)
	refresh()
	return true

## Direct normal push retained for editor probes and scripted geometry tools.
func begin(view_camera: Camera3D, screen: Vector2) -> bool:
	if not select_face(view_camera, screen): return false
	_start_drag()
	return true

func preview_distance(distance: float) -> bool:
	if not dragging: return false
	var block: Node3D = picked.block
	var source_face := ELEMENTS.selection(source_faces, mode, selection_id())
	var normal: Vector3 = (block.global_basis.inverse().transposed() * source_face.normal).normalized()
	amount = snappedf(distance, plugin.edit_step)
	var delta: Vector3 = block.global_basis.inverse() * normal * amount
	var target := before_frame
	target.origin += delta
	return preview_transform(target)

func finish(cancel: bool) -> void:
	if not dragging: return
	dragging = false
	if not is_instance_valid(picked.get("block")): clear(); return
	var block: Node3D = picked.block
	var after := EDIT.capture(block)
	if cancel:
		block.apply_face_state(before)
	elif after != before:
		var history := plugin.get_undo_redo()
		history.create_action("编辑白盒" + MODE_LABELS[mode], UndoRedo.MERGE_DISABLE, block)
		history.add_do_method(block, "apply_face_state", after)
		history.add_undo_method(block, "apply_face_state", before)
		history.add_do_method(self, "refresh")
		history.add_undo_method(self, "refresh")
		history.commit_action()
	amount = 0.0
	refresh()
	plugin._selection_changed()

func input(view_camera: Camera3D, event: InputEvent) -> bool:
	if not enabled: return false
	if event is InputEventMouseMotion and not dragging:
		camera = view_camera; overlay_viewport = camera.get_viewport()
		if mode != "face": hovered = pick_element(view_camera, event.position)
		plugin.update_overlays()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not dragging and not picked.is_empty():
		clear()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not event.alt_pressed and picked.is_empty():
		# Restored object axes remain usable. Native hit-testing checks them first,
		# then calls intersect_face() if the click lands on a surface instead.
		if uses_native_gizmo() and not selection_pending: return false
		select_face(view_camera, event.position)
		return true
	# Selected faces use native subgizmo axes, snapping, mouse capture and cancel.
	return false

func _draw_element(control: Control, block: Node3D, element: Dictionary, color: Color, selected: bool) -> void:
	var points := PackedVector2Array()
	for point in element.get("vertices", []):
		var world := block.to_global(point)
		if camera.is_position_behind(world): return
		points.append(camera.unproject_position(world))
	var ui_scale := EditorInterface.get_editor_scale()
	if points.size() == 2:
		control.draw_line(points[0], points[1], color, (3.0 if selected else 1.0) * ui_scale, true)
	elif points.size() == 1:
		if selected: control.draw_circle(points[0], 6 * ui_scale, Color(0.12, 0.15, 0.2, 0.9))
		control.draw_circle(points[0], (4.5 if selected else 2.5) * ui_scale, color)

func _draw_components(control: Control) -> void:
	var blocks: Array[Node3D] = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node.get_script() == BLOCK: blocks.append(node)
	if not hovered.is_empty() and is_instance_valid(hovered.get("block")) and not blocks.has(hovered.block): blocks.append(hovered.block)
	for block in blocks:
		var data := topology(block)
		for item in data.vertices if mode == "point" else data.edges:
			var point: Vector3 = item.point if mode == "point" else (item.a + item.b) * 0.5
			if not ELEMENTS.front_facing(item.normals, block, camera, point): continue
			var points := PackedVector3Array([item.point]) if mode == "point" else PackedVector3Array([item.a, item.b])
			_draw_element(control, block, {"vertices": points}, Color(0.35, 0.75, 1.0, 0.75), false)
	if not hovered.is_empty() and is_instance_valid(hovered.get("block")):
		_draw_element(control, hovered.block, selected_geometry(hovered.block, int(hovered.element)), Color(0.4, 0.9, 1), true)
	if not picked.is_empty() and is_instance_valid(picked.get("block")):
		_draw_element(control, picked.block, selected_geometry(picked.block, selection_id()), Color(1, 0.7, 0.12), true)

func draw(control: Control) -> void:
	if not enabled or not is_instance_valid(camera): return
	if camera.get_viewport() != overlay_viewport: return
	var view_owner: Node = overlay_viewport.get_parent()
	while view_owner != null and view_owner.get_class() != "Node3DEditorViewport": view_owner = view_owner.get_parent()
	if view_owner == null or not view_owner.is_ancestor_of(control): return
	if mode != "face": _draw_components(control); return
	if picked.is_empty() or not is_instance_valid(picked.get("block")): return
	# Use live triangles so the highlight follows translation and rotation exactly.
	var live_face := EDIT.planar_face(picked.block.geometry().get_faces(), picked.triangle)
	world_faces.clear()
	for point in live_face.get("faces", []): world_faces.append(picked.block.to_global(point))
	var vertices := PackedVector2Array()
	for point in world_faces:
		if camera.is_position_behind(point): return
		vertices.append(camera.unproject_position(point))
	for i in range(0, vertices.size(), 3):
		control.draw_colored_polygon(PackedVector2Array([vertices[i], vertices[i + 1], vertices[i + 2]]), Color(1.0, 0.65, 0.12, 0.24))
	var boundary := {}
	for i in range(0, world_faces.size(), 3):
		for k in 3:
			var key := EDIT.edge_key(world_faces[i + k], world_faces[i + (k + 1) % 3])
			if boundary.has(key): boundary.erase(key)
			else: boundary[key] = [vertices[i + k], vertices[i + (k + 1) % 3]]
	for line in boundary.values(): control.draw_line(line[0], line[1], Color(1, 0.7, 0.12), 2, true)
