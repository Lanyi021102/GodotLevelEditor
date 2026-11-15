extends Node
const WORLD := preload("res://addons/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
const FACTORY := preload("res://addons/godot_level_editor/scene_factory.gd")
const SPAWN := preload("res://addons/godot_level_editor/runtime/spawn_marker.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func wait(count := 8) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame
func run_world(world: Node3D) -> void:
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await wait(15)
func _ready() -> void:
	get_tree().create_timer(45, true).timeout.connect(func(): get_tree().quit(2))
	_run.call_deferred()
func _run() -> void:
	var file_hash := FileAccess.get_sha256("res://scenes/levels/4_TestLevel.tscn")
	var world: Node3D = load("res://scenes/levels/4_TestLevel.tscn").instantiate()
	await run_world(world)
	var session := world.get_node_or_null("PlaySession")
	check(session != null, "running 4_TestLevel directly creates a play session")
	if session == null: get_tree().quit(1); return
	check(session.world == world and world.runtime_valid and not session.persist_progress, "play session uses the authored world and isolated progress")
	var player: CharacterBody3D = session.player
	var camera: Node3D = session.camera_rig
	var spawn: Marker3D = world.get_node("PlayerSpawn")
	check(player.spawn_transform.is_equal_approx(spawn.global_transform) and player.global_position.distance_to(spawn.global_position) < 0.3, "authored player spawn drives initial position and reset transform")
	check(session.hud.get_node_or_null("Root") != null and camera.camera.is_current() and camera.target == player, "standard HUD and active third person camera are connected")
	check(get_tree().get_nodes_in_group("godot_level_editor_player").size() == 1, "standalone play creates exactly one player")
	camera.capture_mouse()
	var before := player.global_position
	Input.action_press("move_right")
	await wait(30)
	Input.action_release("move_right")
	check(player.global_position.distance_to(before) > 0.5, "WASD moves the real player in the authored level")
	player.reset_to_spawn()
	await wait(10)
	var start_y := player.global_position.y
	Input.action_press("jump")
	await wait(1)
	Input.action_release("jump")
	var peak := player.global_position.y
	for i in 55:
		await wait(1)
		peak = maxf(peak, player.global_position.y)
	check(peak > start_y + 1.0 and player.is_on_floor(), "Space jumps and lands on the saved level collision")
	camera._on_window_focus_exited()
	before = player.global_position
	Input.action_press("move_right")
	await wait(20)
	Input.action_release("move_right")
	check(not camera.is_gameplay_input_enabled() and player.global_position.distance_to(before) < 0.15, "switching focus to the editor releases gameplay input")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	camera._unhandled_input(click)
	check(camera.is_gameplay_input_enabled(), "clicking the game restores character controls")
	player.global_position.y = -10
	await wait(10)
	check(player.global_position.distance_to(player.spawn_transform.origin) < 0.3, "falling returns the player to the authored spawn")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "standalone authored level renders with the player")
	check(FileAccess.get_sha256("res://scenes/levels/4_TestLevel.tscn") == file_hash and not world.has_node("World"), "playtest does not rewrite or duplicate the authored level")
	world.queue_free()
	await wait(3)
	var fresh := WORLD.new(); fresh.name = "FreshLevel"; fresh.start_room_id = ""
	fresh.topology = GRAPH.new(); fresh.topology.graph_id = "standalone_topology"; fresh.topology.graph_kind = "topology"
	fresh.events = GRAPH.new(); fresh.events.graph_id = "standalone_events"
	FACTORY.block(fresh, "floor", Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var marker := SPAWN.new(); marker.name = "PlayerSpawn"; marker.position = Vector3(3, 0.1, 2); fresh.add_child(marker)
	await run_world(fresh)
	check(fresh.runtime_valid and fresh.has_node("PlaySession") and fresh.get_node("PlaySession").player.spawn_transform.origin.is_equal_approx(marker.global_position), "fresh worlds automatically use the same standalone play components")
	# A complete sandbox may contain several independent detection areas.
	var entered: Array[String] = []
	for room_id in ["courtyard", "workshop"]:
		var room: Node3D = load("res://addons/godot_level_editor/palette_assets/room.tscn").instantiate()
		room.room_id = room_id
		room.position = Vector3(0, 0, 0) if room_id == "courtyard" else Vector3(6, 0, 0)
		room.player_entered.connect(func(id: String, _actor: Node3D): entered.append(id))
		fresh.add_child(room)
	check(fresh.start_room_id.is_empty() and fresh.validate().is_empty(), "multiple sandbox Room areas validate without a starting room or connections")
	var sandbox_player: CharacterBody3D = fresh.get_node("PlaySession").player
	sandbox_player.global_position = Vector3(0, 0.1, 0)
	await wait(5)
	sandbox_player.global_position = Vector3(6, 0.1, 0)
	await wait(5)
	check(entered.has("courtyard") and entered.has("workshop"), "unconnected sandbox areas still detect the player during standalone play")
	fresh.queue_free()
	await wait(3)
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main); get_tree().current_scene = main
	await wait(15)
	check(not main.world.has_node("PlaySession") and get_tree().get_nodes_in_group("godot_level_editor_player").size() == 1, "F5 main scene keeps its existing player without a second play session")
	main.queue_free()
	await wait(3)
	print("STANDALONE LEVEL PLAY: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
