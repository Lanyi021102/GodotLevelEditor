extends CharacterBody3D
## 玩家角色：相机相对移动 + 跳跃 + 动画状态机（待机 / 走 / 跑 / 空中 / 落地）。
## 角色模型由 CharacterModel 提供，当前使用正常比例骨骼角色。

@export_group("移动")
@export var walk_speed := 4.2
@export var run_speed := 8.0
@export var acceleration := 26.0
@export var deceleration := 32.0
@export var air_acceleration := 7.0
@export var gravity := 24.0
@export var jump_height := 1.7
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var turn_speed := 14.0

@export_group("潜行（docs/GDD.md §6）")
## 蹲行速度（蹲行无声）
@export var crouch_speed := 2.0
## 奔跑噪音半径（GDD §6.1）
@export var hearing_run := 8.0
## 落地噪音半径
@export var hearing_land := 5.0

@export_group("模型")
## 模型相关参数（模型、缩放、灰白材质）在 ModelRoot 节点的 CharacterModel 组件上
## 模型自带的朝向和 Godot 的 -Z 前方不一致时，用它修正（0 或 180 通常就够了）
@export var model_yaw_offset_degrees := 0.0
## 出生朝向：0 = 面向 +Z（南），180 = 面向 -Z（北，背对默认相机）
@export var start_facing_degrees := 180.0
@export var white_albedo := Color(0.86, 0.86, 0.875)

@export_group("动画")
@export var idle_clip := "Idle"
@export var walk_clip := "Walking_A"
@export var run_clip := "Running_A"
@export var jump_start_clip := "Jump_Start"
@export var jump_air_clip := "Jump_Idle"
@export var jump_land_clip := "Jump_Land"
@export var blend_time := 0.15

var camera_rig: Node3D
var spawn_transform: Transform3D

@onready var _model_root: CharacterModel = $ModelRoot

var _anim: AnimationPlayer
var _state := ""
var _lock := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _air_time := 0.0
var _was_on_floor := true
## 是否正蹲着（潜行：更慢、更省、完全无声，守卫也更难看到）
var crouching := false
var _noise_timer := 0.0


func _ready() -> void:
	# 角色放在第 2 层、只和第 1 层（世界）碰撞：
	# 角色只与世界碰撞，便于在白盒里测试动线。
	collision_layer = 2
	collision_mask = 1
	add_to_group("stealth_target")
	add_to_group("godot_level_editor_player")
	spawn_transform = global_transform
	_setup_model()


# --------------------------------------------------------------------------
# 模型（实际装载逻辑在 scripts/actors/character_model.gd，玩家和守卫共用）
# --------------------------------------------------------------------------
func _setup_model() -> void:
	if _model_root.anim == null:
		push_error("模型没有装载成功：%s" % _model_root.model_scene)
		return
	_anim = _model_root.anim
	_model_root.set_tint(white_albedo, 1.0)
	_state = "idle"
	_play(idle_clip, 0.0)
	_model_root.rotation.y = deg_to_rad(start_facing_degrees) + deg_to_rad(model_yaw_offset_degrees)


