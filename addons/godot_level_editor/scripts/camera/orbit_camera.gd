extends Node3D
## Shared third-person shoulder camera. View state stays outside gameplay state snapshots.

@export var target_path: NodePath
@export_group("第三人称构图")
@export_range(1.0, 8.0, 0.1) var distance := 3.8
@export var min_distance := 2.2
@export var max_distance := 6.0
@export var zoom_step := 0.35
@export var pitch_degrees := 10.0
@export var min_pitch := -35.0
@export var max_pitch := 65.0
@export var yaw_degrees := 0.0
@export var follow_offset := Vector3(0.0, 1.45, 0.0)
@export var shoulder_offset := 0.55
@export_range(40.0, 90.0, 1.0) var field_of_view := 65.0
@export_group("近距观察")
@export var focus_distance := 2.3
@export var focus_shoulder_offset := 0.65
@export_range(30.0, 80.0, 1.0) var focus_field_of_view := 50.0
@export var focus_smoothing := 12.0
@export_group("跟随与输入")
@export var rotate_speed := 0.16 # Degrees per unscaled mouse pixel.
@export var invert_vertical := false
@export var follow_smoothing := 18.0
@export var teleport_snap_distance := 6.0
@export var capture_mouse_on_start := true
@export_flags_3d_physics var world_collision_mask := 1
@export var collision_radius := 0.18

var target: Node3D
@onready var arm: SpringArm3D = $Arm
@onready var camera: Camera3D = $Arm/Camera3D
var _shoulder_side := 1.0
var _focus_held := false
var _controls_active := true
var _current_distance := 3.8
var _current_shoulder := 0.55
var _sweep_shape := SphereShape3D.new()
var _dialogue_visible := false
var _restore_after_dialogue := false
var _profile: Dictionary = {}
var _vehicle_target: Node3D
var _vehicle_rid := RID()
var _walking_angles := Vector2.ZERO

func configure_3c(settings: Dictionary) -> void:
	_profile = settings
	distance = settings.distance
	min_distance = minf(distance, 2.2)
	max_distance = maxf(distance, 6.0)
	shoulder_offset = settings.shoulder if settings.view == 0 else 0.0
	focus_shoulder_offset = settings.focus_shoulder if settings.view == 0 else 0.0
	yaw_degrees = settings.yaw
	pitch_degrees = settings.pitch
	min_pitch = settings.min_pitch
	max_pitch = settings.max_pitch
	field_of_view = settings.fov
	focus_field_of_view = settings.focus_fov
	focus_distance = settings.focus_distance
	focus_smoothing = settings.focus_smoothing
	follow_smoothing = settings.follow_smoothing
	rotate_speed = settings.mouse_speed
	invert_vertical = settings.invert_y
	collision_radius = settings.collision_radius
	follow_offset.y = settings.eye_height if settings.view == 1 else settings.pivot_height

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if target == null and not target_path.is_empty():
		target = get_node_or_null(target_path)
	arm.collision_mask = world_collision_mask if _profile.is_empty() or (_profile.occlusion and _profile.view != 1) else 0
	arm.margin = 0.06
	_sweep_shape.radius = collision_radius
	arm.shape = _sweep_shape
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.near = 0.08
	if is_instance_valid(target):
		snap_to_target()
	_apply()
	get_window().focus_exited.connect(_on_window_focus_exited)
	if capture_mouse_on_start:
		capture_mouse()
	else:
		release_mouse()

func _exit_tree() -> void:
	if _controls_active and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	_sync_dialogue_controls()
	if not _profile.is_empty(): _profile_stick_look(delta)
	if is_instance_valid(target):
		var want := _follow_position()
		if global_position.distance_to(want) > teleport_snap_distance:
			global_position = want
		else:
			global_position = global_position.lerp(want, 1.0 - exp(-follow_smoothing * delta))
	_update_pose(1.0 - exp(-focus_smoothing * delta))

