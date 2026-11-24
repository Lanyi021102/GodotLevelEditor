extends RefCounted
## Kinematic actions consume the same collision capsule as regular movement.
const CLIMB_GROUP: StringName = &"godot_level_editor_climbable"
const MAX_REACH := 0.9
var actor: CharacterBody3D
var config: Dictionary
var capsule: CapsuleShape3D
var collision: CollisionShape3D
var action := ""
var duration := 0.0
var _climb_zone: Area3D
var _points: Array[Vector3] = []
var _elapsed := 0.0

func setup(body: CharacterBody3D, settings: Dictionary) -> void:
	actor = body
	config = settings
	collision = body.get_node("Collision")
	capsule = collision.shape.duplicate()
	collision.shape = capsule
	_set_height(config.height)
	body.floor_max_angle = deg_to_rad(config.slope)

func reset() -> void:
	action = ""
	_climb_zone = null
	_set_height(config.height)

func crouch(wants_crouch: bool) -> bool:
	if wants_crouch:
		_set_height(config.crouch_height)
	elif capsule.height < config.height and _clear_at(actor.global_position, config.height):
		_set_height(config.height)
	return capsule.height < config.height - 0.001

func cancel() -> void:
	action = ""
	_climb_zone = null
	actor.velocity = Vector3.ZERO

func tick(delta: float, stick: Vector2, direction: Vector3, controls: RefCounted, input_enabled: bool) -> bool:
	if not input_enabled:
		if not action.is_empty(): cancel()
		return false
	if action == "climb":
		if controls.just("climb") or not is_instance_valid(_climb_zone) or not _climb_zone.overlaps_body(actor):
			cancel()
			return false
		var shape := _climb_zone.get_node("CollisionShape3D") as CollisionShape3D
		var box := shape.shape as BoxShape3D
		var current := shape.to_local(actor.global_position)
		var desired := clampf(current.y - stick.y * config.climb_speed * delta, -box.size.y * 0.5, box.size.y * 0.5)
		actor.move_and_collide(shape.global_basis.y.normalized() * ((desired - current.y) * shape.global_basis.y.length()))
		actor.velocity = Vector3.ZERO
		return true
	if not action.is_empty():
		_advance(delta)
		return true
	if config.climb and controls.just("climb") and _begin_climb():
		return true
	if config.dodge and actor.is_on_floor() and controls.just("dodge"):
		var away := direction.normalized() if not direction.is_zero_approx() else _forward()
		actor.call("_face_3c_action", away)
		_begin("dodge", [actor.global_position, actor.global_position + away * config.dodge_distance], config.dodge_time)
		return true
	if (config.vault or config.mantle) and (controls.just("traverse") or (config.mantle and config.auto_mantle and not actor.is_on_floor() and actor.velocity.y <= 0.0 and not direction.is_zero_approx())):
		var ahead := direction.normalized() if not direction.is_zero_approx() else _forward()
		return _begin_traversal(ahead, controls.just("traverse"))
	return false

func step(horizontal: Vector3) -> bool:
	if not config.step or not actor.is_on_floor() or horizontal.length_squared() < 0.00001: return false
	var here := actor.global_transform
	var face := KinematicCollision3D.new()
	if not actor.test_move(here, horizontal, face) or face.get_normal().dot(Vector3.UP) >= cos(actor.floor_max_angle): return false
	var raise := Vector3.UP * float(config.step_height)
	if actor.test_move(here, raise): return false
	var up := here.translated(raise)
	var probe := horizontal.normalized() * (capsule.radius + horizontal.length())
	if actor.test_move(up, probe): return false
	var floor_hit := KinematicCollision3D.new()
	if not actor.test_move(up.translated(probe), -raise - Vector3.UP * 0.06, floor_hit): return false
	if floor_hit.get_normal().dot(Vector3.UP) < cos(actor.floor_max_angle): return false
	var lift := float(config.step_height) + floor_hit.get_travel().y
	if lift <= 0.015: return false
	actor.global_position.y += lift + 0.008
	return true

func _set_height(height: float) -> void:
	if is_equal_approx(capsule.height, height) and is_equal_approx(collision.position.y, height * 0.5) and is_equal_approx(capsule.radius, float(config.radius)): return
	# Expand height before radius and collapse radius before height.
	capsule.radius = minf(capsule.radius, config.radius)
	capsule.height = height
	capsule.radius = config.radius
	collision.position.y = height * 0.5

