@tool
extends Node3D

const LAYOUT := preload("layout.gd")
const SURFACE := preload("surface.gd")
const METRIC_GRID := preload("res://addons/godot_level_editor/scripts/tools/metric_grid.gd")
const BLOCK := preload("../runtime/whitebox_block.gd")

@export_storage var layout: Dictionary = LAYOUT.empty()

var surface: RefCounted
var preview_only := false
var _mesh: MeshInstance3D
var _collision: CollisionShape3D
var _covered_floor: Node3D
var _committed_mesh: ArrayMesh
var _committed_surface: RefCounted

func _enter_tree() -> void:
	if not preview_only:
		_cover_default_floor.call_deferred()

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.set_meta("godot_level_editor_terrain_mesh", true)
	var grid := METRIC_GRID.material(Color("c5c9d0"))
	grid.set_shader_parameter("triplanar_projection", true)
	_mesh.material_override = grid
	add_child(_mesh)
	if not preview_only:
		var body := StaticBody3D.new()
		_collision = CollisionShape3D.new()
		body.add_child(_collision)
		add_child(body)
		set_meta("_edit_group_", true)
	_rebuild(layout, preview_only)

func _exit_tree() -> void:
	if is_instance_valid(_covered_floor):
		_covered_floor.set_terrain_coverage(get_instance_id(), false)
	_covered_floor = null

func apply_layout(value: Dictionary) -> void:
	layout = value.duplicate(true)
	_rebuild(layout, false)

func preview_layout(value: Dictionary) -> void:
	_rebuild(value, true)

func restore_preview() -> void:
	surface = _committed_surface
	_mesh.mesh = _committed_mesh

func _rebuild(value: Dictionary, draft: bool) -> void:
	if not is_node_ready():
		return
	surface = SURFACE.new(value)
	_mesh.mesh = surface.mesh(draft)
	if not draft and _collision != null:
		_committed_mesh = _mesh.mesh
		_committed_surface = surface
		_collision.shape = _committed_mesh.create_trimesh_shape()

func _cover_default_floor() -> void:
	if not is_inside_tree():
		return
	var floor := get_parent().get_node_or_null("Whitebox/Floor") as Node3D
	if floor == null or floor.get_script() != BLOCK or not floor.get_meta("godot_level_editor_default_floor", false):
		return
	# Only the untouched 20 m floor shipped in the blank level can be replaced.
	if floor.shape_kind != "box" or floor.visual_scene != null or floor.has_mesh_edit():
		return
	if not floor.size.is_equal_approx(Vector3(20, 3.6, 20)) or not floor.position.is_equal_approx(Vector3(0, -1.8, 0)):
		return
	if not floor.basis.is_equal_approx(Basis.IDENTITY) or not floor.get_parent().transform.is_equal_approx(Transform3D.IDENTITY):
		return
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		return
	_covered_floor = floor
	floor.set_terrain_coverage(get_instance_id(), true)