func _sync_dialogue_controls() -> void:
	var blocked := false
	for dialogue in get_tree().get_nodes_in_group("godot_level_editor_dialogue_player"):
		if dialogue.has_method("blocks_player_input"):
			blocked = blocked or dialogue.blocks_player_input()
		elif dialogue.has_method("is_active"):
			blocked = blocked or dialogue.is_active()
	for performance in get_tree().get_nodes_in_group("godot_level_editor_performance_player"):
		if performance.get_viewport() == get_viewport(): blocked = blocked or performance.blocks_player_input()
	if blocked != _dialogue_visible:
		_dialogue_visible = blocked
		if blocked:
			_restore_after_dialogue = _controls_active
			release_mouse()
			if target is CharacterBody3D:
				target.velocity.x = 0.0
				target.velocity.z = 0.0
		elif _restore_after_dialogue:
			capture_mouse()
			_restore_after_dialogue = false

func _physics_process(_delta: float) -> void:
	if is_instance_valid(_vehicle_target):
		arm.position.x = 0.0
		if _controls_active and not _profile.is_empty() and is_instance_valid(target) and target.profile_input != null and target.profile_input.just("recenter"):
			recenter_behind_target()
		return
	if not _profile.is_empty():
		if _controls_active and is_instance_valid(target) and target.profile_input != null:
			var input: RefCounted = target.profile_input
			_focus_held = _profile.focus and input.active("focus", _profile.focus_input)
			if _profile.view == 0 and _profile.shoulder_swap and input.just("swap"): _shoulder_side *= -1.0
			if _profile.view != 2 and _profile.recenter and input.just("recenter"): recenter_behind_target()
		if arm.collision_mask == 0:
			arm.position.x = _current_shoulder
			return
	# Sweep the shoulder offset too: a clear rear arm alone is insufficient at side walls.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sweep_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.motion = global_basis.x * _current_shoulder
	query.collision_mask = world_collision_mask
	if target is CollisionObject3D:
		query.exclude = [target.get_rid()]
	var fraction := get_world_3d().direct_space_state.cast_motion(query)
	arm.position.x = _current_shoulder * fraction[0]

func _unhandled_input(event: InputEvent) -> void:
	if not camera.is_current():
		return
	_sync_dialogue_controls()
	if _dialogue_visible:
		return
	if event.is_action_pressed("ui_cancel"):
		release_mouse()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if not _controls_active:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				capture_mouse()
				get_viewport().set_input_as_handled()
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				if _profile.is_empty() and not is_instance_valid(_vehicle_target): _focus_held = event.pressed
			MOUSE_BUTTON_MIDDLE:
				if _profile.is_empty() and event.pressed: recenter_behind_target()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed and (_profile.is_empty() or _profile.view == 0):
					var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
					distance = clampf(distance + direction * zoom_step, min_distance, max_distance)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _controls_active and (is_instance_valid(_vehicle_target) or _profile.is_empty() or (_profile.look and _profile.view != 2)):
		var motion: Vector2 = event.screen_relative
		yaw_degrees = fposmod(yaw_degrees - motion.x * rotate_speed, 360.0)
		var vertical := -1.0 if invert_vertical else 1.0
		pitch_degrees = clampf(pitch_degrees + motion.y * rotate_speed * vertical, min_pitch, max_pitch)
		get_viewport().set_input_as_handled()
	elif _profile.is_empty() and not is_instance_valid(_vehicle_target) and _controls_active and event.is_action_pressed("camera_swap_shoulder"):
		_shoulder_side *= -1.0
		get_viewport().set_input_as_handled()

func capture_mouse() -> void:
	_controls_active = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	_controls_active = false
	_focus_held = false
	if not _profile.is_empty() and is_instance_valid(target) and target.profile_input != null:
		target.profile_input.toggles.erase("focus")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_window_focus_exited() -> void:
	_restore_after_dialogue = false
	release_mouse()

