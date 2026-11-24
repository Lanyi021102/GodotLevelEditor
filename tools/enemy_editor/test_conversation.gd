extends Node3D
const SAMPLE := preload("res://addons/godot_level_editor/scenes/npcs/v1_human_medium_male.tscn")
const SCENE_REFS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_reference.gd")
const LOGIC := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_logic_graph.gd")
const TASK := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
var failures := 0
var checks := 0

func check(condition: bool, what: String) -> void:
	checks += 1
	if not condition: failures += 1
	print("[PASS] " if condition else "[FAIL] ", what)

func frames(count: int) -> void:
	for frame in count: await get_tree().physics_frame
	await get_tree().process_frame

func connect_nodes(graph: Resource, source: String, target: String) -> void:
	graph.edges.append({"id": source + "_" + target, "from": source, "from_port": "then", "to": target, "to_port": "run"})

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var world: Node3D = preload("res://addons/godot_level_editor/templates/empty_level.tscn").instantiate()
	world.level_id = "2" # Registered development-level ID; no authored scene is opened.
	world.events.graph_id = "events"
	world.topology.graph_id = "topology"
	var graph: LOGIC = world.level_logic
	graph.graph_id = "conversation"
	graph.events_xlsx = "user://npc_conversation_%d.xlsx" % OS.get_process_id()
	graph.dialogue_xlsx = "user://npc_dialogue_%d.xlsx" % OS.get_process_id()
	var library := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd").new()
	library.speakers = {"居民": Color.WHITE}
	library.groups = [{"id": "residents", "name": "居民", "comments": [{"id": "greeting", "name": "问候", "lines": [{"id": "00001", "speaker": "居民", "text": "请到出口来。", "dialogue_mode": "stationary", "type": "对白", "duration": 0.0}]}]}]
	check(library.write_xlsx(graph.dialogue_xlsx).is_empty(), "private stationary dialogue worksheet is ready")
	var catalog := CATALOG.new()
	var event := catalog.add_event()
	var task := catalog.add_task(event.event_id, world.level_id)
	task.graph_path = "res://tools/enemy_editor/conversation_task_%d.tres" % OS.get_process_id()
	var task_graph := TASK.new()
	task_graph.graph_id = "walk_to_exit"
	task_graph.dialogue_xlsx = graph.dialogue_xlsx
	task_graph.nodes = [{"id":"trigger","kind":"room_enter","params":{"room":"exit_area","once":false}}, {"id":"complete","kind":"task_complete","params":{"task":task.task_id}}]
	connect_nodes(task_graph, "trigger", "complete")
	check(ResourceSaver.save(task_graph, task.graph_path) == OK and catalog.save_book(graph.events_xlsx).is_empty(), "temporary graph and workbook saved")
	graph.nodes = [{"id":"talk","kind":"npc_interact","params":{"npc":"$world/guide"}},
		{"id":"neighbor_chat","kind":"npc_interact","params":{"npc":"$world/neighbor"}},
		{"id":"line","kind":"show_dialog","params":{"dialog_id":"greeting"}},
		{"id":"finished","kind":"dialog_completed","params":{"dialog_id":"greeting"}},
		{"id":"accept","kind":"task_accept","params":{"task":task.task_id}}]
	connect_nodes(graph, "talk", "line")
	connect_nodes(graph, "finished", "accept")
	var guide: GuardAI = SAMPLE.instantiate()
	guide.name = "居民"
	guide.enemy_instance_id = "guide"
	guide.allow_conversation = true
	guide.enemy_definition = guide.enemy_definition.duplicate(true)
	guide.enemy_definition.states[0].speed = 0.8
	guide.patrol_points = [Vector3(2, 0, 0), Vector3(0, 0, 0)]
	world.add_child(guide)
	var neighbor: GuardAI = SAMPLE.instantiate()
	neighbor.name = "邻居"
	neighbor.enemy_instance_id = "neighbor"
	neighbor.allow_conversation = true
	neighbor.position.x = -1.5
	world.add_child(neighbor)
	var other: GuardAI = SAMPLE.instantiate()
	other.enemy_instance_id = "other"
	other.position.z = 4
	world.add_child(other)
	var exit_area = world.ROOM.new()
	exit_area.room_id = "exit_area"
	exit_area.uses_topology = false
	exit_area.position = Vector3(5, 1, 0)
	exit_area.bounds_size = Vector3(2, 2, 2)
	world.add_child(exit_area)
	var marker: Node3D = preload("res://addons/godot_level_editor/scenes/narrative/interaction_point.tscn").instantiate()
	marker.position.z = 1.5
	world.add_child(marker)
	var player: CharacterBody3D = preload("res://addons/godot_level_editor/scenes/humanoid_player.tscn").instantiate()
	player.position = Vector3(0, 0.1, 0.5)
	world.add_child(player)
	var session := preload("res://addons/godot_level_editor/scenes/level_editor/play_session.tscn").instantiate()
	var rig: Node3D = session.get_node("CameraRig")
	session.remove_child(rig)
	session.free()
	rig.target_path = NodePath()
	rig.target = player
	player.camera_rig = rig
	world.add_child(rig)
	var camera := Camera3D.new()
	camera.position = Vector3(1.0, 1.9, 3.5)
	world.add_child(camera)
	add_child(world)
	camera.make_current()
	camera.look_at(Vector3(0.25, 1.4, 0))
	await frames(15)
	var director = world.logic_director
	check(director != null and director.valid and director.level_runner != null, "permanent graph loads in the playable level")
	check(guide.global_position.x > 0.04 and guide.enemy_runtime_state().behavior == "patrol", "sample NPC walks its authored route")
	check(LOGIC.permanent_npcs(world).get("$world/guide") == guide and not LOGIC.permanent_npcs(world).has("$world/other"), "only enabled NPC offers a stable permanent binding")
	var trigger := {"id":"talk","kind":"npc_interact","params":{"npc":"guide","task":task.task_id}}
	var options := SCENE_REFS.choices(world, task_graph, trigger, "npc")
	check(options.get("guide") == guide and not options.has("other"), "task dropdown selects only enabled NPC instances")
	check(SCENE_REFS.resolve(world, graph, graph.node_by_id("talk"), "npc", {"type":"nodes","nodes":[guide.get_node("ModelRoot").get_path()]}) == "$world/guide", "dragging the model resolves to its authored NPC instance")
	check(other.prompt == null and not other.is_in_group("godot_level_editor_interactable"), "second instance retains no conversation")
	check(neighbor.can_interact(player) and neighbor.prompt.text.is_empty(), "second eligible resident has no competing hint")
	check(player.interaction_target == guide and player.interaction_hint.visible and str(guide.name) in player.interaction_hint.text and "[F" in player.interaction_hint.text and marker.prompt.text.is_empty(), "neighboring interaction point and player agree on one F hint")
	var normal_font: int = player.interaction_hint.get_theme_font_size("font_size")
	var normal_width: float = player.interaction_hint.size.x
	camera.global_position = guide.prompt.global_position + Vector3.BACK * 0.7
	camera.look_at(guide.prompt.global_position)
	await frames(3)
	check(player.interaction_hint.get_theme_font_size("font_size") == normal_font and is_equal_approx(player.interaction_hint.size.x, normal_width), "approaching camera keeps the selected hint at the same screen size")
	camera.global_position = Vector3(1.0, 1.9, 3.5)
	camera.look_at(Vector3(0.25, 1.4, 0))
	if "--capture-conversation" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await frames(3)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://npc-conversation.png")
	var initial_count: int = director.level_runner.counts.get("talk", 0) if director != null else 0
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(3)
	check(director != null and director.dialogue.is_active() and director.level_runner.counts.get("talk", 0) == initial_count + 1, "physics input F on the walking NPC opens the linked dialogue")
	check(director != null and director.dialogue.current_mode() == "stationary" and not guide.prompt.visible and player.interaction_target == null and not player.interaction_hint.visible, "conversation hides the NPC name and F hint")
	if director != null and director.dialogue.is_active():
		while director.dialogue.is_active():
			await get_tree().process_frame
			director.dialogue.advance()
		await frames(5)
	check(director != null and director.task_states.get(task.task_id) == "active", "dialogue completion accepts the selected task")
	player.global_position = marker.global_position + Vector3.BACK * 0.2
	await frames(3)
	check(player.interaction_target == marker and marker.display_name in player.interaction_hint.text and player.interaction_hint.visible, "after dialogue the nearer interaction point gets the only prompt")
	player.global_position = Vector3(5, 0.2, 0)
	await frames(8)
	check(director != null and director.event_states.get(event.event_id) == "completed", "walking into the trigger completes the accepted task")
	check(player.interaction_target == null and not player.interaction_hint.visible, "leaving all candidates clears the hint")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(task.graph_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(graph.events_xlsx))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(graph.dialogue_xlsx))
	print("NPC CONVERSATION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
