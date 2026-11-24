extends "res://addons/godot_level_editor/scripts/player.gd"
## Normal-proportion whitebox locomotion.
@export var walk_animation_speed := 0.90
@export var run_animation_speed := 5.43
@export var crouch_animation_speed := 0.66

func _ready() -> void:
	super._ready()

func _physics_process(delta: float) -> void:
	if player_preset != null or is_instance_valid(_vehicle):
		super._physics_process(delta)
		return
	var yaw_before := _model_root.rotation.y
	super._physics_process(delta)
	var flat := Vector2(velocity.x, velocity.z)
	# Turn with actual travel, including reversals and braking, rather than turning ahead of the feet.
	if flat.length() > 0.12:
		var desired := atan2(velocity.x, velocity.z) + deg_to_rad(model_yaw_offset_degrees)
		var yaw := lerp_angle(yaw_before, desired, 1.0 - exp(-turn_speed * delta))
		if absf(angle_difference(_model_root.rotation.y, yaw)) > 0.00001:
			_model_root.rotation.y = yaw
	elif absf(angle_difference(_model_root.rotation.y, yaw_before)) > 0.00001:
		_model_root.rotation.y = yaw_before

func _update_animation(on_floor: bool, delta: float) -> void:
	if _anim == null:
		return
	if _lock > 0:
		_lock = maxf(_lock - delta, 0)
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var next := "idle"
	if not on_floor and _air_time > 0.08:
		next = "air"
	elif crouching:
		next = "crouch" if speed > 0.12 else "crouch_idle"
	elif speed > 0.12:
		next = "run" if speed > walk_speed * 1.18 else "walk"
	if on_floor and not _was_on_floor:
		next = "land"
	if next != _state:
		_state = next
		match _state:
			"idle": _play(idle_clip, 0.14)
			"walk": _play(walk_clip, 0.13)
			"run": _play(run_clip, 0.14)
			"crouch": _play(_model_root.crouch_clip, 0.17)
			"crouch_idle": _play("Crouch_Idle", 0.17)
			"air": _play(jump_start_clip if velocity.y > 0.5 else jump_air_clip, 0.1)
			"land":
				_play(jump_land_clip, 0.08)
				_lock = 0.10
	match _state:
		"walk": _model_root.set_speed_scale(clampf(speed / walk_animation_speed, 0.55, 2.1))
		"run": _model_root.set_speed_scale(clampf(speed / run_animation_speed, 0.65, 1.65))
		"crouch": _model_root.set_speed_scale(clampf(speed / crouch_animation_speed, 0.55, 2.2))
		_: _model_root.set_speed_scale(1.0)
