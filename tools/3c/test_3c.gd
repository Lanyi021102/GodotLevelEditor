extends Node
var failures := 0
var checks := 0
var session: Node3D
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func wait(n: int) -> void:
	for i in n: await get_tree().physics_frame
func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60, true).timeout.connect(func(): get_tree().quit(2))
	session = load("res://scenes/3cplayground.tscn").instantiate()
	add_child(session)
	await wait(10)
	var player: CharacterBody3D = session.player
	check(player.is_on_floor(), "spawn settles on the test floor")
	check(session.hud.get_node("Root").get_child_count() == 1, "HUD contains only pause button")
	check(not InputMap.has_action("crouch") and not InputMap.has_action("reset_player"), "old action bindings removed")
	var start := player.position
	Input.action_press("move_forward")
	await wait(45)
	var walk: float = Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_press("sprint")
	await wait(40)
	var run: float = Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await wait(15)
	check(walk > 1.7 and run > 4.5 and run > walk * 2, "walk and Shift run have different speeds")
	check(player.position.distance_to(start) > 3, "real movement occurs")
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "braking reaches rest")
	# Jump forward onto the 0.6m box.
	player.position = Vector3(0, 0.04, 7.1)
	player.velocity = Vector3.ZERO
	await wait(8)
	Input.action_press("move_forward")
	Input.action_press("jump")
	await wait(1)
	Input.action_release("jump")
	var peak := player.position.y
	for i in 42:
		await wait(1)
		peak = maxf(peak, player.position.y)
	Input.action_release("move_forward")
	await wait(25)
	check(peak > 1.4, "Space jumps rather than pausing")
	check(player.is_on_floor() and absf(player.position.y - 0.6) < 0.08, "jump lands on a real 0.6m box")
	# Tap Q/E and hold controls exercise session polling.
	var before := Timeline.head
	Input.action_press("rewind")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("rewind")
	await get_tree().process_frame
	check(Timeline.frozen and absi(Timeline.cursor - (before - 60)) <= 2, "Q tap rewinds one second and remains paused")
	var at_q := Timeline.cursor
	await wait(8)
	check(Timeline.cursor == at_q, "Q release preserves pause")
	Input.action_press("fast_forward")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("fast_forward")
	await get_tree().process_frame
	check(Timeline.cursor == Timeline.head and Timeline.frozen, "E tap previews future up to head and remains paused")
	press("resume_time")
	await wait(3)
	check(not Timeline.frozen, "T resumes simulation")
	# Record F from the same physical input path used by gameplay.
	player.position = Vector3(7, 0.04, 6)
	player.velocity = Vector3.ZERO
	await wait(10)
	var split_frame := Timeline.head
	await wait(8)
	Input.action_press("interact")
	await wait(2)
	Input.action_release("interact")
	await wait(15)
	check(session.get_node("World/Lever").powered, "F interacts with nearest valid lever")
	Timeline.rewind_to_frame(split_frame)
	check(not session.get_node("World/Lever").powered, "rewind restores lever without interaction side effects")
	check(session.try_split(), "R operation commits future recording as a clone")
	var clone: CharacterBody3D = session._bodies[1]
	var recording: Array = clone.replay_segment.duplicate(true)
	check(Timeline.frozen and session.player == player, "R preserves controlled body and waits for T")
	Timeline.rewind_to_frame(split_frame - 5)
	check(not clone.visible and not clone.get_collision_layer_value(2), "rewind before creation hides clone and collision")
	Timeline.resume()
	await wait(50)
	check(clone.visible and clone.is_clone() and session._clone_count() == 1, "branch before creation retains immutable scheduled clone")
	check(clone.replay_segment == recording, "existing recording is unchanged by branching")
	check(session.get_node("World/Lever").powered, "clone replays recorded F with actor range check")
	check(clone.loop_count() == 0 and clone._replay_time > float(recording.size() - 1)/60.0, "clone stops after a single pass")
	var end := clone.global_position
	await wait(30)
	check(clone.global_position.distance_to(end) < 0.03, "clone remains at its endpoint")
	Timeline.rewind_to_frame(split_frame + 12)
	check(clone.is_clone(), "scrubbing never returns control to a clone")
	Timeline.resume()
	await wait(15)
	# A second committed recording includes real travel and a jump.
	player.position = Vector3(-9, 0.04, 5)
	player.velocity = Vector3.ZERO
	await wait(10)
	var second_start := Timeline.head
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait(10)
	Input.action_press("jump")
	await wait(1)
	Input.action_release("jump")
	await wait(65)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await wait(15)
	var destination := player.global_position
	Timeline.rewind_to_frame(second_start)
	check(session.try_split(), "second independent clone can be committed")
	var moving_clone: CharacterBody3D = session._bodies[2]
	Timeline.resume()
	var clone_peak := moving_clone.position.y
	for i in 110:
		await wait(1)
		clone_peak = maxf(clone_peak, moving_clone.position.y)
	check(clone_peak > 1.4, "clone reproduces the recorded jump")
	check(moving_clone.global_position.distance_to(destination) < 0.2, "moving clone finishes at recorded endpoint")
	var moving_end := moving_clone.global_position
	await wait(20)
	check(moving_clone.global_position.distance_to(moving_end) < 0.02, "moving clone stops without looping")
	check(clone.replay_segment == recording, "creating another clone never edits the first recording")
	var hold_head := Timeline.head
	Input.action_press("rewind")
	await get_tree().create_timer(0.65, true).timeout
	Input.action_release("rewind")
	await get_tree().process_frame
	check(Timeline.frozen and Timeline.cursor < hold_head - 80, "holding Q continuously scrubs after the initial one-second step")
	press("resume_time")
	await wait(3)
	EnergyLedger.spend(99999)
	check(not EnergyLedger.is_empty() and EnergyLedger.cumulative == 0, "deprecated energy API cannot restrict gameplay")
	# Native pause button still pauses all actors and recording.
	session.hud.get_node("Root/PauseButton").pressed.emit()
	before = Timeline.head
	await wait(5)
	check(Timeline.frozen and Timeline.head == before, "pause button stops world and recording")
	press("resume_time")
	await wait(2)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			player.position = Vector3(-2, 0.04, 6)
			await wait(30)
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "actual rendered playground captured")
	session.queue_free()
	await wait(3)
	Timeline.clear()
	session = load("res://scenes/main.tscn").instantiate()
	session.persist_progress = false
	add_child(session)
	await wait(8)
	check(session.world.runtime_valid, "default continuous world still assembles")
	check(Timeline.get_entity_index(session.world.get_node("Rewindable")) >= 0, "default world retains shared rewind registration")
	session.queue_free()
	await wait(3)
	print("3C: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
