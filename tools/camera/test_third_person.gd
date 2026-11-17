extends Node
## Camera/locomotion integration; optional Forward+ captures use the real game scenes.
var checks := 0
var failures := 0
var session: Node3D
var capture_dir := ""

class DialogueStub extends Node:
	var active := false
	func is_active() -> bool: return active

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame

func mouse(button: MouseButton, pressed := true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)

func motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.screen_relative = relative
	event.relative = relative
	Input.parse_input_event(event)

func shoulder_key() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	event.pressed = true
	Input.parse_input_event(event)
	var released := event.duplicate()
	released.pressed = false
	Input.parse_input_event(released)

func wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	session.add_child(body)
	return body

func _ready() -> void:
	get_tree().create_timer(90, true).timeout.connect(func(): get_tree().quit(2))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty():
		await capture_scenes()
	else:
		await integration()
	print("THIRD PERSON: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func integration() -> void:
	session = load("res://tools/runtime/session_fixture.tscn").instantiate()
	add_child(session)
	await frames(8)
	var rig: Node3D = session.camera_rig
	var camera: Camera3D = rig.camera
	var player: CharacterBody3D = session.player
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE and camera.near < 0.1, "perspective camera supports near shoulder views")
	check(camera.is_position_in_frustum(player.global_position + Vector3.UP), "player torso is visible in the initial shoulder frame")
	check(camera.global_position.distance_to(player.global_position + Vector3.UP) < 4.5, "camera starts close behind the full-size player")
	check(rig.arm.shape is SphereShape3D and rig.arm.collision_mask == 1, "camera volume checks world geometry")
	motion(Vector2(300, -1000))
	await frames(2)
	check(absf(angle_difference(rig.get_yaw_radians(), deg_to_rad(-48))) < 0.01, "raw mouse motion orbits freely without a drag button")
	check(is_equal_approx(rig.pitch_degrees, rig.min_pitch), "looking up stops at a safe pitch limit")
	motion(Vector2(0, 2000))
	await frames(2)
	check(is_equal_approx(rig.pitch_degrees, rig.max_pitch), "looking down stops at a safe pitch limit")
	rig.yaw_degrees = 90.0
	rig.pitch_degrees = 10.0
	rig._apply()
	var start := player.global_position
	Input.action_press("move_forward")
	await frames(28)
	Input.action_release("move_forward")
	await frames(10)
	check(player.position.x < start.x - 0.5 and absf(player.position.z - start.z) < 0.05, "W follows the rotated camera heading on the ground plane")
	mouse(MOUSE_BUTTON_RIGHT)
	await frames(30)
	check(camera.fov < rig.field_of_view - 10.0 and rig.arm.spring_length < rig.distance - 1.0, "holding right mouse smoothly narrows the lens and moves closer")
	shoulder_key()
	await frames(30)
	check(rig.arm.position.x < -0.5, "V switches the actual camera to the other shoulder")
	mouse(MOUSE_BUTTON_RIGHT, false)
	await frames(30)
	check(absf(camera.fov - rig.field_of_view) < 0.1 and absf(rig.arm.spring_length - rig.distance) < 0.1, "releasing right mouse restores the exploration frame")
	for i in 30: mouse(MOUSE_BUTTON_WHEEL_UP)
	await frames(2)
	check(is_equal_approx(rig.distance, rig.min_distance), "wheel zoom respects the near bound")
	for i in 30: mouse(MOUSE_BUTTON_WHEEL_DOWN)
	await frames(2)
	check(is_equal_approx(rig.distance, rig.max_distance), "wheel zoom respects the far bound")
	player.position = Vector3(0, 0.04, 0)
	player.velocity = Vector3.ZERO
	rig.yaw_degrees = 0.0
	rig.pitch_degrees = 10.0
	rig.distance = 3.8
	rig._shoulder_side = 1.0
	rig.snap_to_target()
	rig._apply()
	var rear := wall(Vector3(0, 2, 2), Vector3(10, 5, 0.3))
	await frames(8)
	check(rig.arm.get_hit_length() < 1.9 and camera.global_position.z < 1.8, "a real wall retracts the camera before it crosses the surface")
	rear.queue_free()
	await frames(8)
	check(rig.arm.get_hit_length() > 3.5, "camera returns to its requested distance when the obstruction clears")
	var side := wall(Vector3(0.42, 2, 0), Vector3(0.1, 5, 12))
	await frames(8)
	check(rig.arm.position.x < 0.25 and camera.global_position.x < 0.25, "side wall sweep keeps the shoulder origin on the player's side of the wall")
	shoulder_key()
	await frames(30)
	check(camera.global_position.x < -0.4, "switching to the clear shoulder works beside a wall")
	side.queue_free()
	await frames(5)
	player.position = Vector3(12, 0.04, 0)
	rig._process(1.0 / 60.0)
	check(rig.global_position.distance_to(player.global_position + rig.follow_offset) < 0.001, "large rewind/reset moves snap the camera pivot to the player")
	await frames(8)
	rig.release_mouse()
	start = player.global_position
	var old_yaw: float = rig.yaw_degrees
	motion(Vector2(500, 0))
	Input.action_press("move_forward")
	Input.action_press("jump")
	await frames(20)
	check(player.global_position.distance_to(start) < 0.05 and rig.yaw_degrees == old_yaw, "released cursor blocks character and look input for HUD use")
	Input.action_release("jump")
	mouse(MOUSE_BUTTON_LEFT)
	await frames(24)
	Input.action_release("move_forward")
	await frames(10)
	check(rig.is_gameplay_input_enabled() and player.global_position.distance_to(start) > 0.4, "clicking the world restores mouse look and movement")
	get_window().focus_exited.emit()
	check(not rig.is_gameplay_input_enabled(), "window focus loss safely releases the controls")
	rig.capture_mouse()
	var dialogue := DialogueStub.new()
	dialogue.add_to_group("godot_level_editor_dialogue_player")
	session.add_child(dialogue)
	dialogue.active = true
	await frames(2)
	mouse(MOUSE_BUTTON_LEFT)
	await frames(2)
	check(not rig.is_gameplay_input_enabled(), "dialogue releases the pointer and menu clicks cannot recapture it")
	dialogue.active = false
	await frames(2)
	check(rig.is_gameplay_input_enabled(), "ending dialogue restores the prior captured-control state")
	dialogue.queue_free()
	session.queue_free()
	await frames(3)

	session = load("res://content/scenes/main.tscn").instantiate()
	session.persist_progress = false
	add_child(session)
	await frames(10)
	check(session.world.runtime_valid and session.camera_rig.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "default continuous world uses the same working third-person camera")
	session.queue_free()
	await frames(3)


func capture_scenes() -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for scene in ["main", "3cplayground"]:
		session = load("res://content/scenes/" + scene + ".tscn").instantiate()
		if "persist_progress" in session: session.persist_progress = false
		var rig: Node3D = session.get_node("CameraRig")
		rig.capture_mouse_on_start = false
		add_child(session)
		# Capture modes must stay fixed even when the review app takes desktop focus.
		get_window().focus_exited.disconnect(rig._on_window_focus_exited)
		await frames(20)

		await capture(scene + "_shoulder.png")
		if scene == "main":
			rig._focus_held = true
			rig._apply()
			await capture("main_focus.png")
			check(rig.camera.fov < 51.0 and rig.arm.spring_length < 2.4, "captured focus frame uses the actual close camera pose")
			rig._shoulder_side = -1.0
			await capture("main_left_shoulder.png")
		session.queue_free()
		await frames(3)


func capture(filename: String) -> void:
	print("CAPTURE VIEW ", filename)
	await frames(45)
	# A paused/background window may stop presenting frames; still render the real viewport.
	RenderingServer.force_draw(false)
	var path := capture_dir.path_join(filename)
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "rendered " + filename)
