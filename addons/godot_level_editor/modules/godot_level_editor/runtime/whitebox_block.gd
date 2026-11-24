@tool
extends Node3D
const SHAPES := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_shapes.gd")
const FACE_EDIT := preload("res://addons/godot_level_editor/modules/godot_level_editor/face_edit.gd")
const METRIC_GRID := preload("res://addons/godot_level_editor/scripts/tools/metric_grid.gd")
@export_storage var mesh_edit: Dictionary = {}:
	set(value): mesh_edit = value; _changed()
@export var object_id := ""
@export_enum("box", "ramp", "stairs", "stairs_manual", "cylinder", "cone", "sphere", "hemisphere", "skewbox", "corner_curved", "stairs_curved", "doorway", "window", "railing", "tube", "corner_ramp") var shape_kind := "box":
	set(value): shape_kind = value; _changed()
@export var visual_scene: PackedScene:
	set(value): visual_scene = value; _changed()
@export var size := Vector3.ONE:
	set(value):
		size = value.snapped(Vector3.ONE * 0.1).clamp(Vector3.ONE * 0.1, Vector3.ONE * 1000)
		_changed()
@export_range(1, 64, 1) var steps := 6:
	set(value): steps = clampi(value, 1, 64); _changed()
@export_range(0.1, 10, 0.1) var step_height := 0.2:
	set(value): step_height = maxf(0.1, snappedf(value, 0.1)); _changed()
@export_range(0.05, 0.45, 0.05) var thickness := 0.2:
	set(value): thickness = clampf(value, 0.05, 0.45); _changed()
@export_range(15, 360, 5) var curve_angle := 90.0:
	set(value): curve_angle = clampf(value, 15, 360); _changed()
@export_range(-0.5, 0.5, 0.05) var skew := 0.25:
	set(value): skew = value; _changed()
@export var tint := Color("aaaaaa"):
	set(value): tint = value; _changed()
@export var solid := true:
	set(value): solid = value; _changed()
var _queued := false
var _snapping_scale := false
var _mesh_cache: ArrayMesh
var _terrain_cover := {}

func _enter_tree() -> void:
	set_notify_local_transform(true)
	if object_id.is_empty(): object_id = "block_" + Crypto.new().generate_random_bytes(10).hex_encode()
func _ready() -> void: _rebuild()

func set_terrain_coverage(source: int, covered: bool) -> void:
	if covered:
		_terrain_cover[source] = true
	else:
		_terrain_cover.erase(source)
	if is_inside_tree() and not _queued:
		_queued = true
		_rebuild.call_deferred()
		if Engine.is_editor_hint(): update_gizmos()

func is_covered_by_terrain() -> bool:
	return not _terrain_cover.is_empty()
func _changed() -> void:
	_mesh_cache = null
	if is_inside_tree() and not _queued:
		_queued = true
		_rebuild.call_deferred()
	if Engine.is_editor_hint() and is_inside_tree(): update_gizmos()
func geometry() -> ArrayMesh:
	if _mesh_cache != null: return _mesh_cache
	if has_mesh_edit():
		var vertices: PackedVector3Array = mesh_edit.vertices.duplicate()
		for i in vertices.size(): vertices[i] *= size
		_mesh_cache = FACE_EDIT.mesh_from_faces(vertices)
		return _mesh_cache
	var count := maxi(1, ceili(size.y / step_height)) if shape_kind == "stairs_manual" else steps
	_mesh_cache = SHAPES.mesh_for(shape_kind, size, count, thickness, curve_angle, skew)
	return _mesh_cache

func geometry_signature() -> Array:
	return [shape_kind, steps, step_height, thickness, curve_angle, skew]
func has_mesh_edit() -> bool:
	return mesh_edit.get("signature", []) == geometry_signature() and mesh_edit.get("vertices") is PackedVector3Array and mesh_edit.vertices.size() >= 12 and mesh_edit.vertices.size() % 3 == 0
func apply_face_state(state: Dictionary) -> void:
	size = state.size
	mesh_edit = state.mesh_edit.duplicate(true)
	transform = state.transform
	_changed()
func _rebuild() -> void:
	_queued = false
	if not is_inside_tree(): return
	for child in get_children():
		if child.get_meta("godot_level_editor_generated", false): child.free()
	if is_covered_by_terrain(): return
	var shape_mesh := geometry()
	if visual_scene != null:
		var visual := visual_scene.instantiate()
		visual.set_meta("godot_level_editor_generated", true)
		add_child(visual)
	else:
		var mesh := MeshInstance3D.new()
		mesh.set_meta("godot_level_editor_generated", true)
		mesh.mesh = shape_mesh
		var grid := METRIC_GRID.material(tint)
		grid.set_shader_parameter("triplanar_projection", shape_kind in ["cylinder", "cone", "sphere", "hemisphere", "corner_curved", "stairs_curved", "tube", "corner_ramp"])
		mesh.material_override = grid
		add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.set_meta("godot_level_editor_generated", true)
		var cs := CollisionShape3D.new()
		if shape_kind == "box" and not has_mesh_edit():
			var shape := BoxShape3D.new()
			shape.size = size
			cs.shape = shape
		else: cs.shape = shape_mesh.create_trimesh_shape()
		body.add_child(cs)
		add_child(body)

func _notification(what: int) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED or not Engine.is_editor_hint() or _snapping_scale: return
	var snapped_scale := scale.snapped(Vector3.ONE * 0.1).clamp(Vector3.ONE * 0.1, Vector3.ONE * 1000)
	if not scale.is_equal_approx(snapped_scale):
		_snapping_scale = true
		scale = snapped_scale
		_snapping_scale = false

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not mesh_edit.is_empty():
		if mesh_edit.get("version", 1) != 1: errors.append(object_id + "：不支持的推拉网格版本")
		if not mesh_edit.get("vertices") is PackedVector3Array or mesh_edit.get("vertices", []).size() % 3 != 0: errors.append(object_id + "：推拉网格三角形数据无效")
		elif mesh_edit.vertices.size() < 12: errors.append(object_id + "：推拉网格没有有效表面")
		else:
			for vertex in mesh_edit.vertices:
				if not vertex.is_finite(): errors.append(object_id + "：推拉网格含无效顶点"); break
	if not SHAPES.LABELS.has(shape_kind): errors.append(object_id + "：未知白盒形状")
	if not size.is_finite() or size.x < 0.1 or size.y < 0.1 or size.z < 0.1: errors.append(object_id + "：尺寸不得小于 0.1")
	if not scale.is_finite() or scale.x <= 0 or scale.y <= 0 or scale.z <= 0: errors.append(object_id + "：缩放必须为有限正数")
	if shape_kind == "stairs_manual" and ceili(size.y / step_height) > 64: errors.append(object_id + "：定高楼梯最多 64 级，请增大级高或降低总高度")
	return errors
