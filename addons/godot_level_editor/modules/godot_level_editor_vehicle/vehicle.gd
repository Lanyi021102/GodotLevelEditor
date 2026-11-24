@tool
extends CharacterBody3D
## The scene is the preset. Each placed instance owns its movement and rider state.

signal mounted(actor: CharacterBody3D)
signal dismounted(actor: CharacterBody3D)
enum Drive { CAR, MOTORCYCLE, HOVER }
enum Ride { EMPTY, BOARDING, DRIVING, EXITING }

const FALLBACK := preload("res://addons/godot_level_editor/modules/godot_level_editor_vehicle/vehicle_model.gd")
const HINT := preload("res://addons/godot_level_editor/scripts/ui/interaction_label.gd")
const EXIT_SPEED := 0.45

@export var display_name := "载具"
@export var available := true
@export_group("驾驶")
@export_enum("汽车", "摩托车", "悬停飞行器") var drive_mode: int = Drive.CAR:
	set(value):
		drive_mode = value
		_refresh_preview()
@export_range(0.5, 80.0, 0.1, "suffix:m/s") var top_speed := 8.0
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var reverse_speed := 3.0
@export_range(0.5, 40.0, 0.1, "suffix:m/s²") var acceleration := 5.0
@export_range(0.5, 40.0, 0.1, "suffix:m/s²") var braking := 9.0
@export_range(15.0, 240.0, 1.0, "suffix:°/s") var turn_rate := 100.0
## 仅用于悬停飞行器。
@export_range(0.5, 30.0, 0.1, "suffix:m/s") var lift_speed := 4.0

@export_group("外观与碰撞")
## 支持导入的 GLB、GLTF 或 Godot 三维场景。留空时使用对应白盒模型。
@export var model_scene: PackedScene:
	set(value):
		model_scene = value
		_refresh_preview()
@export var model_offset := Vector3.ZERO:
	set(value):
		model_offset = value
		_refresh_preview()
@export_range(-180.0, 180.0, 1.0, "suffix:°") var model_yaw := 0.0:
	set(value):
		model_yaw = value
		_refresh_preview()
@export_range(0.01, 20.0, 0.01) var model_scale := 1.0:
	set(value):
		model_scale = value
		_refresh_preview()
@export var body_size := Vector3(1.4, 0.7, 2.6):
	set(value):
		body_size = value.abs().max(Vector3.ONE * 0.05)
		_refresh_preview()
@export var body_center := Vector3(0, 0.36, 0):
	set(value):
		body_center = value
		_refresh_preview()

@export_group("上下车")
## 相对于车身原点的站位。
@export var boarding_point := Vector3(-1.08, 0, 0):
	set(value):
		boarding_point = value
		_refresh_preview()
## 驾驶时角色模型的原点。默认坐姿的脚部靠近此点。
@export var seat_point := Vector3(0, 0.26, 0.22):
	set(value):
		seat_point = value
		_refresh_preview()
@export var exit_left := Vector3(-1.15, 0, 0):
	set(value):
		exit_left = value
		_refresh_preview()
@export var exit_right := Vector3(1.15, 0, 0):
	set(value):
		exit_right = value
		_refresh_preview()
@export_range(0.5, 5.0, 0.1, "suffix:m") var board_distance := 1.25
## 留空可使用当前角色模型里的默认载具动作。可填写 AnimationPlayer 中的片段名（含库名前缀）。
@export var board_animation := ""
@export var seated_animation := ""
@export var exit_animation := ""

@export_group("驾驶镜头")
@export_range(2.0, 20.0, 0.1, "suffix:m") var camera_distance := 5.0
@export_range(0.3, 8.0, 0.1, "suffix:m") var camera_height := 1.25

var rider: CharacterBody3D
var ride_state := Ride.EMPTY
var _speed := 0.0
var _stage_time := 0.0
var _stage_length := 0.0
var _stage_from := Vector3.ZERO
var _stage_to := Vector3.ZERO
var _motion: Node3D
var _shape: CollisionShape3D
var _preview_queued := false
var _hint: Label3D
var _blocked_time := 0.0

func _ready() -> void:
	_motion = Node3D.new()
	_motion.name = "VehicleVisual"
	add_child(_motion)
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	_rebuild_preview()
	if Engine.is_editor_hint(): return
	# World collision layer also makes the chassis solid to walking players.
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.3
	floor_constant_speed = true
	add_to_group("godot_level_editor_interactable")
	_hint = HINT.new()
	add_child(_hint)
	_hint.position.y = maxf(1.35, body_center.y + body_size.y * 0.65)
	_hint.configure(self, display_name, "上车", true)

