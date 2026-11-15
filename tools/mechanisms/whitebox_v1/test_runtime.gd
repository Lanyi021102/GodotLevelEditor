extends Node
const COMPONENT := preload("res://addons/godot_level_editor_mechanisms/runtime/stateful_component.gd")
const ACCESS := preload("res://addons/godot_level_editor_mechanisms/state_access.gd")
const STORE := preload("res://addons/godot_level_editor_mechanisms/store.gd")
const GRAPH := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
const TASK := preload("res://addons/godot_level_editor_narrative/runtime/task_definition.gd")
const RUNNER := preload("res://addons/godot_level_editor_narrative/runtime/task_runner.gd")
var checks := 0
var failures := 0
var world: Node3D
var actor: CharacterBody3D
var packets: Array[Dictionary] = []
var completions := 0
var actions: RefCounted

func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", title)

func quiet(node: Node) -> void:
	node.set_physics_process(false)
	for child in node.get_children(): quiet(child)

func fixture(kind: String, id := "fixture") -> Node3D:
	var root := STORE.load_pair("res://scenes/mechanisms/" + kind + ".tscn")
	if root == null: check(false, "load " + kind); return null
	root.object_id = id; root.instance_id = "test_" + id; world.add_child(root); quiet(root)
	return root

func component(root: Node3D) -> Node:
	return root.output_component()

