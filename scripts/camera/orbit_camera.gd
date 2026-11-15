extends Node3D
## Shared third-person shoulder camera. View state stays outside rewind snapshots.

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if target == null and not target_path.is_empty():
		target = get_node_or_null(target_path)
	arm.collision_mask = world_collision_mask
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
	var dialogue := get_tree().get_first_node_in_group("godot_level_editor_dialogue_player")
	var dialogue_active: bool = dialogue != null and dialogue.has_method("is_active") and dialogue.is_active()
	if dialogue_active != _dialogue_visible:
		_dialogue_visible = dialogue_active
		if dialogue_active:
			_restore_after_dialogue = _controls_active
			release_mouse()
		elif _restore_after_dialogue:
			capture_mouse()
			_restore_after_dialogue = false
	if is_instance_valid(target):
		var want := target.global_position + follow_offset
		if global_position.distance_to(want) > teleport_snap_distance:
			global_position = want
		else:
			global_position = global_position.lerp(want, 1.0 - exp(-follow_smoothing * delta))
	_update_pose(1.0 - exp(-focus_smoothing * delta))

func _physics_process(_delta: float) -> void:
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
				_focus_held = event.pressed
			MOUSE_BUTTON_MIDDLE:
				if event.pressed: recenter_behind_target()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
					distance = clampf(distance + direction * zoom_step, min_distance, max_distance)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _controls_active:
		var motion: Vector2 = event.screen_relative
		yaw_degrees = fposmod(yaw_degrees - motion.x * rotate_speed, 360.0)
		var vertical := -1.0 if invert_vertical else 1.0
		pitch_degrees = clampf(pitch_degrees + motion.y * rotate_speed * vertical, min_pitch, max_pitch)
		get_viewport().set_input_as_handled()
	elif _controls_active and event.is_action_pressed("camera_swap_shoulder"):
		_shoulder_side *= -1.0
		get_viewport().set_input_as_handled()

func capture_mouse() -> void:
	_controls_active = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	_controls_active = false
	_focus_held = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_window_focus_exited() -> void:
	_restore_after_dialogue = false
	release_mouse()

func is_gameplay_input_enabled() -> bool:
	return _controls_active

func snap_to_target() -> void:
	if is_instance_valid(target):
		global_position = target.global_position + follow_offset

func recenter_behind_target() -> void:
	if not is_instance_valid(target): return
	var model := target.get_node_or_null("ModelRoot") as Node3D
	if model != null:
		var model_offset := float(target.get("model_yaw_offset_degrees")) if "model_yaw_offset_degrees" in target else 0.0
		yaw_degrees = fposmod(rad_to_deg(model.global_rotation.y) - 180.0 - model_offset, 360.0)
	pitch_degrees = 10.0

## Kept for existing inspection/capture tools; gameplay transitions use smoothing.
func _apply() -> void:
	_update_pose(1.0)
	arm.position.x = _current_shoulder

func _update_pose(weight: float) -> void:
	rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	arm.rotation_degrees = Vector3(-pitch_degrees, 0.0, 0.0)
	var desired_distance := minf(distance, focus_distance) if _focus_held else distance
	_current_distance = lerpf(_current_distance, desired_distance, weight)
	var desired_shoulder := (focus_shoulder_offset if _focus_held else shoulder_offset) * _shoulder_side
	_current_shoulder = lerpf(_current_shoulder, desired_shoulder, weight)
	arm.spring_length = _current_distance
	camera.fov = lerpf(camera.fov, focus_field_of_view if _focus_held else field_of_view, weight)

## Existing player movement continues to use a horizontal camera-relative basis.
func get_yaw_radians() -> float:
	return deg_to_rad(yaw_degrees)
