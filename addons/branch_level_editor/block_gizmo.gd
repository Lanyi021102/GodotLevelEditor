@tool
extends EditorNode3DGizmoPlugin
const BLOCK := preload("res://addons/branch_level_editor/runtime/whitebox_block.gd")
const ROOM := preload("res://addons/branch_level_editor/runtime/room.gd")
func _init() -> void:
	create_material("outline", Color(0.3, 0.85, 0.95, 0.8))
	create_handle_material("stretch")
func _get_gizmo_name() -> String: return "白盒拉伸与房间范围"
func _has_gizmo(node: Node3D) -> bool: return node.get_script() == BLOCK or node.get_script() == ROOM
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	var room: bool = node.get_script() == ROOM
	var dimensions: Vector3 = node.bounds_size if room else node.size
	var center := Vector3(0, dimensions.y * 0.5, 0) if room else Vector3.ZERO
	var box := AABB(center - dimensions * 0.5, dimensions)
	var lines := PackedVector3Array()
	for i in 8:
		for axis in 3:
			var other := i ^ (1 << axis)
			if i < other:
				lines.append(box.get_endpoint(i))
				lines.append(box.get_endpoint(other))
	gizmo.add_lines(lines, get_material("outline", gizmo))
	gizmo.add_collision_segments(lines)
	if not room:
		gizmo.add_collision_triangles(node.geometry().generate_triangle_mesh())
		var handles := PackedVector3Array([Vector3(dimensions.x * 0.5, 0, 0), Vector3(0, dimensions.y * 0.5, 0), Vector3(0, 0, dimensions.z * 0.5), dimensions * 0.5])
		gizmo.add_handles(handles, get_material("stretch", gizmo), PackedInt32Array([0, 1, 2, 3]))
func _get_handle_name(_gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	return ["宽度 · 0.1", "高度 · 0.1", "深度 · 0.1", "整体缩放 · 0.1"][id]
func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant: return gizmo.get_node_3d().size
func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	var axis: Vector3 = node.size.normalized() if id == 3 else Vector3.ZERO
	if id < 3: axis[id] = 1
	var origin: Vector3 = node.global_position
	var world_axis: Vector3 = (node.global_basis * axis).normalized()
	var start := camera.project_ray_origin(screen_pos)
	var end := start + camera.project_ray_normal(screen_pos) * 10000
	var points := Geometry3D.get_closest_points_between_segments(origin - world_axis * 5000, origin + world_axis * 5000, start, end)
	var local: Vector3 = node.to_local(points[0])
	var dimensions: Vector3 = node.size
	if id < 3: dimensions[id] = maxf(0.1, local[id] * 2)
	else:
		var length_value := maxf(0.1, local.dot(axis) * 2)
		dimensions *= length_value / maxf(dimensions.length(), 0.1)
	node.size = dimensions
	node.update_gizmos()
func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	if cancel: node.size = restore; return
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("拉伸白盒（0.1）", UndoRedo.MERGE_DISABLE, node)
	undo.add_do_property(node, "size", node.size)
	undo.add_undo_property(node, "size", restore)
	undo.commit_action()
