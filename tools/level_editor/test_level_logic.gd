extends Node
const WORLD := preload("res://addons/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
const LOGIC := preload("res://addons/godot_level_editor/runtime/level_logic_graph.gd")
const TASK := preload("res://addons/godot_level_editor_narrative/runtime/task_definition.gd")
const CATALOG := preload("res://addons/godot_level_editor_suite/runtime/event_catalog.gd")
const PROFILE := preload("res://addons/godot_level_editor/runtime/entity_profile.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)

func physics(count := 6) -> void:
	for i in count: await get_tree().physics_frame

func wire(graph: Resource, from: String, to: String, output := "then") -> void:
	graph.edges.append({"id": "e_" + str(graph.edges.size()), "from": from, "from_port": output, "to": to, "to_port": "run"})

func task_graph(task: Dictionary) -> void:
	var graph := TASK.new(); graph.graph_id = "level_logic_test_" + str(task.task_id)
	graph.nodes = [{"id": "start", "kind": "start", "params": {}}, {"id": "started", "kind": "set_variable", "params": GRAPH.TASK_NODES.defaults("set_variable")}, {"id": "finish", "kind": "event_received", "params": {"key": "finish_" + str(task.task_id), "once": false}}, {"id": "complete", "kind": "task_complete", "params": {"task": task.task_id}}]
	graph.nodes[1].params.key = "started_" + str(task.task_id)
	wire(graph, "start", "started"); wire(graph, "finish", "complete")
	task.graph_path = "res://tools/level_editor/level_logic_task_%d_%s.tres" % [OS.get_process_id(), task.task_id]
	paths.append(task.graph_path)
	check(graph.validate().is_empty() and ResourceSaver.save(graph, task.graph_path) == OK, "acceptance fixture saves a valid task graph")

func _ready() -> void:
	get_tree().create_timer(45, true).timeout.connect(func(): get_tree().paused = false; get_tree().quit(2))
	_run.call_deferred()

func _run() -> void:
	var catalog := CATALOG.new(); var event := catalog.add_event()
	event.start_type = "game_start"
	var first := catalog.add_task(event.event_id, "2"); var second := catalog.add_task(event.event_id, "2")
	task_graph(first); task_graph(second)
	var workbook := "user://level_logic_%d.xlsx" % OS.get_process_id()
	paths.append(workbook)
	check(catalog.save_book(workbook).is_empty(), "acceptance fixture saves an isolated task catalog")
	var world := WORLD.new(); world.name = "Sandbox"; world.level_id = "2"; world.world_id = "level_logic_test"; world.start_room_id = ""
	world.topology = GRAPH.new(); world.topology.graph_id = "empty_topology"; world.topology.graph_kind = "topology"
	world.events = GRAPH.new(); world.events.graph_id = "legacy_events"
	var npc: Node3D = load("res://scenes/narrative/npc.tscn").instantiate(); npc.object_id = "guide"; npc.name = "Guide"; npc.position.x = -4; world.add_child(npc)
	var task_npc: Node3D = load("res://scenes/narrative/npc.tscn").instantiate(); task_npc.object_id = "task_only"; task_npc.name = "TaskOnly"; world.add_child(task_npc)
	var profile := PROFILE.new(); profile.lifetime = "task"; profile.task_id = first.task_id; task_npc.set_meta(PROFILE.META, profile)
	var region := WORLD.REGION.new(); region.object_id = "courtyard"; region.extent = Vector3(2, 2, 2); world.add_child(region)
	var graph := LOGIC.new(); graph.graph_id = "sandbox_logic"; graph.events_xlsx = workbook
	graph.nodes = [
		{"id": "start", "kind": "start", "params": {}},
		{"id": "always", "kind": "set_variable", "params": GRAPH.TASK_NODES.defaults("set_variable")},
		{"id": "npc", "kind": "npc_interact", "params": {"npc": "$world/guide"}},
		{"id": "dialog", "kind": "show_dialog", "params": {"dialog_id": "reception_intro"}},
		{"id": "dialog_end", "kind": "dialog_completed", "params": {"dialog_id": "reception_intro"}},
		{"id": "accept", "kind": "task_accept", "params": {"task": first.task_id}},
		{"id": "enter", "kind": "region_enter", "params": {"object": "$world/courtyard", "once": false}},
		{"id": "visits", "kind": "counter", "params": {"target": 3}},
		{"id": "repeat", "kind": "event_received", "params": {"key": "repeat_accept", "once": false}},
		{"id": "repeat_failed", "kind": "set_variable", "params": GRAPH.TASK_NODES.defaults("set_variable")},
		{"id": "wait_signal", "kind": "event_received", "params": {"key": "wait", "once": false}},
		{"id": "delay", "kind": "delay", "params": {"seconds": 0.15, "scope": ""}},
		{"id": "delayed", "kind": "set_variable", "params": GRAPH.TASK_NODES.defaults("set_variable")},
	]
	graph.node_by_id("always").params.key = "always"
	graph.node_by_id("repeat_failed").params.key = "repeat_failed"
	graph.node_by_id("delayed").params.key = "delayed"
	wire(graph, "start", "always"); wire(graph, "npc", "dialog"); wire(graph, "dialog_end", "accept"); wire(graph, "enter", "visits"); wire(graph, "repeat", "accept"); wire(graph, "accept", "repeat_failed", "failed"); wire(graph, "wait_signal", "delay"); wire(graph, "delay", "delayed")
	world.level_logic = graph
	check(graph.validate().is_empty() and world.validate().is_empty(), "permanent graph validates with task and NPC references but no task activation scope")
	check(LOGIC.permanent_npcs(world).has("$world/guide") and not LOGIC.permanent_npcs(world).has("$world/task_only"), "only level-resident NPCs are available for permanent logic")
	graph.node_by_id("npc").params.npc = "$world/task_only"
	check(not graph.validate_bindings(world).is_empty(), "pasted task-only NPC references are rejected during validation")
	graph.node_by_id("npc").params.npc = "$world/missing"
	check(not graph.validate_bindings(world).is_empty(), "deleted permanent NPC references are rejected")
	graph.node_by_id("npc").params.npc = "$world/guide"
	graph.node_by_id("npc").params.task = first.task_id
	check(not graph.validate().is_empty(), "task-scoped conversation parameters cannot silently disable permanent triggers")
	graph.node_by_id("npc").params.erase("task")
	var bad_mechanism := LOGIC.new(); bad_mechanism.graph_id = "missing_mechanism"
	bad_mechanism.nodes = [{"id": "missing", "kind": "mechanism_state", "params": {"mechanism": "$world/missing::door", "state": "open"}}]
	check(not bad_mechanism.validate_bindings(world).is_empty(), "permanent mechanism nodes validate actual scene component references")
	graph.node_by_id("accept").params.task = second.task_id
	check(not graph.validate().is_empty(), "acceptance cannot silently skip earlier tasks in an event")
	graph.node_by_id("accept").params.task = first.task_id
	var rejected: Resource = graph.duplicate(true)
	rejected.nodes.append({"id": "task_complete", "kind": "task_complete", "params": {"task": first.task_id}})
	check(not rejected.validate().is_empty(), "task completion actions cannot leak into the permanent node palette or saved graph")
	var player := CharacterBody3D.new(); player.name = "Player"; player.collision_layer = 2; player.position = Vector3(-4, 0.2, 0); player.add_to_group("godot_level_editor_player")
	var shape := CollisionShape3D.new(); shape.shape = SphereShape3D.new(); player.add_child(shape)
	world.add_child(player)
	add_child(world)
	await physics(10)
	var director: Node = world.logic_director
	check(director != null and director.valid and director.level_runner != null, "F6-compatible world automatically attaches one permanent-logic service")
	if director == null: get_tree().quit(1); return
	check(not director.event_states.has(event.event_id) and not director.variables.has("started_" + first.task_id), "task graph remains inactive until a task is accepted, including catalog auto-start entries")
	check(director.level_variables.get("always") == true, "level start logic executes without accepting any task")
	check(npc.can_interact(player) and not task_npc.interaction_allowed, "permanent NPC conversation is enabled before task acceptance")
	player.global_position = Vector3(0, 0.2, 0); await physics(8)
	check(director.level_runner.flow.get("visits", {}).get("count", 0) == 1, "real region entry executes permanent level logic before acceptance")
	director.publish_event("finish_" + str(second.task_id)); await physics(2)
	check(not director.task_states.has(second.task_id), "future tasks cannot consume events sent before acceptance")
	player.global_position = Vector3(-4, 0.2, 0); await physics(4)
	check(npc.interact(player), "real player F-interaction can trigger the permanent NPC")
	await get_tree().process_frame
	await get_tree().process_frame
	check(director.dialogue.is_active(), "permanent NPC graph opens the same dialogue player used by task graphs")
	while director.dialogue.is_active():
		await get_tree().process_frame
		director.dialogue.advance()
	await physics(6)
	check(director.task_states.get(first.task_id) == "active" and director.variables.get("started_" + first.task_id) == true, "dialogue completion reaches Accept Task and starts the selected first task")
	check(not director.task_states.has(second.task_id), "acceptance activates only the first ordered task initially")
	director.publish_event("repeat_accept"); await physics(4)
	check(director.level_variables.get("repeat_failed") == true and director.active[event.event_id].runner.counts.get("start") == 1, "repeated acceptance uses the failure output without restarting the active task")
	var saved: Dictionary = director.capture_progress()
	director.level_variables["always"] = false
	check(director.restore_progress(saved) and director.level_variables.get("always") == true and director.task_states.get(first.task_id) == "active", "permanent variables and accepted-task progress restore together without replaying start")
	var invalid := saved.duplicate(true); invalid.level_logic.graph_id = "foreign"
	var before: Dictionary = director.capture_progress()
	check(not director.restore_progress(invalid) and before == director.capture_progress(), "foreign level graph state is rejected before changing task progress")
	director.publish_event("finish_" + str(first.task_id)); await physics(5)
	check(director.task_states.get(first.task_id) == "completed" and director.task_states.get(second.task_id) == "active", "accepting the first task automatically continues to the next ordered task")
	director.publish_event("finish_" + str(second.task_id)); await physics(5)
	check(director.event_states.get(event.event_id) == "completed", "the accepted event finishes after its final task")
	player.global_position = Vector3(0, 0.2, 0); await physics(6)
	check(director.level_runner.flow.get("visits", {}).get("count", 0) == 2 and npc.interaction_allowed, "permanent region and NPC logic continue after all tasks complete")
	director.publish_event("wait"); await physics(16)
	check(director.level_variables.get("delayed") == true, "shared asynchronous wait nodes execute in permanent level logic")
	check(not director.accept_task(first.task_id).ok and not director.accept_task("missing").ok, "completed or missing tasks cannot be accepted again")
	var progress := world.capture_progress()
	check(progress.has("level_logic") and world.restore_progress(progress), "world save bridge preserves permanent logic and accepted tasks")
	var invalid_world := progress.duplicate(true); invalid_world.level_logic.level_logic.graph_id = "foreign"
	check(not world.restore_progress(invalid_world) and progress == world.capture_progress(), "world bridge rejects foreign permanent graph state without changing either graph")
	world.queue_free(); await physics(3)
	var standalone: Node3D = load("res://scenes/levels/4_TestLevel.tscn").instantiate()
	standalone.level_logic = LOGIC.new(); standalone.level_logic.graph_id = "standalone_logic"; standalone.level_logic.events_xlsx = workbook
	standalone.level_logic.nodes.assign([{"id": "start", "kind": "start", "params": {}}, {"id": "always", "kind": "set_variable", "params": GRAPH.TASK_NODES.defaults("set_variable")}])
	wire(standalone.level_logic, "start", "always")
	var authored_hash := FileAccess.get_sha256("res://scenes/levels/4_TestLevel.tscn")
	get_tree().root.add_child(standalone); get_tree().current_scene = standalone
	await physics(15)
	check(standalone.has_node("PlaySession") and standalone.logic_director != null and standalone.logic_director.level_variables.get("flag") == true, "direct F6 play runs permanent logic alongside the standard player session")
	check(get_tree().get_nodes_in_group("godot_level_editor_task_directors").size() == 1 and get_tree().get_nodes_in_group("godot_level_editor_player").size() == 1, "standalone level creates one task service and one player")
	check(authored_hash == FileAccess.get_sha256("res://scenes/levels/4_TestLevel.tscn"), "runtime logic services never rewrite the authored level")
	get_tree().current_scene = self; standalone.queue_free(); await physics(3)
	for path in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PERMANENT LEVEL LOGIC: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