func _exit_tree() -> void:
	if is_instance_valid(rider) and not rider.is_queued_for_deletion():
		rider.detach_vehicle(self)

func _refresh_preview() -> void:
	if not is_node_ready() or _preview_queued: return
	_preview_queued = true
	_rebuild_preview.call_deferred()

func _rebuild_preview() -> void:
	_preview_queued = false
	if not is_instance_valid(_motion): return
	for old in _motion.get_children():
		_motion.remove_child(old)
		old.queue_free()
	var model: Node3D
	if model_scene != null and (scene_file_path.is_empty() or model_scene.resource_path != scene_file_path):
		var instance := model_scene.instantiate()
		if instance is Node3D and instance.get_script() != get_script():
			model = instance
		else:
			instance.free()
	if model == null:
		model = FALLBACK.build(drive_mode, body_size)
	else:
		_make_model_visual_only(model)
	var alignment := Node3D.new()
	alignment.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(model_yaw)).scaled(Vector3.ONE * model_scale), model_offset)
	alignment.add_child(model)
	_motion.add_child(alignment)
	_shape.shape.size = body_size
	_shape.position = body_center
	if Engine.is_editor_hint(): update_gizmos()

func _make_model_visual_only(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is Camera3D: node.current = false
	if node is AudioStreamPlayer3D: node.autoplay = false
	for child in node.get_children():
		_make_model_visual_only(child)

func interaction_position() -> Vector3:
	return to_global(boarding_point)

func can_interact(actor: Node3D) -> bool:
	if not available or ride_state != Ride.EMPTY or not actor is CharacterBody3D or not actor.has_method("can_drive_vehicle") or not actor.can_drive_vehicle(): return false
	return actor.global_position.distance_to(interaction_position()) <= board_distance and absf(velocity.y) < EXIT_SPEED

func interact(actor: Node3D) -> bool:
	if not can_interact(actor): return false
	var ground := _floor_at(interaction_position(), 0.6)
	if ground.is_empty(): return false
	var entry: Vector3 = ground.position + Vector3.UP * 0.035
	if not _standing_room(actor, entry) or not _clear_route(actor, actor.global_position, entry) or not _clear_route(actor, entry, to_global(seat_point)):
		return false
	if not actor.attach_vehicle(self): return false
	rider = actor
	ride_state = Ride.BOARDING
	_stage_from = to_local(actor.global_position)
	_stage_to = seat_point
	_stage_time = 0.0
	_stage_length = rider.play_vehicle_animation(board_animation, "vehicle_board")
	rider.interaction_target = self
	_hint.action_hint = "上车中"
	return true

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_instance_valid(rider): return
	motion_mode = MOTION_MODE_GROUNDED
	velocity = Vector3(0, minf(velocity.y, 0.0) - 18.0 * delta, 0)
	move_and_slide()

func tick_rider(delta: float, stick: Vector2, lift: float, use_interact: bool) -> void:
	if not is_instance_valid(rider): return
	match ride_state:
		Ride.BOARDING, Ride.EXITING:
			_stage_time = minf(_stage_time + delta, _stage_length)
			var weight := smoothstep(0.0, 1.0, _stage_time / _stage_length)
			_position_rider(_stage_from.lerp(_stage_to, weight))
			if _stage_time >= _stage_length: _finish_transition()
		Ride.DRIVING:
			if use_interact and _try_dismount(): return
			_drive(delta, stick, lift)
			_position_rider(seat_point)
			_blocked_time = maxf(_blocked_time - delta, 0.0)
			if _blocked_time <= 0.0: _hint.action_hint = "下车" if _is_stopped() else "停车后下车"

func _drive(delta: float, stick: Vector2, lift: float) -> void:
	var flying := drive_mode == Drive.HOVER
	var wanted := -stick.y * (top_speed if stick.y <= 0.0 else reverse_speed)
	var rate := braking if absf(wanted) < absf(_speed) or wanted * _speed < 0.0 else acceleration
	_speed = move_toward(_speed, wanted, rate * delta)
	if flying or absf(_speed) > 0.08:
		var direction := -1.0 if not flying and _speed < 0.0 else 1.0
		var before := rotation.y
		rotate_y(-stick.x * deg_to_rad(turn_rate) * delta * direction)
		# Rotating in place can overlap a side wall even when translation is clear.
		if test_move(global_transform, Vector3.ZERO): rotation.y = before
	var travel := -global_basis.z.normalized() * _speed
	if flying:
		motion_mode = MOTION_MODE_FLOATING
		travel.y = move_toward(velocity.y, lift * lift_speed, acceleration * delta)
	else:
		motion_mode = MOTION_MODE_GROUNDED
		travel.y = minf(velocity.y, 0.0) - 18.0 * delta
	velocity = travel
	move_and_slide()
	var planar := Vector2(travel.x, travel.z)
	if planar.length() > 0.1 and Vector2(get_real_velocity().x, get_real_velocity().z).dot(planar.normalized()) < planar.length() * 0.25:
		_speed = 0.0
	var lean := 0.0
	if drive_mode != Drive.CAR:
		lean = -stick.x * deg_to_rad(14.0) * minf(absf(_speed) / 3.0, 1.0)
	_motion.rotation.z = lerpf(_motion.rotation.z, lean, minf(1.0, 8.0 * delta))

func _is_stopped() -> bool:
	return absf(_speed) < EXIT_SPEED and get_real_velocity().length() < EXIT_SPEED

func _try_dismount() -> bool:
	if not _is_stopped():
		_feedback("停车后下车")
		return false
	var floor := _floor_at(global_position, 0.4)
	if floor.is_empty():
		_feedback("请先降落" if drive_mode == Drive.HOVER else "请在地面停车")
		return false
	for offset in [exit_left, exit_right]:
		var ground := _floor_at(to_global(offset), 0.65)
		if ground.is_empty(): continue
		var candidate: Vector3 = ground.position + Vector3.UP * 0.035
		if not _standing_room(rider, candidate) or not _clear_route(rider, rider.global_position, candidate): continue
		_motion.rotation.z = 0.0
		_stage_from = seat_point
		_stage_to = to_local(candidate)
		_stage_time = 0.0
		_stage_length = rider.play_vehicle_animation(exit_animation, "vehicle_exit")
		ride_state = Ride.EXITING
		_hint.action_hint = "下车中"
		return true
	_feedback("周围没有下车空间")
	return false

func _floor_at(point: Vector3, depth: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.45, point - Vector3.UP * depth, 1, _excluded_rids(rider))
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit if not hit.is_empty() and hit.normal.dot(Vector3.UP) >= 0.65 else {}

func _excluded_rids(actor: CharacterBody3D) -> Array[RID]:
	var exclusions: Array[RID] = [get_rid()]
	if is_instance_valid(actor): exclusions.append(actor.get_rid())
	return exclusions

func _standing_room(actor: CharacterBody3D, point: Vector3) -> bool:
	var collision: CollisionShape3D = actor.vehicle_collision_shape()
	if collision == null or collision.shape == null: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = Transform3D(collision.global_basis, point + collision.global_position - actor.global_position + Vector3.UP * 0.025)
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _clear_route(actor: CharacterBody3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.75, to + Vector3.UP * 0.75, 1, _excluded_rids(actor))
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _position_rider(offset: Vector3) -> void:
	rider.global_position = _motion.to_global(offset)
	rider.face_vehicle(global_rotation.y, _motion.rotation.z)

func _finish_transition() -> void:
	if ride_state == Ride.BOARDING:
		ride_state = Ride.DRIVING
		rider.play_vehicle_animation(seated_animation, "vehicle_seated")
		_hint.action_hint = "下车"
		mounted.emit(rider)
	else:
		var actor := rider
		# A moving prop may have blocked the intended standing pose during the animation.
		if not _standing_room(actor, actor.global_position):
			ride_state = Ride.DRIVING
			_position_rider(seat_point)
			actor.play_vehicle_animation(seated_animation, "vehicle_seated")
			_feedback("周围没有下车空间")
			return
		release_rider(actor)
		actor.detach_vehicle(self)
		dismounted.emit(actor)

func _feedback(message: String) -> void:
	_hint.action_hint = message
	_blocked_time = 1.1

func release_rider(actor: CharacterBody3D) -> void:
	if rider != actor: return
	rider = null
	ride_state = Ride.EMPTY
	_speed = 0.0
	velocity = Vector3.ZERO
	_motion.rotation.z = 0.0
	_hint.action_hint = "上车"