func _clear_at(feet: Vector3, height: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.height = height
	shape.radius = config.radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform.origin = feet + Vector3.UP * (height * 0.5 + 0.025)
	params.collision_mask = actor.collision_mask
	params.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, actor.collision_mask, [actor.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(query)

func _forward() -> Vector3:
	var visual := actor.get_node("ModelRoot") as Node3D
	return Basis(Vector3.UP, visual.global_rotation.y - deg_to_rad(float(actor.get("model_yaw_offset_degrees")))) * Vector3.BACK

func _begin_climb() -> bool:
	var nearest: Area3D
	var best := INF
	for node in actor.get_tree().get_nodes_in_group(CLIMB_GROUP):
		var area := node as Area3D
		if area == null or not area.overlaps_body(actor): continue
		var shape := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape == null or not shape.shape is BoxShape3D: continue
		var distance := area.global_position.distance_squared_to(actor.global_position)
		if distance < best:
			nearest = area
			best = distance
	if nearest == null: return false
	_climb_zone = nearest
	action = "climb"
	var normal := nearest.global_basis.z
	actor.call("_face_3c_action", -Vector3(normal.x, 0.0, normal.z))
	return true

func _begin_traversal(ahead: Vector3, manual: bool) -> bool:
	var feet := actor.global_position
	var reach := maxf(MAX_REACH, capsule.radius + 0.25)
	var front := feet + Vector3.UP * 0.22
	var wall := _ray(front, front + ahead * reach)
	if wall.is_empty() or Vector3(wall.normal).dot(ahead) > -0.4: return false
	var edge := Vector3(wall.position) + ahead * 0.05
	var top_height := float(config.mantle_height) if config.mantle else float(config.vault_height)
	if config.vault and manual: top_height = maxf(top_height, config.vault_height)
	var top := _ray(Vector3(edge.x, feet.y + top_height + 0.05, edge.z), Vector3(edge.x, feet.y + 0.23, edge.z))
	if top.is_empty() or Vector3(top.normal).y < cos(actor.floor_max_angle): return false
	var height: float = top.position.y - feet.y
	var raised := Vector3(feet.x, top.position.y + 0.04, feet.z)
	if config.vault and manual and actor.is_on_floor() and height <= config.vault_height:
		var far_probe := Vector3(edge.x, raised.y, edge.z) + ahead * (float(config.vault_depth) + capsule.radius + 0.06)
		var landing := _ray(far_probe, far_probe - Vector3.UP * (height + 1.1))
		if not landing.is_empty() and landing.position.y < top.position.y - 0.2 and Vector3(landing.normal).y >= cos(actor.floor_max_angle):
			var far := Vector3(landing.position) + Vector3.UP * 0.04
			if _path_is_clear([feet, raised, far_probe, far]):
				_begin("vault", [feet, raised, far_probe, far], config.vault_time)
				actor.call("_face_3c_action", ahead)
				return true
	if not config.mantle or height > config.mantle_height: return false
	var platform_probe := Vector3(edge.x, raised.y + 0.1, edge.z) + ahead * (capsule.radius + 0.1)
	var platform := _ray(platform_probe, platform_probe - Vector3.UP * 0.22)
	if platform.is_empty() or Vector3(platform.normal).y < cos(actor.floor_max_angle): return false
	var landing_point := Vector3(platform.position) + Vector3.UP * 0.04
	if not _path_is_clear([feet, raised, landing_point]): return false
	_begin("mantle", [feet, raised, landing_point], config.mantle_time)
	actor.call("_face_3c_action", ahead)
	return true

func _path_is_clear(points: Array[Vector3]) -> bool:
	if not _clear_at(points.back(), config.height): return false
	for i in range(1, points.size()):
		var origin := actor.global_transform
		origin.origin = points[i - 1]
		if actor.test_move(origin, points[i] - points[i - 1]): return false
	return true

func _begin(id: String, points: Array[Vector3], action_duration: float) -> void:
	action = id
	_points = points
	_elapsed = 0.0
	duration = action_duration
	actor.velocity = Vector3.ZERO

func _advance(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, duration)
	var progress := (_elapsed / duration) * (_points.size() - 1)
	var segment := mini(int(progress), _points.size() - 2)
	var destination := _points[segment].lerp(_points[segment + 1], progress - segment)
	var hit := actor.move_and_collide(destination - actor.global_position)
	if hit != null or _elapsed >= duration: cancel()