func _ready() -> void:
	world = preload("res://addons/godot_level_editor/runtime/world.gd").new()
	world.world_id = "whitebox_mechanism_test"; world.topology = GRAPH.new(); world.topology.graph_id = "test_topology"; world.topology.graph_kind = "topology"
	world.events = GRAPH.new(); world.events.graph_id = "test_events"; add_child(world)
	actor = CharacterBody3D.new(); actor.name = "Player"; actor.collision_layer = 2; actor.collision_mask = 1
	actor.add_to_group("godot_level_editor_player"); actor.add_to_group("stealth_target"); add_child(actor)
	actions = preload("res://addons/godot_level_editor_narrative/runtime/task_actions.gd").new(); actions.world = world
	actions.legacy = preload("res://addons/godot_level_editor/runtime/level_actions.gd").new(); actions.legacy.world = world
	for kind in COMPONENT.KINDS:
		var root := fixture(kind, "asset_" + kind)
		if root == null: continue
		var item := component(root)
		check(STORE.validate(root).is_empty() and item != null and not item.get_state().is_empty(), kind + " is a valid paired editable assembly with initialized named state")
		check(not item.find_children("*", "MeshInstance3D", true, false).is_empty() and not item.find_children("*", "CollisionShape3D", true, false).is_empty(), kind + " has visible whitebox geometry and real collision/sensor shapes")
		root.free()
	button_tests()
	motion_tests()
	custom_tests()
	combination_tests()
	task_tests()
	director_tests()
	await physics_tests()
	print("MECHANISM WHITEBOX V1: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func button_tests() -> void:
	var root := fixture("button"); var button := component(root)
	actor.position = Vector3(10, 0, 0)
	check(not button.interact(actor), "button rejects interaction outside its configured radius")
	actor.position = Vector3(0, 0, 1)
	var events: Array = []; button.state_changed.connect(func(old: String, state: String): events.append([old, state]))
	check(button.interact(actor) and button.get_state() == "pressed" and events == [["idle", "pressed"]], "successful player interaction changes idle to pressed exactly once")
	check(not button.interact(actor) and events.size() == 1, "repeated pressing while held does not duplicate state-change events")
	button.advance(0.6)
	check(button.get_state() == "idle" and events.size() == 2, "button automatically releases after its configured delay")
	button.one_shot = true; button.reset_state(); button.interact(actor); button.advance(0.6)
	check(not button.interact(actor), "one-shot button remains used after its visible cap resets")
	button.one_shot = false; button.reset_state(); button.interaction_enabled = false
	check(not button.interact(actor) and button.request_state("pressed").ok, "disabling player interaction still allows explicit graph control")
	check(not button.set_property_value("arbitrary_script", true).ok and not button.set_property_value("motion_seconds", -1).ok, "property bridge rejects unknown fields and invalid numeric values")
	root.free()
	root = fixture("toggle_switch"); var lever := component(root); lever.interact(actor); var on: bool = lever.get_state() == "on"; lever.interact(actor)
	check(on and lever.get_state() == "off", "new lever toggles off/on through the shared interaction interface")
	root.free()

func motion_tests() -> void:
	for kind in ["sliding_door", "hinged_door", "lift_platform"]:
		var root := fixture(kind); var item := component(root)
		var final_state := "at_end" if kind == "lift_platform" else "open"
		var transitional := "moving" if kind == "lift_platform" else "opening"
		var completed: Array = []; var changed: Array = []
		item.action_finished.connect(func(action: String, success: bool): completed.append([action, success]))
		item.state_changed.connect(func(old: String, state: String): changed.append([old, state]))
		var before: Dictionary = item.tl_capture()
		check(item.request_state(final_state).ok and item.get_state() == transitional and completed.is_empty(), kind + " accepts a request without pretending the physical action has completed")
		item.advance(item.motion_seconds * 0.5)
		check(item.get_state() == transitional and is_equal_approx(item.progress, 0.5) and completed.is_empty(), kind + " stays in a transition state at half travel")
		var half: Dictionary = item.tl_capture(); var signal_count := changed.size()
		item.tl_restore(before)
		check(changed.size() == signal_count and completed.is_empty() and item.progress == 0, kind + " restores silently without replaying task triggers")
		item.tl_restore(half); item.advance(item.motion_seconds)
		check(item.get_state() == final_state and item.progress == 1 and completed.size() == 1 and completed[0][1], kind + " emits success only after geometry and collision reach the endpoint")
		item.locked = true; item.request_state("at_start" if kind == "lift_platform" else "closed"); item.advance(item.motion_seconds)
		check(not item.request_state(final_state).ok, kind + " honors the locked property while allowing a return/close command")
		root.free()
	var root := fixture("sliding_door"); var door := component(root)
	var finished: Array = []; door.action_finished.connect(func(action: String, success: bool): finished.append([action, success]))
	door.perform_action("open"); door.advance(0.3); door.perform_action("close"); door.advance(2)
	check(door.get_state() == "closed" and finished == [["open", false], ["close", true]], "reversing a moving door cancels the original action and reports the actual completed direction")
	root.free()
	root = fixture("hinged_door"); door = component(root); finished.clear()
	door.action_finished.connect(func(action: String, success: bool): finished.append([action, success]))
	door.perform_action("toggle"); door.advance(2)
	check(finished == [["toggle", true]], "action-completion events retain the exact requested toggle action name")
	root.free()
	root = fixture("lift_platform"); var lift := component(root); finished.clear()
	lift.action_finished.connect(func(action: String, success: bool): finished.append([action, success]))
	lift.perform_action("move_to_end"); lift.advance(0.2); lift.perform_action("stop")
	check(lift.get_state() == "stopped" and finished == [["move_to_end", false], ["stop", true]], "stopping a lift reports the canceled travel and completed stop separately")
	root.free()

func custom_tests() -> void:
	var root := fixture("terminal"); var terminal := component(root)
	terminal.custom_states = PackedStringArray(["broken", "repaired"]); terminal.initial_state = "broken"
	terminal.transition_rules.assign([{"from": "broken", "action": "repair", "to": "repaired"}]); terminal.reset_state()
	check(terminal.validate_component().is_empty() and terminal.request_state("repaired").ok and terminal.get_state() == "repaired", "custom named states and authored transition rules work without writing a component script")
	check(not terminal.request_state("broken").ok and not terminal.perform_action("unknown").ok, "custom transitions cannot jump backward without an allowed rule")
	terminal.transition_rules.append({"from": "broken", "action": "repair", "to": "repaired"})
	check(not terminal.validate_component().is_empty(), "duplicate transition rules fail validation")
	root.free()

func step_pair(root: Node3D, seconds: float) -> void:
	for tick in ceili(seconds * 60):
		root.step()
		for item in root.bindings.values():
			if item.has_method("get_state"): item.advance(1.0 / 60.0)

func combination_tests() -> void:
	var root := fixture("button_door", "button_door"); var button: Node = root.bindings.button; var door: Node = root.bindings.door
	actor.global_position = button.global_position + Vector3.BACK
	check(button.interact(actor), "button-door sample accepts a real player interaction")
	root.step()
	check(door.get_state() == "opening", "button entered-state event executes the connected open action")
	step_pair(root, 1.5)
	check(door.get_state() == "open", "button-door sample completes the actual opening")
	root.free()
	root = fixture("dual_plate_door", "dual_plate_door")
	root.bindings.plate_a._preview_occupants = 1; root.bindings.plate_b._preview_occupants = 0
	# Runtime occupancy remains physical; direct named-state changes isolate graph wiring here.
	root.bindings.plate_a._change_state("pressed"); root.step()
	check(root.bindings.door.get_state() == "closed", "one pressure plate alone cannot open the paired door")
	root.bindings.plate_b._change_state("pressed"); root.step()
	check(root.bindings.door.get_state() == "opening", "both plate outputs pass through AND and request opening")
	root.bindings.plate_a._change_state("released"); root.step()
	check(root.bindings.door.get_state() in ["closing", "closed"], "leaving either plate requests closure without retaining an old open command")
	root.free()
	root = fixture("terminal_lift", "terminal_lift"); actor.global_position = root.bindings.terminal.global_position + Vector3.BACK
	root.bindings.terminal.interact(actor); root.step()
	check(root.bindings.lift.get_state() == "moving", "activating the terminal starts the connected lift")
	step_pair(root, 1.5)
	check(root.bindings.lift.get_state() == "at_end", "terminal-lift sample reaches the physical endpoint")
	root.free()

func task_graph(nodes: Array, edges: Array) -> Resource:
	var graph := TASK.new(); graph.graph_id = "whitebox_test_task"; graph.nodes.assign(nodes)
	for index in edges.size():
		graph.edges.append({"id": "edge_" + str(index), "from": edges[index][0], "from_port": edges[index][1], "to": edges[index][2], "to_port": edges[index][3]})
	return graph

func on_action(node: Dictionary, context: Dictionary) -> Dictionary:
	if node.kind == "task_complete": completions += 1; return {"ok": true, "reason": "done"}
	return actions.perform(node, context)

func task_tests() -> void:
	var a := fixture("sliding_door", "door_a"); var b := fixture("sliding_door", "door_b")
	var target := "$world/door_a::sliding_door"
	check(ACCESS.resolve(world, target) == component(a) and ACCESS.resolve(world, "$world/door_b::sliding_door") == component(b), "two instances of the same source have distinct stable target references")
	var graph := task_graph([
		{"id": "start", "kind": "start", "params": {}},
		{"id": "request", "kind": "mechanism_request_state", "params": {"mechanism": target, "state": "open"}},
		{"id": "wait", "kind": "wait_mechanism_state", "params": {"mechanism": target, "state": "open", "timeout": 3.0, "scope": ""}},
		{"id": "done", "kind": "task_complete", "params": {"task": "test"}}
	], [["start", "then", "request", "run"], ["request", "then", "wait", "run"], ["wait", "then", "done", "run"]])
	var runner := RUNNER.new()
	if not graph.validate().is_empty(): print("TASK VALIDATION: ", graph.validate())
	check(runner.configure(graph, world.object_by_id, on_action, actions.condition), "task schema accepts request-state and wait-for-state nodes")
	runner.tick(); check(completions == 0 and not runner.waits.is_empty() and component(b).get_state() == "closed", "accepted request starts waiting, leaves other instances untouched and does not complete the task early")
	component(a).advance(2.0); runner.tick()
	check(completions == 1 and runner.waits.is_empty(), "task completes after the requested door actually reaches open")
	graph.nodes = graph.nodes.filter(func(n: Dictionary): return n.id != "request")
	graph.edges = graph.edges.filter(func(e: Dictionary): return e.from != "request" and e.to != "request")
	graph.edges.append({"id": "already", "from": "start", "from_port": "then", "to": "wait", "to_port": "run"})
	runner.configure(graph, world.object_by_id, on_action, actions.condition); runner.tick()
	check(completions == 2, "waiting immediately passes when the target was opened before the task began")
	component(a).reset_state(); graph.node_by_id("wait").params.timeout = 0.1
	runner.configure(graph, world.object_by_id, on_action, actions.condition); runner.tick(); runner.tick(0.2)
	check(runner.waits.is_empty() and completions == 2 and str(runner.last_reason.get("wait", "")).contains("timeout"), "wait nodes time out without pretending the target state was reached")
	graph.node_by_id("wait").params.timeout = 0.0
	runner.configure(graph, world.object_by_id, on_action, actions.condition); runner.tick(); var saved := runner.capture()
	runner.restore(saved); check(runner.waits.has("wait") and completions == 2, "checkpoint-style runner restore preserves an active mechanism wait without completing it")
	var trigger := task_graph([
		{"id": "changed", "kind": "mechanism_state_changed", "params": {"mechanism": target, "from_state": "opening", "to_state": "open", "once": true}},
		{"id": "done", "kind": "task_complete", "params": {"task": "test"}}
	], [["changed", "then", "done", "run"]])
	runner.configure(trigger, world.object_by_id, on_action, actions.condition)
	var bridge := preload("res://addons/godot_level_editor_mechanisms/task_bridge.gd").new(); add_child(bridge)
	packets.clear(); bridge.bind_world(world, func(kind: String, context: Dictionary): packets.append({"kind": kind, "context": context}); runner.queue_trigger(kind, context))
	component(b).request_state("open"); component(b).advance(2); runner.tick()
	check(completions == 2, "task state-change triggers reject events from another instance")
	component(a).request_state("open"); runner.tick(); check(completions == 2, "task does not treat opening as open")
	component(a).advance(2); runner.tick()
	check(completions == 3 and packets.any(func(packet: Dictionary): return packet.kind == "mechanism_action_finished" and packet.context.succeeded), "bridge publishes real endpoint and action-completion events to task graphs")
	var count := packets.size(); component(a).tl_restore(component(a).tl_capture()); runner.tick()
	check(packets.size() == count and completions == 3, "component restore emits no duplicate state, action or task completion events")
	check(ACCESS.descriptions(world).size() >= 2 and ACCESS.descriptions(world)[0].states.has("open"), "editor target descriptions provide instance names and real state choices")
	bridge.free()
	graph.node_by_id("wait").params.state = "closed"
	runner.configure(graph, world.object_by_id, on_action, actions.condition); runner.tick()
	a.free(); runner.tick()
	check(runner.waits.is_empty() and str(runner.last_reason.get("wait", "")).contains("failed"), "a target removed during a wait takes the failure output instead of waiting forever")
	b.free()

func physics_tests() -> void:
	var plate_root := fixture("pressure_plate", "physical_plate"); var plate := component(plate_root)
	plate._preview_occupants = -1; plate.release_delay = 0.05; plate_root.position.x = 40
	var collider := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius = 0.3; capsule.height = 1.7; collider.shape = capsule; collider.position.y = 0.85; actor.add_child(collider)
	actor.global_position = plate.global_position
	for tick in 8: await get_tree().physics_frame
	plate.advance(1.0 / 60.0)
	check(plate.get_state() == "pressed", "real player overlap activates the new pressure plate")
	actor.global_position += Vector3(0, 0, 5)
	for tick in 8: await get_tree().physics_frame
	plate.advance(0.1)
	check(plate.get_state() == "released", "real exit releases the plate after its configured delay")
	var weight := RigidBody3D.new(); weight.freeze = true; weight.collision_layer = 4; var shape := CollisionShape3D.new(); shape.shape = BoxShape3D.new(); weight.add_child(shape); add_child(weight); weight.global_position = plate.global_position + Vector3.UP * 0.5
	for tick in 8: await get_tree().physics_frame
	plate.advance(1.0 / 60.0)
	check(plate.get_state() == "pressed", "the configured physics layer lets a movable weight hold a plate")
	weight.free(); plate_root.free()
	var lift_root := fixture("lift_platform", "riding_lift"); var lift := component(lift_root); lift_root.position.x = 60
	lift.set_physics_process(true); actor.global_position = lift.global_position + Vector3(0, 0.24, 0)
	for tick in 20:
		await get_tree().physics_frame
		actor.velocity.y -= 18.0 / 60.0; actor.move_and_slide()
	check(actor.is_on_floor(), "player can stand on the lift's real moving collision body")
	if not actor.is_on_floor(): print("LIFT DIAGNOSTIC ", actor.global_position, " body=", lift._motion.global_position, " server=", PhysicsServer3D.body_get_state(lift._motion.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM))
	lift.request_state("at_end")
	for tick in 100:
		await get_tree().physics_frame
		actor.velocity.y -= 18.0 / 60.0; actor.move_and_slide()
	check(lift.get_state() == "at_end" and actor.global_position.y > 2.8, "AnimatableBody lift carries a standing character to its actual endpoint")
	if actor.global_position.y <= 2.8: print("LIFT END ", actor.global_position, " state=", lift.get_state(), " body=", lift._motion.global_position)
	lift_root.free()

func director_tests() -> void:
	var catalog := preload("res://addons/godot_level_editor_suite/runtime/event_catalog.gd").new()
	var event: Dictionary = catalog.add_event(); var task: Dictionary = catalog.add_task(str(event.event_id), "1")
	var graph_path := "res://tools/mechanisms/whitebox_v1/director_task_%d.tres" % OS.get_process_id()
	var workbook := "user://mechanism_director_%d.xlsx" % OS.get_process_id()
	task.graph_path = graph_path
	var target := "$world/director_door::sliding_door"
	var graph := task_graph([
		{"id": "start", "kind": "start", "params": {}},
		{"id": "request", "kind": "mechanism_request_state", "params": {"mechanism": target, "state": "open"}},
		{"id": "wait", "kind": "wait_mechanism_state", "params": {"mechanism": target, "state": "open", "timeout": 3.0, "scope": ""}},
		{"id": "done", "kind": "task_complete", "params": {"task": str(task.task_id)}}
	], [["start", "then", "request", "run"], ["request", "then", "wait", "run"], ["wait", "then", "done", "run"]])
	check(ResourceSaver.save(graph, graph_path) == OK and catalog.save_book(workbook).is_empty(), "integration fixture writes an isolated event workbook and real numeric task graph")
	var door_root := fixture("sliding_door", "director_door"); var permanent_root := fixture("sliding_door", "permanent_door")
	var level_graph := preload("res://addons/godot_level_editor/runtime/level_logic_graph.gd").new()
	level_graph.graph_id = "mechanism_permanent_integration"
	level_graph.nodes.assign([
		{"id": "start", "kind": "start", "params": {}},
		{"id": "open", "kind": "mechanism_action", "params": {"mechanism": "$world/permanent_door::sliding_door", "action": "open"}}
	]); level_graph.edges.assign([{"id": "level_open", "from": "start", "from_port": "then", "to": "open", "to_port": "run"}])
	world.level_id = "1"; world.level_logic = level_graph
	var director := preload("res://addons/godot_level_editor_suite/runtime/event_director.gd").new()
	director.world_path = world.get_path(); director.workbook = workbook; add_child(director); director.set_physics_process(false)
	director._physics_process(1.0 / 60.0)
	check(director.valid and component(permanent_root).get_state() == "opening" and director.task_states.is_empty(), "permanent level logic can control mechanism actions before a task is accepted")
	check(director.start_event(str(event.event_id)), "real event director accepts the isolated numeric task")
	director._physics_process(1.0 / 60.0)
	check(component(door_root).get_state() == "opening" and director.task_states.get(task.task_id) == "active", "real task director routes mechanism requests and waits without premature completion")
	component(door_root).advance(2.0); director._physics_process(1.0 / 60.0)
	check(director.task_states.get(task.task_id) == "completed" and director.event_states.get(event.event_id) == "completed", "actual endpoint advances the event director and completes its bound task")
	director.free(); door_root.free(); permanent_root.free(); world.level_logic = null; world.level_id = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(graph_path)); DirAccess.remove_absolute(ProjectSettings.globalize_path(workbook))
