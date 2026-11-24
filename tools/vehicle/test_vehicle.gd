extends SceneTree

const TEMPLATE := preload("res://addons/godot_level_editor/templates/empty_level.tscn")
const PLAYER_PRESET := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/preset.gd")
const VEHICLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_vehicle/vehicle.gd")
const KART := preload("res://addons/godot_level_editor/scenes/vehicles/kart.tscn")
const MOTORCYCLE := preload("res://addons/godot_level_editor/scenes/vehicles/motorcycle.tscn")
const SPEEDER := preload("res://addons/godot_level_editor/scenes/vehicles/hover_speeder.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	checks += 1
	failures += int(not condition)
	print("[PASS] " if condition else "[FAIL] ", description)

func _frames(count: int) -> void:
	for frame in count: await physics_frame

func _hold(name: StringName, count: int) -> void:
	Input.action_press(name)
	await _frames(count)
	Input.action_release(name)
	await _frames(2)

func _block(world: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = at
	return body

func _place_vehicle(world: Node3D, packed: PackedScene, at: Vector3) -> VEHICLE:
	var vehicle := packed.instantiate() as VEHICLE
	vehicle.position = at
	world.add_child(vehicle)
	return vehicle

func _run() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	var world := TEMPLATE.instantiate() as Node3D
	var profile := PLAYER_PRESET.new()
	profile.values = {"view": 1, "drive_vehicles": true}
	world.player_preset = profile
	for part in ["topology", "events", "level_logic"]:
		world.get(part).graph_id = "test_vehicle_" + part
	var kart := _place_vehicle(world, KART, Vector3(-4, 0, 2))
	var bike := _place_vehicle(world, MOTORCYCLE, Vector3(0, 0, 2))
	var speeder := _place_vehicle(world, SPEEDER, Vector3(4, 0, 2))
	root.add_child(world)
	current_scene = world
	await _frames(24)
	var session := world.get_node("PlaySession")
	var player := session.get_node("Player") as CharacterBody3D
	var actions: Dictionary = player.profile_input.actions
	var camera: Node3D = session.camera_rig
	var counter := {"mount": 0, "exit": 0}
	kart.mounted.connect(func(_actor: CharacterBody3D): counter.mount += 1)
	kart.dismounted.connect(func(_actor: CharacterBody3D): counter.exit += 1)
	camera.capture_mouse()
	_check(is_instance_valid(kart.model_scene) and is_instance_valid(bike.model_scene) and is_instance_valid(speeder.model_scene), "all three presets load their source models")
	player.global_position = kart.interaction_position()
	await _frames(4)
	await _hold(actions.interact, 3)
	_check(kart.ride_state == VEHICLE.Ride.BOARDING and player.collision_layer == 0 and camera._vehicle_target == kart, "native player interaction starts boarding, transfers camera and releases walking collision")
	await _frames(80)
	_check(kart.ride_state == VEHICLE.Ride.DRIVING and counter.mount == 1 and player.get_node("ModelRoot").current_clip().contains("Sitting_Idle"), "boarding ends once in the source seated animation")
	if failures > 0:
		var animation: AnimationPlayer = player.get_node("ModelRoot").anim
		print("BOARD DIAGNOSTIC state=", kart.ride_state, " signal=", counter, " clip=", animation.current_animation, " available=", animation.get_animation_list())
	var start := kart.position
	await _hold(actions.forward, 40)
	_check(kart.position.z < start.z - 0.5 and player.global_position.distance_to(kart.to_global(kart.seat_point)) < 0.08, "car drives forward and rider follows the seat")
	var before_turn := kart.rotation.y
	Input.action_press(actions.forward)
	await _hold(actions.right, 14)
	Input.action_release(actions.forward)
	_check(absf(kart.rotation.y - before_turn) > 0.12, "car can steer while moving on the ground")
	await _frames(60)
	var wall := _block(world, kart.to_global(kart.exit_left) + Vector3.UP, Vector3(0.44, 2.5, 1.8))
	await _frames(3)
	await _hold(actions.interact, 2)
	await _frames(80)
	_check(kart.ride_state == VEHICLE.Ride.EMPTY and counter.exit == 1 and kart.to_local(player.global_position).x > 0.75 and player.collision_layer == 2 and camera._vehicle_target == null, "blocked left exit uses right exit and restores walking controls and camera")
	_check(not player.get_node("ModelRoot").visible and camera.arm.spring_length < 0.15, "dismount restores the original first-person view")
	wall.queue_free()

	player.global_position = bike.interaction_position()
	player.player_config.drive_vehicles = false
	await _frames(4)
	_check(not bike.can_interact(player), "a player preset can disable driving")
	player.player_config.drive_vehicles = true
	await _hold(actions.interact, 2)
	await _frames(72)
	var start_bike := bike.position
	Input.action_press(actions.forward)
	await _hold(actions.right, 24)
	Input.action_release(actions.forward)
	_check(bike.rider == player and bike.position.distance_to(start_bike) > 0.27 and absf(bike._motion.rotation.z) > 0.03, "motorcycle moves and leans in a turn")
	player.reset_to_spawn()
	_check(bike.rider == null and camera._vehicle_target == null, "player reset clears rider and camera ownership")

	player.global_position = speeder.interaction_position()
	await _frames(4)
	await _hold(actions.interact, 2)
	await _frames(72)
	var ground_y := speeder.global_position.y
	await _hold(actions.jump, 38)
	await _frames(32)
	_check(speeder.rider == player and speeder.global_position.y > ground_y + 1.1, "the speeder takes off and hovers without holding a key")
	await _hold(actions.interact, 2)
	_check(speeder.ride_state == VEHICLE.Ride.DRIVING and speeder._hint.action_hint == "请先降落", "an airborne player cannot dismount")
	await _hold(actions.crouch, 65)
	await _frames(18)
	await _hold(actions.interact, 2)
	await _frames(80)
	_check(speeder.rider == null and absf(player.global_position.y) < 0.25, "speeder descends, lands and releases the player at ground level")
	print("VEHICLE CHECKS: %d, FAILURES: %d" % [checks, failures])
	quit(int(failures > 0))
