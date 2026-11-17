extends Node
## 白盒试玩集成：真实移动、碰撞、交互、复位与进度隔离。
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func wait(count: int) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60, true).timeout.connect(func(): get_tree().quit(2))
	var session: Node3D = load("res://content/scenes/3cplayground.tscn").instantiate()
	add_child(session)
	await wait(12)
	var player: CharacterBody3D = session.player
	session.camera_rig.capture_mouse()
	var start := player.position
	Input.action_press("move_forward")
	await wait(35)
	Input.action_release("move_forward")
	await wait(15)
	var walked := start.distance_to(player.position)
	check(walked > 0.5, "W moves the real player over the whitebox floor")
	player.reset_to_spawn()
	await wait(10)
	start = player.position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait(35)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await wait(15)
	check(start.distance_to(player.position) > walked * 1.5, "Shift retains basic running")
	player.position = Vector3(-9, 0.05, 5)
	player.velocity = Vector3.ZERO
	await wait(10)
	var floor_y := player.position.y
	Input.action_press("jump")
	await wait(1)
	Input.action_release("jump")
	var peak := player.position.y
	for i in 65:
		await wait(1)
		peak = maxf(peak, player.position.y)
	check(peak > floor_y + 1.3 and player.is_on_floor(), "Space jumps and lands on real collision")
	var lever: Node3D = session.get_node("World/Lever")
	player.global_position = lever.global_position + Vector3(0, 0.05, 1.0)
	player.velocity = Vector3.ZERO
	await wait(10)
	Input.action_press("interact")
	await wait(1)
	Input.action_release("interact")
	await wait(60)
	check(lever.powered and session.get_node("World/Door").is_open(), "F drives the edited lever and door")
	player.position.y = -10
	await wait(12)
	check(player.global_position.distance_to(player.spawn_transform.origin) < 0.2 and not lever.powered, "falling resets player and temporary mechanism state")
	for key in [KEY_Q, KEY_E, KEY_R, KEY_T]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		Input.parse_input_event(event)
		await wait(3)
		event.pressed = false
		Input.parse_input_event(event)
	check(not get_tree().paused and get_tree().get_nodes_in_group("godot_level_editor_player").size() == 1, "former time/clone keys leave the simulation running with one player")
	check(not player.has_node("Rewindable") and get_node_or_null("/root/Timeline") == null and get_node_or_null("/root/Abilities") == null and get_node_or_null("/root/EnergyLedger") == null, "removed systems have no live singleton or player component")
	check(not session.hud.has_node("Root/PauseButton"), "editable HUD has no time pause button")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "actual rendered whitebox captured")
	session.queue_free()
	await wait(3)
	session = load("res://content/scenes/main.tscn").instantiate()
	session.persist_progress = false
	add_child(session)
	await wait(12)
	check(session.world.runtime_valid, "default world still validates and assembles")
	check(session.world.events.nodes.is_empty() and session.world.topology.edges.is_empty() and not session.has_node("Narrative") and get_tree().get_nodes_in_group("guard").is_empty(), "default whitebox has no preset puzzle, enemy, story or task")
	var old_path := GLESaveSystem.storage_path
	GLESaveSystem.storage_path = "user://whitebox_test_progress.json"
	var disk: Dictionary = GLESaveSystem.save_game()
	check(disk.has("progress") and not disk.has("abilities"), "isolated save contains editable progress without removed abilities")
	check(not GLESaveSystem.load_game().is_empty(), "editable world progress reloads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GLESaveSystem.storage_path))
	GLESaveSystem.storage_path = old_path
	session.queue_free()
	await wait(3)
	print("WHITEBOX: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
