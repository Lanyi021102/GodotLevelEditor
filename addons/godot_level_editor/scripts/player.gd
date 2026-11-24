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
var interaction_target: Node3D
var interaction_hint: Label
const PROFILE_INPUT := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/player_input.gd")
const PROFILE_MOTION := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/traversal.gd")
const PROFILE_ANIMATIONS := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/animations.gd")
var player_preset: Resource
var player_config: Dictionary = {}
var profile_input: RefCounted
var traversal: RefCounted
var _extra_jump_used := false
var _vehicle: CharacterBody3D
var _vehicle_layers := Vector2i.ZERO
var _vehicle_was_visible := true

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
	if player_preset != null:
		profile_input = PROFILE_INPUT.new()
		profile_input.setup(player_preset, player_config, get_instance_id())
		traversal = PROFILE_MOTION.new()
		traversal.setup(self, player_config)
		if player_preset.model_scene == null:
			PROFILE_ANIMATIONS.attach(_model_root.anim)
		if _model_root.anim != null:
			for name: StringName in _model_root.anim.get_animation_library_list():
				var library := _model_root.anim.get_animation_library(name).duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as AnimationLibrary
				_model_root.anim.remove_animation_library(name)
				_model_root.anim.add_animation_library(name, library)
			var used := PackedStringArray()
			for clip in player_preset.clip_overrides.values():
				if str(clip).begins_with("imported/"): used.append(str(clip).trim_prefix("imported/"))
			if not used.is_empty() and not _model_root.anim.has_animation_library("imported"):
				var external := PROFILE_ANIMATIONS.external_library(_model_root.anim, player_preset.animation_scene, used)
				if external != null: _model_root.anim.add_animation_library("imported", external)
	_setup_model()
	if player_preset != null: _play_profile("idle", 0.0, true)

func _exit_tree() -> void:
	if is_instance_valid(_vehicle): _vehicle.release_rider(self)
	if profile_input != null: profile_input.dispose()

func configure_3c(preset: Resource) -> void:
	player_preset = preset
	player_config = preset.settings()
	for property in ["walk_speed", "run_speed", "acceleration", "deceleration", "turn_speed", "gravity", "air_acceleration", "jump_height", "crouch_speed"]:
		set(property, player_config[property])
	coyote_time = player_config.coyote_time if player_config.coyote else 0.0
	jump_buffer_time = player_config.jump_buffer_time if player_config.jump_buffer else 0.0
	var visual := get_node("ModelRoot") as CharacterModel
	visual.model_override = preset.model_scene
	visual.target_height = player_config.height
	visual.visible = player_config.view != 1


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
func _process(_delta: float) -> void:
	var anchor: Label3D
	if is_instance_valid(interaction_target) and interaction_target.has_meta(&"_gle_interaction_label"):
		anchor = interaction_target.get_meta(&"_gle_interaction_label") as Label3D
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(anchor) or not anchor.is_visible_in_tree() or camera == null or camera.is_position_behind(anchor.global_position):
		if is_instance_valid(interaction_hint): interaction_hint.hide()
		return
	if not is_instance_valid(interaction_hint):
		interaction_hint = preload("res://addons/godot_level_editor/scenes/ui/interaction_hint.tscn").instantiate()
		add_child(interaction_hint)
	var message := str(anchor.caption) + "  " + str(anchor.action_hint)
	if interaction_hint.text != message:
		interaction_hint.text = message
		interaction_hint.reset_size()
	var area := get_viewport().get_visible_rect()
	var point := camera.unproject_position(anchor.global_position)
	interaction_hint.visible = area.has_point(point)
	interaction_hint.position = (point - interaction_hint.size * 0.5).clamp(area.position, (area.end - interaction_hint.size).max(area.position)).round()