func is_gameplay_input_enabled() -> bool:
	_sync_dialogue_controls()
	return _controls_active

func snap_to_target() -> void:
	if is_instance_valid(target):
		global_position = _follow_position()

func set_vehicle_target(vehicle: Node3D) -> void:
	if _vehicle_rid.is_valid(): arm.remove_excluded_object(_vehicle_rid)
	if is_instance_valid(vehicle):
		_walking_angles = Vector2(yaw_degrees, pitch_degrees)
		_vehicle_rid = vehicle.get_rid()
		arm.add_excluded_object(_vehicle_rid)
		arm.collision_mask = world_collision_mask
	else:
		_vehicle_rid = RID()
		yaw_degrees = _walking_angles.x
		pitch_degrees = _walking_angles.y
		arm.collision_mask = world_collision_mask if _profile.is_empty() or (_profile.occlusion and _profile.view != 1) else 0
	_vehicle_target = vehicle
	_focus_held = false
	if is_instance_valid(vehicle): recenter_behind_target()

func _follow_position() -> Vector3:
	if is_instance_valid(_vehicle_target):
		return _vehicle_target.global_position + Vector3.UP * float(_vehicle_target.camera_height)
	return target.global_position + follow_offset

func recenter_behind_target() -> void:
	if is_instance_valid(_vehicle_target):
		yaw_degrees = rad_to_deg(_vehicle_target.global_rotation.y)
		pitch_degrees = 12.0
		return
	if not is_instance_valid(target): return
	var model := target.get_node_or_null("ModelRoot") as Node3D
	if model != null:
		var model_offset := float(target.get("model_yaw_offset_degrees")) if "model_yaw_offset_degrees" in target else 0.0
		yaw_degrees = fposmod(rad_to_deg(model.global_rotation.y) - 180.0 - model_offset, 360.0)
	pitch_degrees = 10.0 if _profile.is_empty() else _profile.pitch

## Kept for existing inspection/capture tools; gameplay transitions use smoothing.
func _apply() -> void:
	_update_pose(1.0)
	arm.position.x = _current_shoulder

func _update_pose(weight: float) -> void:
	rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	arm.rotation_degrees = Vector3(-pitch_degrees, 0.0, 0.0)
	var desired_distance := minf(distance, focus_distance) if _focus_held else distance
	if is_instance_valid(_vehicle_target):
		desired_distance = _vehicle_target.camera_distance
	elif not _profile.is_empty() and _profile.view == 1:
		desired_distance = 0.0
	_current_distance = lerpf(_current_distance, desired_distance, weight)
	var desired_shoulder := 0.0 if is_instance_valid(_vehicle_target) else (focus_shoulder_offset if _focus_held else shoulder_offset) * _shoulder_side
	_current_shoulder = lerpf(_current_shoulder, desired_shoulder, weight)
	arm.spring_length = _current_distance
	camera.fov = lerpf(camera.fov, focus_field_of_view if _focus_held else field_of_view, weight)

## Existing player movement continues to use a horizontal camera-relative basis.
func get_yaw_radians() -> float:
	return deg_to_rad(yaw_degrees)

func _profile_stick_look(delta: float) -> void:
	if not _controls_active or not camera.is_current(): return
	if not is_instance_valid(_vehicle_target) and (not _profile.look or _profile.view == 2): return
	var pads := Input.get_connected_joypads()
	if pads.is_empty(): return
	var stick := Vector2(Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X), Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y)).limit_length()
	var magnitude := stick.length()
	if magnitude <= float(_profile.look_deadzone): return
	var motion := stick.normalized() * ((magnitude - float(_profile.look_deadzone)) / (1.0 - float(_profile.look_deadzone))) * float(_profile.stick_speed) * delta
	yaw_degrees = fposmod(yaw_degrees - motion.x, 360.0)
	pitch_degrees = clampf(pitch_degrees + motion.y * (-1.0 if invert_vertical else 1.0), min_pitch, max_pitch)
