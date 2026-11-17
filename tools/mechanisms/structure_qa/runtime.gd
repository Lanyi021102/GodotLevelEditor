extends Node
const OUTPUT := "res://content/qa/mechanisms/"
var checks := 0
var failures := 0
var details: Array = []
var observations: Array = []
var player: CharacterBody3D

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	details.append({"ok": ok, "title": title})
	print("[F6 PASS] " if ok else "[F6 FAIL] ", title)

func frames(count := 8) -> void:
	for i in count: await get_tree().physics_frame

func stand(component: Node3D, offset := Vector3(0, 0.1, 1.0)) -> void:
	player.global_position = component.global_position + offset
	player.velocity = Vector3.ZERO
	await frames(12)

func press_f() -> void:
	# Same entry point used when the player clicks back into the game after the
	# editor or another isolated QA window took focus.
	get_window().grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	player.camera_rig.capture_mouse()
	var event := InputEventKey.new(); event.keycode = KEY_F; event.physical_keycode = KEY_F; event.pressed = true
	Input.parse_input_event(event); await frames(2)
	event = InputEventKey.new(); event.keycode = KEY_F; event.physical_keycode = KEY_F; event.pressed = false
	Input.parse_input_event(event); await frames(2)

func _ready() -> void:
	await frames(35)
	var level := get_parent()
	player = get_tree().get_first_node_in_group("godot_level_editor_player")
	check(player != null and level.runtime_valid, "F6 inherited level starts with its real default player and valid runtime")
	if player == null: finish(); return
	check(InputMap.action_get_events("interact").any(func(event: InputEvent): return event is InputEventKey and event.physical_keycode == KEY_F), "installed plugin maps F to player interaction")
	var button: Node3D = level.get_node("button").output_component()
	var single: Node3D = level.get_node("single_door").output_component()
	var double_: Node3D = level.get_node("double_door").output_component()
	var plate: Node3D = level.get_node("pressure_plate").output_component()
	var lift: Node3D = level.get_node("lift_platform").output_component()
	await stand(button); await press_f()
	check(button.get_state() == "pressed", "real F input presses the standalone button")
	check(single.get_state() == "close" and double_.get_state() == "close" and lift.get_state() == "at_start", "button interaction does not control either door or lift")
	await get_tree().create_timer(0.6).timeout
	check(button.get_state() == "idle", "authored button reset parameter works in F6")
	await stand(plate, Vector3(0, 0.2, 0)); await frames(12)
	check(plate.get_state() == "pressed", "real player occupancy presses the standalone pressure plate")
	await stand(button); await get_tree().create_timer(0.6).timeout
	check(plate.get_state() == "released", "authored release delay clears occupancy after leaving")
	check(single.get_state() == "close" and double_.get_state() == "close", "pressure plate does not control the doors")
	for door in [single, double_]:
		check(door.state_names() == ["close", "moving", "open"], "placed door exposes all three authored states")
		check(is_equal_approx(door.motion_curve.sample(0.5), 0.25), "placed door retains its node-edited animation curve")
		await stand(door); await press_f()
		check(door.get_state() == "moving" and door.angle_degrees() > 0 and door.angle_degrees() < 90, "real F input starts the door's continuous rotation")
		await get_tree().create_timer(1.3).timeout
		check(door.get_state() == "open" and is_equal_approx(door.angle_degrees(), 90), "door reaches ninety degrees after its authored duration")
		await press_f(); await get_tree().create_timer(1.3).timeout
		check(door.get_state() == "close" and is_zero_approx(door.angle_degrees()), "second F interaction closes the door along the curve")
	await stand(lift, Vector3(0, 0.3, 0)); await press_f()
	check(lift.get_state() == "moving", "real F input starts the standalone lift")
	await get_tree().create_timer(1.3).timeout
	check(lift.get_state() == "at_end", "lift reaches its authored endpoint")
	check(player.global_position.y > lift.global_position.y + 2.5, "moving platform carries the real player")
	observations.append({"stage": "lift_top_before_return", "player": str(player.global_position), "velocity": str(player.velocity), "lift": str(lift.global_position), "progress": lift.progress, "can_interact": lift.can_interact(player), "floor": player.is_on_floor()})
	await press_f(); await get_tree().create_timer(1.3).timeout
	observations.append({"stage": "lift_after_return", "player": str(player.global_position), "velocity": str(player.velocity), "progress": lift.progress, "state": lift.get_state()})
	check(lift.get_state() == "at_start", "player can F-interact at the endpoint to return")
	check(player.global_position.y < lift.global_position.y + 0.8, "returning lift carries the player back down")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUTPUT + "f6.png")
	finish()

func finish() -> void:
	var file := FileAccess.open(OUTPUT + "f6_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "details": details, "observations": observations}, "\t")); file.close()
	print("MECHANISM F6 RESULT: %d checks, %d failures" % [checks, failures])
	if "--mechanism-runtime-probe" in OS.get_cmdline_user_args(): get_tree().quit(1 if failures else 0)
