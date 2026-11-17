class_name PressurePlate
extends Area3D
## 压力板（docs/GDD.md §8 P1）：有角色站在上面就通电；离开后延迟 release_delay 秒断电。
## 可被时间线回退——所以"回退到踩板之前"会让门重新关上。

signal power_changed(powered: bool)

@export var release_delay := 2.0
@export var plate_size := Vector2(2.4, 2.4)
@export var thickness := 0.14
@export var color_idle := Color(0.70, 0.70, 0.74, 1.0)
@export var color_active := Color(0.32, 0.86, 0.74, 1.0)

var powered := false

var _release_timer := 0.0
var _visual: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2          # 只检测角色（第 2 层）
	monitoring = true
	_build_visual()
	_refresh_visual()


func _build_visual() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = color_idle
	_material.roughness = 0.7
	_visual = MeshInstance3D.new()
	_visual.name = "Plate"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(plate_size.x, thickness, plate_size.y)
	_visual.mesh = mesh
	_visual.material_override = _material
	_visual.position = Vector3(0.0, thickness * 0.5, 0.0)
	add_child(_visual)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var shape := BoxShape3D.new()
	# 检测体做高：角色站在地面上时胶囊能盖住它；Area 不挡路，所以不用做台阶
	shape.size = Vector3(plate_size.x, 1.6, plate_size.y)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.8, 0.0)
	add_child(cs)


func _physics_process(delta: float) -> void:
	if occupant_count() > 0:
		_release_timer = release_delay
		_set_powered(true)
	elif powered:
		_release_timer -= delta
		if _release_timer <= 0.0:
			_set_powered(false)


## 站在板上的有效角色数量；隐藏或停止物理处理的身体不计入。
func occupant_count() -> int:
	var n := 0
	for body in get_overlapping_bodies():
		if body is CharacterBody3D and body.is_in_group("stealth_target") and body.visible and body.is_physics_processing():
			n += 1
	return n


func is_powered() -> bool:
	return powered


func _set_powered(value: bool) -> void:
	if value == powered:
		return
	powered = value
	_refresh_visual()
	power_changed.emit(powered)


func _refresh_visual() -> void:
	if _material == null:
		return
	_material.albedo_color = color_active if powered else color_idle
	_material.emission_enabled = powered
	_material.emission = color_active
	_material.emission_energy_multiplier = 0.6


# --------------------------------------------------------------------------
# 时间线接口
# --------------------------------------------------------------------------
func tl_capture() -> Dictionary:
	return {"powered": powered, "timer": _release_timer}


func tl_restore(state: Dictionary) -> void:
	powered = bool(state["powered"])
	_release_timer = float(state["timer"])
	_refresh_visual()
	power_changed.emit(powered)