func _physics_process(delta: float) -> void:
	if is_instance_valid(_vehicle):
		_tick_vehicle(delta)
		return
	if player_preset != null:
		_tick_profile(delta)
		return
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
	interaction_target = _nearest_interaction() if input_enabled else null
	if interaction_target != null and Input.is_action_just_pressed("interact"):
		interaction_target.interact(self)
		if is_instance_valid(_vehicle): return

	if on_floor and not _was_on_floor:
		get_node("/root/GLENoiseBus").emit_pulse(global_position, hearing_land, self)   # 落地有声
	_emit_movement_noise(sprinting, delta)
	_update_animation(on_floor, delta)
	_was_on_floor = on_floor

func _tick_profile(delta: float) -> void:
	var grounded := is_on_floor()
	var enabled: bool = camera_rig == null or camera_rig.is_gameplay_input_enabled()
	var stick: Vector2 = profile_input.movement(player_config.move_deadzone) if enabled else Vector2.ZERO
	var direction := Vector3(stick.x, 0.0, stick.y)
	if player_config.move_reference == 0 and is_instance_valid(camera_rig):
		direction = Basis(Vector3.UP, camera_rig.get_yaw_radians()) * direction
	elif player_config.move_reference == 2:
		var facing := _model_root.global_rotation.y - PI - deg_to_rad(model_yaw_offset_degrees)
		direction = Basis(Vector3.UP, facing) * direction
	if not enabled:
		profile_input.clear_motion_toggles()
		_jump_buffer = 0.0

	if traversal.tick(delta, stick, direction, profile_input, enabled):
		var action: String = traversal.action
		interact_hint_target(false)
		_jump_buffer = 0.0
		_coyote = 0.0
		if action == "climb":
			_profile_animation(action, true, -stick.y * float(player_config.climb_speed) / 1.5)
		elif not action.is_empty():
			var key: String = player_preset.clip(action)
			var rate := _anim.get_animation(key).length / float(traversal.duration) if _anim != null and _anim.has_animation(key) else 1.0
			_profile_animation(action, false, rate)
		_was_on_floor = false
		return

	var wants_crouch: bool = enabled and player_config.crouch and profile_input.active("crouch", player_config.crouch_input)
	crouching = traversal.crouch(wants_crouch)
	var running := false
	var sprinting := false
	if enabled:
		running = player_config.run and (profile_input.stick_is_full() or profile_input.pressed("run") if player_config.run_input == 2 else profile_input.active("run", player_config.run_input))
		sprinting = player_config.sprint and profile_input.active("sprint", player_config.sprint_input)
	var speed: float = walk_speed if player_config.walk else 0.0
	if running: speed = run_speed
	if sprinting: speed = player_config.sprint_speed
	if crouching: speed = crouch_speed
	var desired := direction * speed
	var accel := (deceleration if desired.is_zero_approx() else acceleration) if grounded else air_acceleration
	velocity.x = move_toward(velocity.x, desired.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta)
	velocity.y = minf(velocity.y, 0.0) if grounded else velocity.y - gravity * delta
	if grounded: _extra_jump_used = false
	_coyote = coyote_time if grounded else maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	var jump_pressed: bool = enabled and player_config.jump and profile_input.just("jump")
	if jump_pressed: _jump_buffer = jump_buffer_time
	var jumped := false
	if player_config.jump and not crouching and (jump_pressed or _jump_buffer > 0):
		if grounded or _coyote > 0.0:
			velocity.y = sqrt(2.0 * gravity * jump_height)
			jumped = true
		elif jump_pressed and player_config.extra_jump and not _extra_jump_used:
			velocity.y = sqrt(2.0 * gravity * float(player_config.extra_jump_height))
			_extra_jump_used = true
			jumped = true
	if jumped:
		_jump_buffer = 0.0
		_coyote = 0.0
		_air_time = 0.0
		_profile_animation("jump_start")
	elif traversal.step(Vector3(velocity.x, 0.0, velocity.z) * delta) and not player_preset.clip("step").is_empty():
		_profile_animation("step")
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if player_config.face_camera == 1 and is_instance_valid(camera_rig):
		_face_3c_action(Basis(Vector3.UP, camera_rig.get_yaw_radians()) * Vector3.FORWARD, delta)
	elif flat.length() > 0.12 and player_config.move_reference != 2:
		_face_3c_action(flat, delta)
	move_and_slide()
	interact_hint_target(enabled and player_config.interact)
	if interaction_target != null and profile_input.just("interact") and interaction_target.interact(self):
		if is_instance_valid(_vehicle): return
		if is_on_floor() and flat.length() < 0.12: _profile_animation("interact")
	if not grounded and is_on_floor():
		get_node("/root/GLENoiseBus").emit_pulse(global_position, hearing_land, self)
		if _state != "step": _profile_animation("land")
	_emit_movement_noise((running or sprinting) and not crouching, delta)
	_air_time = 0.0 if is_on_floor() else _air_time + delta
	if not jumped: _update_profile_locomotion(running, sprinting)
	_was_on_floor = is_on_floor()

