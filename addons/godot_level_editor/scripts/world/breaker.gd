class_name Breaker
extends PressurePlate
## 电闸（docs/GDD.md §8 P3）：站上去才通电（第一次通电消耗 cost 能量），离开 5 秒后自动复位。
## 通电时"拉闸关灯"：房间里的动态暗区被打开，守卫视距随之降到 40%。

@export var cost := 6.0
## 关灯后的暗区（相对本节点的世界偏移与尺寸）
@export var dark_offset := Vector3(0.0, 1.7, 0.0)
@export var dark_size := Vector3(14.0, 3.6, 12.0)
@export var dark_level := 0.32

var _dark_id := -1
var _dark_patch: MeshInstance3D
var _charged := false


func _ready() -> void:
	release_delay = 5.0
	color_idle = Color(0.62, 0.45, 0.30, 1.0)
	color_active = Color(0.95, 0.80, 0.25, 1.0)
	super._ready()
	_dark_id = get_node("/root/GLELightZones").register_dynamic_box_center(global_position + dark_offset, dark_size, dark_level)
	_build_dark_patch()


func _build_visual() -> void:
	# 电闸做成控制箱 + 拉杆，和压力板区分开
	_material = StandardMaterial3D.new()
	_material.albedo_color = color_idle
	_material.roughness = 0.6
	_visual = MeshInstance3D.new()
	_visual.name = "BreakerBox"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2, 1.4, 0.8)
	_visual.mesh = mesh
	_visual.material_override = _material
	_visual.position = Vector3(0.0, 0.7, 0.0)
	add_child(_visual)
	var lever := MeshInstance3D.new()
	lever.name = "Lever"
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.16, 0.9, 0.16)
	lever.mesh = lever_mesh
	lever.material_override = _material
	lever.position = Vector3(0.0, 0.9, 0.5)
	lever.rotation_degrees = Vector3(35.0, 0.0, 0.0)
	add_child(lever)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 1.6, 2.2)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.8, 0.0)
	add_child(cs)


func _build_dark_patch() -> void:
	_dark_patch = MeshInstance3D.new()
	_dark_patch.name = "DarkPatch"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(dark_size.x, 0.05, dark_size.z)
	_dark_patch.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.01, 0.035, 0.07, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dark_patch.material_override = mat
	_dark_patch.position = dark_offset + Vector3(0.0, -dark_offset.y + 0.04, 0.0)
	_dark_patch.visible = false
	add_child(_dark_patch)


func _set_powered(value: bool) -> void:
	var first := value and not powered
	super._set_powered(value)
	if first and not _charged:
		_charged = true
	if _dark_id >= 0:
		get_node("/root/GLELightZones").set_dynamic_enabled(_dark_id, powered)
	if _dark_patch != null:
		_dark_patch.visible = powered


func tl_capture() -> Dictionary:
	var d := super.tl_capture()
	d["charged"] = _charged
	return d


func tl_restore(state: Dictionary) -> void:
	super.tl_restore(state)
	_charged = bool(state.get("charged", false))
	if _dark_id >= 0:
		get_node("/root/GLELightZones").set_dynamic_enabled(_dark_id, powered)
	if _dark_patch != null:
		_dark_patch.visible = powered
