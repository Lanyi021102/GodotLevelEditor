extends SceneTree

const PRESET := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/preset.gd")
const TEMPLATE := preload("res://addons/godot_level_editor/templates/empty_level.tscn")
const CLIMB := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/climb_zone.tscn")
const MAP := "res://content/scenes/levels/player_preset_test.tscn"
var count := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(result: bool, label: String) -> void:
	count += 1
	failures += int(not result)
	print("[PASS] " if result else "[FAIL] ", label)

func frames(n: int) -> void:
	for i in n: await physics_frame
	await process_frame

func _box(world: Node, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body, true)
	body.position = position
	body.owner = world
	collider.owner = world

func _map_with(profile: Resource) -> void:
	var world := TEMPLATE.instantiate()
	world.player_preset = profile
	world.level_id = "3c_test"
	world.world_id = "player_preset_test"
	for key in ["topology", "events", "level_logic"]:
		world.get(key).graph_id = "player_preset_test_" + key
	_box(world, Vector3(-4, 0.10, 1), Vector3(2, 0.2, 2))
	_box(world, Vector3(0, 0.35, 0), Vector3(2, 0.7, 0.35))
	_box(world, Vector3(4, 0.55, 0), Vector3(2, 1.1, 2))
	_box(world, Vector3(-4, 1.40, 5), Vector3(2, 0.15, 2))
	var zone := CLIMB.instantiate() as Area3D
	zone.position = Vector3(7, 0, 3)
	world.add_child(zone)
	zone.owner = world
	var packed := PackedScene.new()
	assert(packed.pack(world) == OK and ResourceSaver.save(packed, MAP) == OK)
	world.free()

func _make_profile(suffix: String, values: Dictionary) -> Resource:
	var profile := PRESET.new()
	profile.display_name = suffix
	profile.values = values
	var path := "res://content/resources/test_3c_" + suffix + ".tres"
	assert(ResourceSaver.save(profile, path) == OK)
	return ResourceLoader.load(path)

func _ready_player() -> CharacterBody3D:
	assert(change_scene_to_packed(ResourceLoader.load(MAP, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)) == OK)
	await frames(16)
	var session := current_scene.get_node_or_null("PlaySession")
	assert(session != null)
	session.camera_rig.capture_mouse()
	return session.get_node("Player")

func _press(actor: CharacterBody3D, id: String, duration := 1) -> void:
	var action: StringName = actor.profile_input.actions[id]
	Input.action_press(action)
	await frames(duration)
	Input.action_release(action)