func interact_hint_target(enabled: bool) -> void:
	interaction_target = _nearest_interaction() if enabled else null

func _face_3c_action(direction: Vector3, delta := -1.0) -> void:
	if direction.is_zero_approx(): return
	var yaw := atan2(direction.x, direction.z) + deg_to_rad(model_yaw_offset_degrees)
	var weight := 1.0 if delta < 0.0 else 1.0 - exp(-turn_speed * delta)
	_model_root.global_rotation.y = lerp_angle(_model_root.global_rotation.y, yaw, weight)

func _update_profile_locomotion(running: bool, sprinting: bool) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if _state == "step" and _anim != null and _anim.is_playing() and speed >= 0.12 and velocity.y > -1.0: return
	if _state in ["jump_start", "land", "interact"] and _anim != null and _anim.is_playing():
		if (_state == "jump_start" and not is_on_floor()) or (_state == "land" and is_on_floor() and speed < 0.8) or (_state == "interact" and speed < 0.12):
			return
	var next := "idle"
	if not is_on_floor(): next = "air"
	elif crouching: next = "crouch" if speed > 0.12 else "crouch_idle"
	elif speed > 0.12:
		next = "sprint" if sprinting else "run" if running else "walk"
	var play_speed := 1.0
	match next:
		"crouch": play_speed = clampf(speed / float(get("crouch_animation_speed")), 0.55, 2.2)
		"walk": play_speed = clampf(speed / float(get("walk_animation_speed")), 0.55, 2.1)
		"run": play_speed = clampf(speed / float(get("run_animation_speed")), 0.65, 1.65)
		"sprint": play_speed = clampf(speed / 5.5, 0.65, 1.65)
	_profile_animation(next, true, play_speed)

func _profile_animation(slot: String, loop := false, rate := 1.0) -> void:
	if _state != slot:
		_state = slot
		_play_profile(slot, blend_time, loop)
	_model_root.set_speed_scale(rate)

func _play_profile(slot: String, blend: float, looping: bool) -> void:
	if _anim == null: return
	var clip: String = player_preset.clip(slot)
	if clip.is_empty() or not _anim.has_animation(clip):
		_anim.stop()
		return
	var animation := _anim.get_animation(clip)
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	_anim.play(clip, blend)


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
	if is_instance_valid(_vehicle):
		_vehicle.release_rider(self)
		detach_vehicle(_vehicle)
	if traversal != null: traversal.reset()
	if profile_input != null: profile_input.clear_motion_toggles()
	_extra_jump_used = false
	velocity = Vector3.ZERO
	global_transform = spawn_transform
	_model_root.rotation.y = deg_to_rad(start_facing_degrees) + deg_to_rad(model_yaw_offset_degrees)
	_state = ""
	_lock = 0.0
	_air_time = 0.0
	_coyote = 0.0
	_jump_buffer = 0.0
	_was_on_floor = true
	if player_preset != null:
		_profile_animation("idle", true)
	elif _anim:
		_play(idle_clip, 0.0)


## 使用同一交互合同试玩机关和台本。
func interact_nearest() -> bool:
	if player_preset != null and not player_config.interact: return false
	interaction_target = _nearest_interaction()
	return interaction_target != null and interaction_target.interact(self)

