@tool
extends Node3D
const GROUPS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
signal player_entered(room_id: String, actor: Node3D)
signal player_exited(room_id: String, actor: Node3D)
signal activation_changed(active: bool)
var _region: Area3D
var _bounds_signature: Array = []
var _players: Dictionary = {}
var _active_state := false
var _detection_enabled := true
@export var room_id := "room"
@export var display_name := "房间"
@export var uses_topology := true
## Legacy scene defaults stay intact; new trigger presets explicitly use one metre.
@export var bounds_size := Vector3(20, 4, 20)
@export var keep_active_on_exit := false
@export var volume_material: Material

func _enter_tree() -> void:
	if room_id.is_empty(): room_id = "room_" + Crypto.new().generate_random_bytes(10).hex_encode()

func _ready() -> void:
	_build_region()
	if Engine.is_editor_hint(): return
	for child in GROUPS.contents(self):
		if child.get_script() == preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/placement.gd") and child.component_kind == "door" and child.runtime_component != null and child.component_scene == null:
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
		if child.get_script() == preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd"): errors.append_array(child.validate())
		if child is Node3D and (not child.transform.is_finite() or (child.get_script() != preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd") and not child.scale.is_equal_approx(Vector3.ONE))):
			errors.append(id + "：请使用有限坐标和尺寸参数，保持单位缩放")
		if child.get_script() == preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/placement.gd"):
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

func _scope() -> String:
	var profile: Resource = get_meta("godot_level_editor_entity") if has_meta("godot_level_editor_entity") else null
	return str(profile.lifetime) if profile != null else "level"

func preview_color() -> Color:
	return Color(0.58, 0.88, 0.52, 0.24) if _scope() == "task" else Color(0.12, 0.42, 0.21, 0.24)

func is_active() -> bool:
	return _active_state and _detection_enabled

func set_detection_enabled(enabled: bool) -> void:
	if _detection_enabled == enabled: return
	_detection_enabled = enabled
	if not enabled:
		_players.clear()
		_set_active(false)
	if is_instance_valid(_region): _region.set_deferred("monitoring", enabled)

func _set_active(value: bool) -> void:
	if _active_state == value: return
	_active_state = value
	activation_changed.emit(value)

func _body_entered(body: Node3D) -> void:
	if not _detection_enabled or not _controlled(body) or _players.has(body.get_instance_id()): return
	_players[body.get_instance_id()] = weakref(body)
	_set_active(true)
	player_entered.emit(room_id, body)

func _body_exited(body: Node3D) -> void:
	if not _players.has(body.get_instance_id()): return
	_players.erase(body.get_instance_id())
	if _players.is_empty() and not keep_active_on_exit: _set_active(false)
	player_exited.emit(room_id, body)

func _controlled(body: Node3D) -> bool:
	return body.is_in_group("godot_level_editor_player") and not (body.has_method("is_clone") and body.call("is_clone"))

func _volume_signature() -> Array:
	return [bounds_size, uses_topology, _scope(), volume_material]

func _build_region() -> void:
	refresh_volume()

func refresh_volume() -> void:
	if not is_inside_tree(): return
	_bounds_signature = _volume_signature()
	for child in get_children():
		if child.get_meta("godot_level_editor_room_preview", false): child.free()
	if Engine.is_editor_hint() or uses_topology:
		var preview := MeshInstance3D.new()
		preview.name = "RoomPreview"
		preview.set_meta("godot_level_editor_room_preview", true)
		preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not uses_topology:
			var mesh := BoxMesh.new(); mesh.size = bounds_size
			preview.mesh = mesh; preview.position.y = bounds_size.y * 0.5
			var material := StandardMaterial3D.new()
			material.albedo_color = preview_color()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			preview.material_override = volume_material if volume_material != null else material
		else:
			var edges := PackedVector3Array()
			var box := AABB(Vector3(-bounds_size.x * 0.5, 0, -bounds_size.z * 0.5), bounds_size)
			if Engine.is_editor_hint():
				for i in 8:
					for axis in 3:
						var other := i ^ (1 << axis)
						if i < other: edges.append(box.get_endpoint(i)); edges.append(box.get_endpoint(other))
			else:
				var corners := [Vector3(box.position.x, 0.04, box.position.z), Vector3(box.end.x, 0.04, box.position.z), Vector3(box.end.x, 0.04, box.end.z), Vector3(box.position.x, 0.04, box.end.z)]
				for i in 4: edges.append(corners[i]); edges.append(corners[(i + 1) % 4])
			var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = edges
			var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays); preview.mesh = mesh
			var material := StandardMaterial3D.new(); material.albedo_color = Color(0.2, 0.8, 0.75, 0.75)
			if not Engine.is_editor_hint(): material.albedo_color = Color("55c8df")
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			preview.material_override = material
		add_child(preview)
	if Engine.is_editor_hint():
		update_gizmos()
		return
	if not is_instance_valid(_region):
		_region = Area3D.new(); _region.name = "RoomVolume"; _region.collision_layer = 0; _region.collision_mask = 2
		var collision := CollisionShape3D.new(); collision.name = "Shape"; collision.shape = BoxShape3D.new(); _region.add_child(collision)
		add_child(_region)
		_region.body_entered.connect(_body_entered); _region.body_exited.connect(_body_exited)
	var collision := _region.get_node("Shape") as CollisionShape3D
	collision.shape.size = bounds_size; collision.position.y = bounds_size.y * 0.5

func _process(_delta: float) -> void:
	if _bounds_signature != _volume_signature():
		if Engine.is_editor_hint(): bounds_size = bounds_size.snapped(Vector3.ONE * 0.1).max(Vector3.ONE * 0.1)
		refresh_volume()
