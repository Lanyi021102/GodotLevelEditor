@tool
extends Node3D
const GROUPS := preload("res://addons/godot_level_editor/scene_groups.gd")
signal player_entered(room_id: String, actor: Node3D)
signal player_exited(room_id: String, actor: Node3D)
var _region: Area3D
var _bounds_signature := Vector3.ZERO
@export var room_id := "room"
@export var display_name := "房间"
@export var uses_topology := true
@export var bounds_size := Vector3(20, 4, 20)

func _enter_tree() -> void:
	if room_id.is_empty(): room_id = "room_" + Crypto.new().generate_random_bytes(10).hex_encode()

func _ready() -> void:
	_build_region()
	if Engine.is_editor_hint(): return
	for child in GROUPS.contents(self):
		if child.get_script() == preload("res://addons/godot_level_editor/runtime/placement.gd") and child.component_kind == "door" and child.runtime_component != null and child.component_scene == null:
			for id in child.source_ids:
				var source := object_by_id(id)
				if source != null:
					child.runtime_component.add_power_source(source)

func object_by_id(id: String) -> Node:
	for child in GROUPS.contents(self):
		if child.get("object_id") == id:
			return child
	return null

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	for child in GROUPS.contents(self):
		var id: Variant = child.get("object_id")
		if not id is String: continue
		if not id.is_valid_identifier() or ids.has(id): errors.append("房间对象 ID 无效或重复：" + id)
		ids[id] = true
		if child.get_script() == preload("res://addons/godot_level_editor/runtime/whitebox_block.gd"): errors.append_array(child.validate())
		if child is Node3D and (not child.transform.is_finite() or (child.get_script() != preload("res://addons/godot_level_editor/runtime/whitebox_block.gd") and not child.scale.is_equal_approx(Vector3.ONE))):
			errors.append(id + "：请使用有限坐标和尺寸参数，保持单位缩放")
		if child.get_script() == preload("res://addons/godot_level_editor/runtime/placement.gd"):
			if child.component_kind == "door" and child.component_scene == null:
				for source in child.source_ids:
					if object_by_id(source) == null: errors.append(id + "：机关来源缺失 " + source)
			if child.component_scene != null:
				var instance: Node = child.component_scene.instantiate()
				if not instance is Node3D: errors.append(id + "：复用组件的场景根必须为三维节点")
				if not child.component_output_path.is_empty() and instance.get_node_or_null(child.component_output_path) == null:
					errors.append(id + "：复用组合的输出对象不存在")
				instance.free()
	return errors

func _build_region() -> void:
	_bounds_signature = bounds_size
	if Engine.is_editor_hint():
		for child in get_children():
			if child.get_meta("godot_level_editor_room_preview", false): child.free()
		var preview := MeshInstance3D.new()
		preview.set_meta("godot_level_editor_room_preview", true)
		var edges := PackedVector3Array()
		var box := AABB(-bounds_size * 0.5, bounds_size)
		for i in 8:
			for axis in 3:
				var other := i ^ (1 << axis)
				if i < other:
					edges.append(box.get_endpoint(i))
					edges.append(box.get_endpoint(other))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = edges
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		preview.mesh = mesh
		preview.position.y = bounds_size.y * 0.5
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.2, 0.8, 0.75, 0.75)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		preview.material_override = material
		add_child(preview)
		update_gizmos()
		return
	var corners := PackedVector3Array()
	var x := bounds_size.x * 0.5
	var z := bounds_size.z * 0.5
	var points := [Vector3(-x, 0.04, -z), Vector3(x, 0.04, -z), Vector3(x, 0.04, z), Vector3(-x, 0.04, z)]
	for i in 4:
		corners.append(points[i])
		corners.append(points[(i + 1) % 4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = corners
	var outline_mesh := ArrayMesh.new()
	outline_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var outline := MeshInstance3D.new()
	outline.mesh = outline_mesh
	var outline_mat := StandardMaterial3D.new()
	outline_mat.albedo_color = Color("55c8df")
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.material_override = outline_mat
	add_child(outline)
	_region = Area3D.new()
	_region.name = "RoomVolume"
	_region.collision_layer = 0
	_region.collision_mask = 2
	var shape := BoxShape3D.new()
	shape.size = bounds_size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = bounds_size.y * 0.5
	_region.add_child(cs)
	add_child(_region)
	_region.body_entered.connect(func(body: Node3D):
		if _controlled(body): player_entered.emit(room_id, body))
	_region.body_exited.connect(func(body: Node3D):
		if _controlled(body): player_exited.emit(room_id, body))

func _controlled(body: Node3D) -> bool:
	return body.is_in_group("godot_level_editor_player") and not (body.has_method("is_clone") and body.call("is_clone"))

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _bounds_signature != bounds_size:
		bounds_size = bounds_size.snapped(Vector3.ONE * 0.1).max(Vector3.ONE * 0.1)
		_build_region()