# --------------------------------------------------------------------------
# 主循环
# --------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	var input_enabled: bool = camera_rig == null or not camera_rig.has_method("is_gameplay_input_enabled") or camera_rig.is_gameplay_input_enabled()

	_coyote = coyote_time if on_floor else maxf(_coyote - delta, 0.0)
	_air_time = 0.0 if on_floor else _air_time + delta
	_jump_buffer = jump_buffer_time if input_enabled and Input.is_action_just_pressed("jump") else maxf(_jump_buffer - delta, 0.0)

	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	var dir := Vector3(input_dir.x, 0.0, input_dir.y)
	if not input_enabled:
		dir = Vector3.ZERO
		_jump_buffer = 0.0
	if camera_rig:
		dir = Basis(Vector3.UP, camera_rig.get_yaw_radians()) * dir
	if dir.length() > 1.0:
		dir = dir.normalized()

	var sprinting: bool = input_enabled and Input.is_action_pressed("sprint")
	crouching = false
	if crouching:
		sprinting = false

	var speed := crouch_speed if crouching else (run_speed if sprinting else walk_speed)
	var accel := (deceleration if dir.length_squared() < 0.001 else acceleration) if on_floor else air_acceleration
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_v.z, accel * delta)

	if on_floor:
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= gravity * delta
	if _jump_buffer > 0.0:
		if _coyote > 0.0:
			velocity.y = sqrt(2.0 * gravity * jump_height)
			_jump_buffer = 0.0
			_coyote = 0.0
			_was_on_floor = false

	if dir.length_squared() > 0.001:
		var want_yaw := atan2(dir.x, dir.z) + deg_to_rad(model_yaw_offset_degrees)
		_model_root.rotation.y = lerp_angle(_model_root.rotation.y, want_yaw, minf(1.0, turn_speed * delta))

	move_and_slide()
	if input_enabled and Input.is_action_just_pressed("interact"):
		interact_nearest()

	if on_floor and not _was_on_floor:
		get_node("/root/GLENoiseBus").emit_pulse(global_position, hearing_land, self)   # 落地有声
	_emit_movement_noise(sprinting, delta)
	_update_animation(on_floor, delta)
	_was_on_floor = on_floor


## Running and landing still supply perception cues; there is no resource cost.
func _emit_movement_noise(sprinting: bool, delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if planar < 0.15:
		return
	var running := (sprinting and planar > walk_speed * 1.05) or planar > run_speed * 0.9
	if crouching:
		return
	_noise_timer -= delta
	if running and _noise_timer <= 0.0:
		get_node("/root/GLENoiseBus").emit_pulse(global_position, hearing_run, self)
		_noise_timer = 0.4


func is_crouching() -> bool:
	return crouching


func _update_animation(on_floor: bool, delta: float) -> void:
	if _anim == null:
		return
	if _lock > 0.0:
		_lock = maxf(_lock - delta, 0.0)
		return

	var planar := Vector2(velocity.x, velocity.z).length()
	var next := "idle"
	# 刚离开地面的一两帧不算“空中”，避免出生/走下小台阶时闪跳
	if not on_floor and _air_time > 0.08:
		next = "air"
	elif crouching and planar > 0.15:
		next = "crouch"
	elif planar > 0.15:
		next = "run" if planar > walk_speed * 1.15 else "walk"
	if on_floor and not _was_on_floor:
		next = "land"

	if next != _state:
		_state = next
		match _state:
			"idle":
				_model_root.set_speed_scale(1.0)
				_play(idle_clip)
			"walk":
				_play(walk_clip)
			"crouch":
				_play(_model_root.crouch_clip)
			"run":
				_play(run_clip)
			"air":
				_play(jump_start_clip if velocity.y > 0.5 else jump_air_clip)
			"land":
				_play(jump_land_clip)
				_lock = 0.12

	if _state == "walk":
		_model_root.set_speed_scale(clampf(planar / maxf(walk_speed, 0.1), 0.5, 1.8))
	elif _state == "run":
		_model_root.set_speed_scale(clampf(planar / maxf(run_speed, 0.1), 0.6, 1.6))


func _play(clip: String, blend := blend_time) -> void:
	_model_root.play(clip, blend)


# --------------------------------------------------------------------------
# 外部调用
# --------------------------------------------------------------------------
func reset_to_spawn() -> void:
	velocity = Vector3.ZERO
	global_transform = spawn_transform
	_model_root.rotation.y = deg_to_rad(start_facing_degrees) + deg_to_rad(model_yaw_offset_degrees)
	_state = ""
	_lock = 0.0
	_air_time = 0.0
	_coyote = 0.0
	_jump_buffer = 0.0
	_was_on_floor = true
	if _anim:
		_play(idle_clip, 0.0)


## 使用同一交互合同试玩机关和台本。
func interact_nearest() -> bool:
	var nearest: Node3D
	var distance := INF
	for endpoint in get_tree().get_nodes_in_group("godot_level_editor_interactable"):
		if endpoint.has_method("can_interact") and endpoint.can_interact(self):
			var d := global_position.distance_squared_to(endpoint.global_position)
			if d < distance:
				distance = d
				nearest = endpoint
	if nearest == null or not nearest.interact(self): return false
	return true
