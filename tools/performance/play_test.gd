extends SceneTree

const PLAYER := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/player.gd")
const DATA := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sequence.gd")
const TASK := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")
const TASK_DIR := "res://tools/performance"
const ACTOR := "$world/test_resident"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	var fixture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): fixture = arg.trim_prefix("--fixture=")
	check(not fixture.is_empty() and change_scene_to_file(fixture) == OK, "load the saved map as the scene (F6 runtime entry)")
	if failures > 0: quit(1); return
	await scene_changed
	await frames(10)
	var world := current_scene as Node3D
	var director: Node = world.logic_director
	var rig: Node3D = get_first_node_in_group("main").camera_rig
	check(is_instance_valid(director) and director.level_runner != null, "native scene starts the real player and persistent graph")
	if not is_instance_valid(director) or director.level_runner == null: quit(1); return
	var base_camera: Camera3D = rig.camera
	var player: CharacterBody3D = rig.target
	var actor: Node3D = DATA.npc_choices(world).get(ACTOR)
	var original := actor.global_position
	check(root.get_camera_3d() == base_camera and rig.is_gameplay_input_enabled() and director.level_objective.is_empty() and not PLAYER.is_playing_in(world), "player starts in control before entering the Room")
	Input.action_press("move_forward")
	for attempt in 220:
		if PLAYER.is_playing_in(world): break
		await physics_frame
	Input.action_release("move_forward")
	await frames(4)
	var playback := world.get_node_or_null(PLAYER.NODE_NAME)
	check(PLAYER.is_playing_in(world) and not rig.is_gameplay_input_enabled() and root.get_camera_3d() != base_camera, "entering the trigger cuts to the first camera and locks gameplay input")
	if playback == null: quit(1); return
	check(not actor.is_physics_processing() and director.level_objective.is_empty(), "NPC behavior yields during the performance and graph waits")
	check(not director.checkpoint.capture(director), "checkpoint capture defers while the performance is in progress")
	var motion := DATA.motion_player(actor)
	check(motion != null and motion.assigned_animation == "walk" and actor.global_position.distance_to(original) > 0.01, "NPC follows the route with its actual walking animation")
	var playing_sequence: Resource = world.performances[0]
	var first_pose: Transform3D = root.get_camera_3d().global_transform
	var busy := PLAYER.play(world, playing_sequence.id)
	check(not busy.ok and PLAYER.is_playing_in(world), "another trigger cannot replace a running performance")
	await frames(124)
	check(root.get_camera_3d() != base_camera and not root.get_camera_3d().global_transform.is_equal_approx(first_pose), "runtime hard-cuts to the second shot")
	await frames(195)
	check(not PLAYER.is_playing_in(world) and director.level_objective == "演出结束", "completed port advances the actual level graph after the last frame")
	check(root.get_camera_3d() == base_camera and rig.is_gameplay_input_enabled(), "completion restores the original player camera and input")
	check(actor.global_position.distance_to(Vector3(1.5, 0, -3)) < 0.08 and actor.is_physics_processing(), "NPC remains at its final position and resumes behavior")

	var quiet := DATA.new()
	quiet.id = "quiet"
	quiet.actors.append(ACTOR)
	quiet.clips.append({"id": "place", "kind": "place", "label": "站位", "actor": ACTOR, "start": 0.0, "duration": 0.5, "point": Vector3(-1, 0, -1)})
	world.performances.append(quiet)
	var task_book: Resource = director.catalog
	var event: Dictionary = task_book.add_event()
	var task: Dictionary = task_book.add_task(event.event_id, director.current_level_id)
	task.graph_path = TASK_DIR.path_join(".task_%d.tres" % OS.get_process_id())
	var graph := TASK.new()
	graph.graph_id = "performance_task"
	graph.nodes.assign([
		{"id": "start", "kind": "start", "params": {}},
		{"id": "play", "kind": "play_performance", "params": {"performance": quiet.id}},
		{"id": "done", "kind": "objective", "params": {"text": "NPC 就位"}},
	])
	graph.edges.assign([
		{"id": "start_play", "from": "start", "from_port": "then", "to": "play", "to_port": "run"},
		{"id": "play_done", "from": "play", "from_port": "completed", "to": "done", "to_port": "run"},
	])
	var saved := ResourceSaver.save(graph, task.graph_path)
	check(saved == OK and director.start_event(event.event_id), "actual task graph starts the NPC-only performance")
	await frames(4)
	check(PLAYER.is_playing_in(world) and root.get_camera_3d() == base_camera and rig.is_gameplay_input_enabled(), "NPC-only playback keeps normal 3C input and camera")
	await frames(34)
	check(director.active.get(event.event_id, {}).get("objective", "") == "NPC 就位" and actor.global_position.distance_to(Vector3(-1, 0, -1)) < 0.08, "task graph continues from the completed port and retains NPC placement")

	var before := actor.global_position
	quiet.input_mode = 2
	var interrupted := PLAYER.play(world, quiet.id)
	check(interrupted.ok and not rig.is_gameplay_input_enabled(), "explicit lock also applies to an NPC-only performance")
	PLAYER.cancel_in(world)
	await frames(3)
	check(interrupted.ticket.status == "failed" and rig.is_gameplay_input_enabled() and actor.global_position.distance_to(before) < 0.06, "interruption restores gameplay input and the starting NPC pose")
	quiet.actors.clear()
	check(not PLAYER.play(world, quiet.id).ok and rig.is_gameplay_input_enabled(), "invalid actor references fail before changing input")
	print("PERFORMANCE PLAY: ", checks - failures, "/", checks)
	quit(0 if failures == 0 else 1)