func _position(actor: CharacterBody3D, point: Vector3) -> void:
	actor.traversal.reset()
	actor.global_position = point
	actor.velocity = Vector3.ZERO
	actor.get_node("ModelRoot").global_rotation.y = PI
	await frames(6)

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	var limited := _make_profile("limited", {"jump": false, "run": false, "interact": false, "distance": 4.8, "fov": 75.0})
	_map_with(limited)
	var actor := await _ready_player()
	var runner := actor.get_parent()
	var start := actor.position
	var previous_action: StringName = actor.profile_input.actions.jump
	await _press(actor, "jump", 3)
	check(actor.is_on_floor() and absf(actor.position.y - start.y) < 0.05, "disabled jump ignores the input")
	check(not actor.interact_nearest(), "disabled interaction is also gated through the legacy player method")
	check(runner.camera_rig.distance == 4.8 and is_equal_approx(runner.camera_rig.camera.fov, 75.0), "standalone play loads camera parameters from the bound resource")
	Input.action_press(actor.profile_input.actions.run)
	await _press(actor, "forward", 24)
	Input.action_release(actor.profile_input.actions.run)
	check(Vector2(actor.velocity.x, actor.velocity.z).length() < 2.0, "disabled run leaves walk speed")
	check(actor._anim.has_animation("moves/Roll") and actor._anim.has_animation("moves/Sprint") and actor._anim.has_animation("moves/Interact"), "Quaternius source clips bind to the default skeleton")
	check(actor._anim.has_animation("moves/Vault") and actor._anim.has_animation("moves/Mantle"), "the whitebox vault and mantle clips are available")
	check(actor._anim.get_animation("moves/Climb").resource_name == "CMU Ladder Climb" and actor._anim.get_animation("moves/StepOver").resource_name == "CMU Step Over", "both downloaded motion captures are in the default character library")

	var expanded := _make_profile("expanded", {"walk_speed": 3.0, "jump_height": 1.2, "jump_buffer": false, "coyote": false, "extra_jump": true, "crouch": true, "vault": true, "mantle": true, "step": true, "dodge": true, "climb": true, "view": 1, "fov": 58.0})
	expanded.animation_scene = preload("res://addons/godot_level_editor/assets/characters/quaternius_base/UAL1_Standard.glb")
	expanded.clip_overrides["walk"] = "imported/Walk"
	expanded.clip_overrides["step"] = "moves/StepOver"
	assert(ResourceSaver.save(expanded) == OK)
	_map_with(expanded)
	actor = await _ready_player()
	runner = actor.get_parent()
	check(not InputMap.has_action(previous_action), "old per-player input actions are released")
	check(actor.walk_speed == 3.0 and actor.player_preset.resource_path.ends_with("test_3c_expanded.tres"), "same scene reloaded with the other external preset")
	check(actor._anim.has_animation("imported/Walk") and not actor._anim.has_animation("imported/Idle"), "only bound clips from the compatible external pack are retargeted at runtime")
	check(runner.camera_rig.arm.spring_length == 0.0 and is_equal_approx(runner.camera_rig.camera.fov, 58.0) and not actor.get_node("ModelRoot").visible, "first person applies eye mode, FOV, and clears the body from view")
	start = actor.position
	await _press(actor, "jump", 4)
	check(actor.position.y > start.y + 0.2, "enabled jump works even with both input assists off")
	await frames(5)
	await _press(actor, "jump", 1)
	check(actor._extra_jump_used and actor.velocity.y > 1.0, "double jump consumes one extra jump in the air")
	await frames(65)

	await _position(actor, Vector3(-4, 0.05, 6.2))
	Input.action_press(actor.profile_input.actions.crouch)
	await _press(actor, "forward", 56)
	check(actor.is_crouching() and is_equal_approx(actor.traversal.capsule.height, 1.2), "crouch lowers the capsule and physically enters a low ceiling")
	Input.action_release(actor.profile_input.actions.crouch)
	await frames(4)
	check(actor.is_crouching(), "ceiling blocks standing")
	await _press(actor, "back", 60)
	await frames(12)
	check(not actor.is_crouching(), "standing resumes in clear space")

	await _position(actor, Vector3(-4, 0.05, 2.5))
	await _press(actor, "forward", 30)
	check(actor.position.y > 0.14 and actor.is_on_floor(), "auto step moves onto low solid geometry")
	check(actor._anim.current_animation == "moves/StepOver", "auto step plays the assigned CMU clip")
	await _position(actor, Vector3(0, 0.05, 0.56))
	await _press(actor, "traverse")
	check(actor.traversal.action == "vault" and actor._anim.current_animation == "moves/Vault", "thin obstacle triggers vault and plays its clip")
	await frames(33)
	check(actor.position.z < -0.4 and actor.is_on_floor(), "vault finishes on the opposite side")
	await _position(actor, Vector3(4, 0.05, 1.45))
	await _press(actor, "traverse")
	check(actor.traversal.action == "mantle" and actor._anim.current_animation == "moves/Mantle", "platform triggers mantle and plays its clip")
	await frames(46)
	check(actor.position.y > 1.0 and actor.is_on_floor(), "mantle lands on the top")

	await _position(actor, Vector3(7, 0.05, 3.0))
	await _press(actor, "climb")
	await _press(actor, "forward", 35)
	check(actor.traversal.action == "climb" and actor.position.y > 0.65 and actor._anim.current_animation == "moves/Climb", "climb area accepts vertical input with its own animation")
	var skeleton := actor.get_node("ModelRoot").model.get_node("Body/Armature/Skeleton3D") as Skeleton3D
	var arm := skeleton.find_bone("upperarm_l")
	check(skeleton.get_bone_pose_rotation(arm).angle_to(skeleton.get_bone_rest(arm).basis.get_rotation_quaternion()) > 0.15, "the downloaded ladder motion actually drives the player skeleton")
	await _press(actor, "climb")
	await frames(50)
	check(actor.traversal.action.is_empty() and actor.is_on_floor(), "exiting climb restores gravity")
	await _position(actor, Vector3(7, 0.05, 6))
	await _press(actor, "dodge")
	check(actor.traversal.action == "dodge" and actor._anim.current_animation == "moves/Roll", "dodge runs the roll clip")
	await frames(41)
	check(actor.position.z < 4.3, "dodge moves the physical body")

	print("PLAYER 3C: %d checks, %d failures" % [count, failures])
	quit(1 if failures else 0)
