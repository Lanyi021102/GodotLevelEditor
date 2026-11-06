extends Node3D
## 鸟瞰跟随相机：高角度俯视跟随玩家。
##   右键 / 中键拖动 = 旋转（水平转 yaw，竖直调俯角）
##   滚轮 = 拉近拉远
##   Q / E reserved for time navigation
## 用 SpringArm3D 做遮挡回退，避免相机穿进平台里。

@export var target_path: NodePath
@export var distance := 30.0
@export var min_distance := 12.0
@export var max_distance := 48.0
@export var zoom_step := 2.5
@export var pitch_degrees := 50.0
@export var min_pitch := 42.0
@export var max_pitch := 72.0
@export var yaw_degrees := 20.0
@export var rotate_speed := 0.3       ## 度 / 像素
@export var key_rotate_speed := 70.0  ## 度 / 秒
@export var follow_offset := Vector3(0.0, 1.2, 0.0)
@export var follow_smoothing := 12.0

var target: Node3D

@onready var arm: SpringArm3D = $Arm
@onready var camera: Camera3D = $Arm/Camera3D

var _dragging := false


func _ready() -> void:
	# 时间线冻结世界时，相机仍要能自由观察（docs/GDD.md §10.1）
	process_mode = Node.PROCESS_MODE_ALWAYS
	if target == null and target_path != NodePath():
		target = get_node_or_null(target_path)
	if target:
		global_position = target.global_position + follow_offset
	_apply()


func _process(delta: float) -> void:
	if target:
		var want := target.global_position + follow_offset
		var k := 1.0 - exp(-follow_smoothing * delta)
		global_position = global_position.lerp(want, k)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = clampf(distance - zoom_step, min_distance, max_distance)
					_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = clampf(distance + zoom_step, min_distance, max_distance)
					_apply()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw_degrees = fposmod(yaw_degrees - mm.relative.x * rotate_speed, 360.0)
		pitch_degrees = clampf(pitch_degrees + mm.relative.y * rotate_speed, min_pitch, max_pitch)
		_apply()


func _apply() -> void:
	rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	arm.rotation_degrees = Vector3(-pitch_degrees, 0.0, 0.0)
	arm.spring_length = distance
	if is_instance_valid(camera):
		camera.size = distance * 0.8


## 玩家用它把移动方向换算成相机朝向
func get_yaw_radians() -> float:
	return deg_to_rad(yaw_degrees)