func _nearest_interaction() -> Node3D:
	var nearest: Node3D
	var distance := INF
	for endpoint in get_tree().get_nodes_in_group("godot_level_editor_interactable"):
		if endpoint.is_visible_in_tree() and endpoint.can_process() and endpoint.has_method("can_interact") and endpoint.can_interact(self):
			var anchor: Vector3 = endpoint.interaction_position() if endpoint.has_method("interaction_position") else endpoint.global_position
			var d := global_position.distance_squared_to(anchor)
			if player_preset != null and d > float(player_config.interact_distance) ** 2: continue
			if d < distance:
				distance = d
				nearest = endpoint
	return nearest


func can_drive_vehicle() -> bool:
	return not is_instance_valid(_vehicle) and (player_preset == null or player_config.get("drive_vehicles", true))

func attach_vehicle(vehicle: CharacterBody3D) -> bool:
	if not can_drive_vehicle(): return false
	if traversal != null: traversal.reset()
	if profile_input != null: profile_input.clear_motion_toggles()
	_vehicle = vehicle
	_vehicle_layers = Vector2i(collision_layer, collision_mask)
	_vehicle_was_visible = _model_root.visible
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_coyote = 0.0
	_jump_buffer = 0.0
	_model_root.visible = true
	if is_instance_valid(camera_rig) and camera_rig.has_method("set_vehicle_target"):
		camera_rig.set_vehicle_target(vehicle)
	return true

func detach_vehicle(vehicle: CharacterBody3D) -> void:
	if _vehicle != vehicle: return
	_vehicle = null
	collision_layer = _vehicle_layers.x
	collision_mask = _vehicle_layers.y
	_model_root.visible = _vehicle_was_visible
	_model_root.rotation.z = 0.0
	_state = ""
	_lock = 0.0
	_was_on_floor = true
	_air_time = 0.0
	_extra_jump_used = false
	interaction_target = null
	if is_instance_valid(camera_rig) and camera_rig.has_method("set_vehicle_target"):
		camera_rig.set_vehicle_target(null)

func vehicle_collision_shape() -> CollisionShape3D:
	return get_node_or_null("Collision") as CollisionShape3D

func face_vehicle(vehicle_yaw: float, lean: float) -> void:
	_model_root.global_rotation = Vector3(0.0, vehicle_yaw + PI + deg_to_rad(model_yaw_offset_degrees), lean)

func play_vehicle_animation(requested: String, slot: String) -> float:
	var fallback := 0.45
	if _anim == null: return fallback
	_model_root.set_speed_scale(1.0)
	var clip := requested
	if clip.is_empty() or not _anim.has_animation(clip):
		const CLIPS := {"vehicle_board": "Sitting_Enter", "vehicle_seated": "Sitting_Idle", "vehicle_exit": "Sitting_Exit"}
		var original: String = CLIPS[slot]
		clip = original
		if not _anim.has_animation(clip):
			PROFILE_ANIMATIONS.attach_vehicle(_anim)
			clip = "vehicle/" + original
	if not _anim.has_animation(clip):
		_play(idle_clip, 0.1)
		return fallback
	var length := _anim.get_animation(clip).length
	var duration := clampf(length, 0.3, 1.05)
	_anim.play(clip, 0.12, length / duration, false)
	if slot == "vehicle_seated": _anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return duration

func _tick_vehicle(delta: float) -> void:
	var enabled: bool = not is_instance_valid(camera_rig) or not camera_rig.has_method("is_gameplay_input_enabled") or camera_rig.is_gameplay_input_enabled()
	var stick := Vector2.ZERO
	var lift := 0.0
	var interact := false
	if enabled:
		if profile_input != null:
			stick = profile_input.movement(player_config.move_deadzone)
			lift = float(profile_input.pressed("jump")) - float(profile_input.pressed("crouch") or profile_input.pressed("run"))
			interact = profile_input.just("interact")
		else:
			stick = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			lift = Input.get_axis("sprint", "jump")
			interact = Input.is_action_just_pressed("interact")
	_vehicle.tick_rider(delta, stick, lift, interact)
