@tool
extends EditorNode3DGizmoPlugin
const BLOCK := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd")
const ROOM := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/room.gd")
const EDIT := preload("res://addons/godot_level_editor/modules/godot_level_editor/face_edit.gd")
var face_tool: RefCounted
func _init() -> void:
	create_material("outline", Color(0.3, 0.85, 0.95, 0.8))
func _get_gizmo_name() -> String: return "白盒拉伸与房间范围"
func _has_gizmo(node: Node3D) -> bool: return node.get_script() == BLOCK or node.get_script() == ROOM
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	var room: bool = node.get_script() == ROOM
	if not room and face_tool != null and face_tool.enabled:
		gizmo.add_collision_triangles(node.geometry().generate_triangle_mesh())
		return
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

func _subgizmos_intersect_ray(gizmo: EditorNode3DGizmo, camera: Camera3D, screen_pos: Vector2) -> int:
	if face_tool == null or gizmo.get_node_3d().get_script() != BLOCK: return -1
	return face_tool.intersect_face(gizmo, camera, screen_pos)

func _get_subgizmo_transform(gizmo: EditorNode3DGizmo, id: int) -> Transform3D:
	if face_tool != null: return face_tool.element_frame(gizmo.get_node_3d(), id)
	return Transform3D.IDENTITY

func _set_subgizmo_transform(gizmo: EditorNode3DGizmo, id: int, target: Transform3D) -> void:
	if face_tool != null and face_tool.enabled and face_tool.picked.get("block") == gizmo.get_node_3d() and face_tool.selection_id() == id:
		face_tool.preview_transform(target)

func _commit_subgizmos(_gizmo: EditorNode3DGizmo, _ids: PackedInt32Array, _restores: Array[Transform3D], cancel: bool) -> void:
	if face_tool != null: face_tool.finish(cancel)
