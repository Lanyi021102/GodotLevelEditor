extends Node
## One active graph per event; tasks advance in catalog order after an entire event batch.
signal task_graph_rejected(task_id: String, errors: PackedStringArray)
var task_binding_errors := PackedStringArray()
var task_binding_notice := ""
signal event_started(event_id: String)
signal event_completed(event_id: String)
signal task_started(task_id: String)
signal task_completed(task_id: String)
signal task_failed(task_id: String, reason: String)
signal checkpoint_saved
signal checkpoint_restored
signal objective_changed(text: String)
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const RUNNER := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_runner.gd")
@export_file("*.xlsx") var workbook := CATALOG.PATH
@export var world_path: NodePath
@export var automatic_starts := true
var catalog: Resource
var active: Dictionary = {}
var event_states: Dictionary = {}
var task_states: Dictionary = {}
var dialogue: CanvasLayer
var valid := false
var world: Node
var objective_label: Control
var retry_button: Button
var _failure_mouse_captured := false
var _npcs: Dictionary = {}
var _hidden: Dictionary = {}
var current_level_id := ""
var _world_links: Array[Dictionary] = []
var variables: Dictionary = {}
var _task_actions := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_actions.gd").new()
var _mechanism_bridge: Node
var checkpoint := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_checkpoint.gd").new()
var _restore_requested := false
var _failure_text := ""
var _suppress_triggers := 0
var _debug_clock := 0.0
var _debug_instances: Dictionary = {}
var level_runner: RefCounted
var level_variables: Dictionary = {}
var level_objective := ""
func _ready() -> void:
	add_to_group("godot_level_editor_task_directors")
	process_physics_priority = 520
	world = get_node_or_null(world_path)
	var result := CATALOG.load_book(workbook)
	if world == null or not result.errors.is_empty():
		push_error("事件执行器无法载入：" + "; ".join(result.errors))
		return
	catalog = result.catalog
	dialogue = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_player.gd").new()
	add_child(dialogue)
	dialogue.dialogue_completed.connect(func(id: String): _broadcast("dialog_completed", {"dialog_id": id}))
	dialogue.opened.connect(_hide_ui)
	dialogue.closed.connect(_restore_ui)
	var layer := CanvasLayer.new()
	add_child(layer)
	var ancestor: Node = get_parent()
	while ancestor != null and objective_label == null:
		objective_label = ancestor.get_node_or_null("HUD/Root/TaskTracker") as Control
		ancestor = ancestor.get_parent()
	if objective_label == null:
		objective_label = preload("res://addons/godot_level_editor/scenes/ui/task_tracker.tscn").instantiate()
		layer.add_child(objective_label)
	task_completed.connect(_animate_task_completion)
	retry_button = Button.new()
	retry_button.text = "从检查点重试"
	retry_button.hide()
	retry_button.pressed.connect(retry_from_checkpoint)
	layer.add_child(retry_button)
	_connect_world()
	valid = true
	_start_game_events.call_deferred()
func _connect_world() -> void:
	if _mechanism_bridge == null:
		_mechanism_bridge = preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_bridge.gd").new()
		add_child(_mechanism_bridge)
	_mechanism_bridge.bind_world(world, _broadcast)
	var levels := LEVELS.load_book()
	var row: Dictionary = levels.catalog.for_world(world) if levels.catalog != null else {}
	current_level_id = str(row.get("level_id", ""))
	_task_actions.world = world
	_task_actions.legacy = preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_actions.gd").new()
	_task_actions.legacy.world = world
	_attach_level_logic()
	for id in world.objects():
		var anchor: Node = world.object_by_id(id)
		if anchor.get_script() == world.REGION:
			_link(anchor, "player_entered", _region_changed.bind(str(id), true))
			_link(anchor, "player_exited", _region_changed.bind(str(id), false))
		var component: Node = anchor.output_component() if anchor.has_method("output_component") else anchor
		if component != null and component.has_signal("interacted"):
			for info in component.get_signal_list():
				if info.name != "interacted": continue
				if info.args.size() == 3: _link(component, "interacted", _object_interacted.bind(str(id)))
				elif info.args.size() == 2: _link(component, "interacted", _npc_object_interacted.bind(str(id)))
		var agent: Node = _task_actions.agent(str(id))
		if agent != null and agent.has_signal("state_changed"): _link(agent, "state_changed", _actor_state_changed.bind(str(id)))
	var player_agent: Node = _task_actions.agent()
	if player_agent != null and player_agent.has_signal("state_changed"): _link(player_agent, "state_changed", _actor_state_changed.bind(""))
	for room in world.rooms():
		_link(room, "player_entered", _room_entered)
		_link(room, "player_exited", _room_exited)
	var candidates := world.find_children("*", "Node3D", true, false) if level_runner != null else world.get_parent().find_children("*", "Node3D", true, false) if world.get_parent() != null else world.find_children("*", "Node3D", true, false)
	for node in candidates:
		if node.get_script() != preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/npc.gd"): continue
		var ancestor: Node = node.get_parent()
		while ancestor != null and ancestor.get_script() != WORLD: ancestor = ancestor.get_parent()
		if ancestor != null and ancestor != world: continue
		var reference := _npc_reference(node)
		_npcs[reference if level_runner != null and not reference.is_empty() else node.object_id] = node
		_link(node, "interacted", _npc_interacted.bind(node))
	_refresh_npcs()

func _npc_reference(node: Node) -> String:
	for reference in world.objects():
		if world.object_by_id(reference) == node: return str(reference)
	return ""

func _attach_level_logic() -> void:
	level_runner = null; level_variables = {}; level_objective = ""
	if world.level_logic == null: return
	var graph: Resource = world.level_logic
	if not graph.is_level_logic() or not graph.validate().is_empty() or not graph.validate_bindings(world).is_empty(): return
	var runner := RUNNER.new()
	if not runner.configure(graph, world.object_by_id, perform_level, _task_actions.condition): return
	level_runner = runner; runner.variables = level_variables
	world.logic_director = self
	runner.objective_requested.connect(func(text: String): level_objective = text; _hud())
	runner.checkpoint_requested.connect(world._request_progress)

func accept_task(task_id: String) -> Dictionary:
	if not valid: return {"ok": false, "reason": "任务执行器尚未就绪"}
	var task: Dictionary = catalog.task_by_id(task_id)
	if task.is_empty(): return {"ok": false, "reason": "接受任务引用不存在"}
	if str(task.level_id) != current_level_id: return {"ok": false, "reason": "任务不属于当前关卡"}
	var tasks: Array = catalog.event_tasks(str(task.event_id))
	if tasks.is_empty() or str(tasks[0].task_id) != task_id: return {"ok": false, "reason": "请接取第一项任务，后续任务自动接续"}
	if event_states.has(str(task.event_id)): return {"ok": false, "reason": "任务已接取、已完成或已失败，不会重复启动"}
	var ok := start_event(str(task.event_id))
	return {"ok": ok, "reason": "已接受任务：" + str(task.display_name) if ok else "；".join(task_binding_errors) if not task_binding_errors.is_empty() else "任务未能接取"}

func perform_level(node: Dictionary, _context: Dictionary) -> Dictionary:
	if level_runner == null: return {"ok": false, "reason": "关卡图未就绪"}
	if node.kind == "task_accept": return accept_task(str(node.params.task))
	if node.kind == "show_dialog":
		var result: Dictionary = world.level_logic.load_dialogue()
		if not result.errors.is_empty() or dialogue.is_active(): return {"ok": false, "reason": "台本无效或已有对话正在播放"}
		dialogue.library = result.library
		var ok: bool = dialogue.show_dialog(str(node.params.dialog_id))
		return {"ok": ok, "reason": "已显示对话" if ok else "对话引用无效"}
	return _task_actions.perform(node, _context)
func _link(node: Node, signal_name: String, callback: Callable) -> void:
	if node.is_connected(signal_name, callback): return
	node.connect(signal_name, callback)
	_world_links.append({"node": node, "signal": signal_name, "callback": callback})
func _region_changed(actor: Node3D, id: String, entered: bool) -> void:
	_broadcast("region_enter" if entered else "region_exit", {"object": id, "actor": str(actor.get_path())})
func _object_interacted(_id: String, action: String, actor: Node3D, reference: String) -> void:
	_broadcast("object_interacted", {"object": reference, "action": action, "actor": str(actor.get_path())})
func _npc_object_interacted(_id: String, actor: Node3D, reference: String) -> void:
	_object_interacted(_id, "interact", actor, reference)
func _actor_state_changed(key: String, value: bool, actor_id: String) -> void:
	_broadcast("state_changed", {"actor_id": actor_id, "key": key, "value": value})
func _condition(node: Dictionary, event_id: String) -> bool:
	if node.kind == "objective_state": return active.get(event_id, {}).get("objectives", {}).get(node.params.key, {}).get("state", "") == node.params.status
	return _task_actions.condition(node)
func retry_from_checkpoint() -> bool:
	var ok: bool = checkpoint.restore(self)
	if ok:
		_failure_text = ""
		var main: Node = get_tree().get_first_node_in_group("main")
		if _failure_mouse_captured and main != null and main.get("camera_rig") != null: main.camera_rig.capture_mouse()
		_failure_mouse_captured = false
		_suppress_triggers = 2
		_hud()
		checkpoint_restored.emit()
	return ok
func _npc_interacted(id: String, _actor: Node3D, source: Node = null) -> void:
	_broadcast("npc_interact", {"npc": id, "npc_ref": _npc_reference(source) if source != null else ""})
func bind_world(new_world: Node) -> bool:
	if not valid or new_world == null or new_world.get_script() != WORLD or dialogue.is_active(): return false
	for state in active.values():
		if state.runner != null: state.saved_runner = state.runner.capture()
		state.runner = null; state.graph = null
	for link in _world_links:
		if is_instance_valid(link.node) and link.node.is_connected(link.signal, link.callback): link.node.disconnect(link.signal, link.callback)
	_world_links.clear()
	for npc in _npcs.values():
		if is_instance_valid(npc): npc.interaction_allowed = false
	_npcs.clear()
	if world.logic_director == self: world.logic_director = null
	world = new_world
	_connect_world()
	for id in active: _attach_runner(id)
	_refresh_npcs()
	return true
func _task_here(event_id: String) -> bool:
	var state: Dictionary = active[event_id]
	var tasks: Array = catalog.event_tasks(event_id)
	return not tasks.is_empty() and str(tasks[mini(int(state.index), tasks.size() - 1)].level_id) == current_level_id
func _start_game_events() -> void:
	if not automatic_starts: return
	for event in catalog.events:
		if event.start_type == "game_start": start_event(event.event_id)
func _room_entered(id: String, _actor: Node3D) -> void:
	if _suppress_triggers > 0: return
	for event in catalog.events:
		if automatic_starts and event.start_type == "room_enter" and event.start_key == id: start_event(event.event_id)
	_broadcast("room_enter", {"room": id})

func _room_exited(id: String, _actor: Node3D) -> void:
	if _suppress_triggers == 0: _broadcast("room_exit", {"room": id})
func publish_event(key: String) -> void:
	if not valid: return
	for event in catalog.events:
		if automatic_starts and event.start_type == "event_received" and event.start_key == key: start_event(event.event_id)
	_broadcast("event_received", {"key": key})
func start_event(id_or_name: String) -> bool:
	if not valid: return false
	var event: Dictionary = catalog.event_by_id(id_or_name)
	if event.is_empty():
		for row in catalog.events:
			if row.name == id_or_name: event = row; break
	if event.is_empty() or event_states.has(event.event_id): return false
	var first_tasks: Array = catalog.event_tasks(str(event.event_id))
	if not first_tasks.is_empty() and not _check_task_bindings(first_tasks[0]): return false
	var id := str(event.event_id)
	event_states[id] = "active"
	active[id] = {"index": 0, "hold": false, "advance": false, "runner": null, "graph": null, "objective": "", "saved_runner": {}, "objectives": {}}
	event_started.emit(id)
	_start_task(id)
	return true
func _start_task(event_id: String) -> void:
	var state: Dictionary = active[event_id]
	var tasks: Array = catalog.event_tasks(event_id)
	if int(state.index) >= tasks.size():
		if not state.hold: _finish_event(event_id)
		return
	var task: Dictionary = tasks[int(state.index)]
	state.advance = false
	state.objective = ""
	task_states[task.task_id] = "active"
	task_started.emit(task.task_id)
	state.runner = null
	state.graph = null
	state.saved_runner = {}
	_attach_runner(event_id)
	_hud()
	_refresh_npcs()
func _check_task_bindings(task: Dictionary) -> bool:
	task_binding_errors.clear()
	if str(task.level_id) != current_level_id or not FileAccess.file_exists(str(task.graph_path)): return true
	var graph: Resource = load(task.graph_path)
	if graph == null or not graph.has_method("load_dialogue"): return true
	task_binding_errors = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_bindings.gd").validate(world, graph, str(task.task_id))
	if not task_binding_errors.is_empty():
		task_binding_notice = "无法开始任务：" + str(task.display_name) + " — " + "；".join(task_binding_errors)
		_hud()
		task_graph_rejected.emit(str(task.task_id), task_binding_errors)
	elif not task_binding_notice.is_empty():
		task_binding_notice = ""
		_hud()
	return task_binding_errors.is_empty()

func _attach_runner(event_id: String) -> void:
	if not _task_here(event_id): return
	var state: Dictionary = active[event_id]
	var tasks: Array = catalog.event_tasks(event_id)
	var task: Dictionary = tasks[mini(int(state.index), tasks.size() - 1)]
	if not _check_task_bindings(task):
		state["failure"] = "；".join(task_binding_errors)
		return
	if FileAccess.file_exists(task.graph_path):
		var graph: Resource = load(task.graph_path)
		if graph != null and graph.has_method("load_dialogue") and graph.validate().is_empty():
			var runner := RUNNER.new()
			if runner.configure(graph, world.object_by_id, _action.bind(event_id), _condition.bind(event_id)):
				runner.variables = variables
				runner.task_id = str(task.task_id)
				state.runner = runner
				state.graph = graph
				if not state.get("saved_runner", {}).is_empty(): runner.restore(state.saved_runner)
				runner.checkpoint_requested.connect(world._request_progress)
				runner.objective_requested.connect(func(text: String): state.objective = text; _hud())
		else: push_error("任务图无效：" + str(task.graph_path))
	else: push_warning("任务等待配置图：" + str(task.task_id))
func _action(node: Dictionary, context: Dictionary, event_id: String) -> Dictionary:
	if not active.has(event_id) or not _task_here(event_id): return {"ok": false, "reason": "任务不属于当前关卡"}
	if preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_nodes.gd").is_action(str(node.kind)): return _task_actions.perform(node, context)
	var state: Dictionary = active[event_id]
	var tasks: Array = catalog.event_tasks(event_id)
	var task: Dictionary = tasks[mini(int(state.index), tasks.size() - 1)] if not tasks.is_empty() else {}
	var ok := false
	match str(node.kind):
		"task_start": ok = not task.is_empty() and str(node.params.get("task")) == str(task.task_id) and task_states.get(task.task_id) == "active"
		"task_complete":
			ok = not task.is_empty() and str(node.params.get("task")) == str(task.task_id) and task_states.get(task.task_id) == "active" and not state.has("failure")
			if ok:
				task_states[task.task_id] = "completed"
				state.advance = true
				task_completed.emit(task.task_id)
		"show_dialog":
			var result: Dictionary = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd").read_xlsx(context._dialogue_xlsx) if context.has("_dialogue_xlsx") else state.graph.load_dialogue()
			if result.errors.is_empty() and not dialogue.is_active():
				dialogue.library = result.library
				ok = dialogue.show_dialog(str(node.params.get("dialog_id", "")))
		"objective_start":
			if not state.has("objectives"): state.objectives = {}
			if not state.objectives.has(node.params.key): state.objectives[node.params.key] = {"text": node.params.text, "state": "active", "optional": node.params.optional}
			ok = true
			_hud()
		"objective_complete", "objective_fail":
			var goals: Dictionary = state.get("objectives", {})
			ok = goals.has(node.params.key) and goals[node.params.key].state == "active"
			if ok: goals[node.params.key].state = "completed" if node.kind == "objective_complete" else "failed"; _hud()
		"task_fail":
			ok = str(node.params.task) == str(task.task_id) and task_states.get(task.task_id) == "active"
			if ok: state["failure"] = str(node.params.reason)
		"checkpoint_save":
			ok = checkpoint.capture(self)
			if ok: checkpoint_saved.emit()
		"checkpoint_restore":
			ok = not checkpoint.saved.is_empty() and checkpoint.saved.level == current_level_id
			if ok: _restore_requested = true
		"set_switch", "set_visibility", "enemy_patrol", "change_item", "equip_item", "set_actor_state": return _task_actions.perform(node, context)
		"event_hold": state.hold = true; ok = true
		"event_complete": _finish_event(event_id); ok = true
	return {"ok": ok, "reason": "已执行" if ok else "任务状态／引用不匹配，或对话忙碌"}
func _physics_process(delta: float) -> void:
	if not valid: return
	if _suppress_triggers > 0: _suppress_triggers -= 1
	if level_runner != null: level_runner.tick(delta)
	var ids := active.keys()
	ids.sort()
	for id in ids:
		if not active.has(id): continue
		var state: Dictionary = active[id]
		if state.runner != null and _task_here(id): state.runner.tick(delta)
		if _restore_requested:
			_restore_requested = false
			retry_from_checkpoint()
			return
		if active.has(id) and state.has("failure"):
			var tasks: Array = catalog.event_tasks(id)
			var task_id := str(tasks[int(state.index)].task_id)
			task_states[task_id] = "failed"
			event_states[id] = "failed"
			_failure_text = str(state.failure)
			_failure_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			var main: Node = get_tree().get_first_node_in_group("main")
			if main != null and main.get("camera_rig") != null: main.camera_rig.release_mouse()
			active.erase(id)
			task_failed.emit(task_id, _failure_text)
			_hud()
			continue
		if active.has(id) and state.advance and (state.runner == null or state.runner.pending.is_empty()):
			state.advance = false
			state.index += 1
			_start_task(id)
	_refresh_npcs()
	_debug_clock += delta
	if _debug_clock >= 0.15:
		_debug_clock = 0.0
		_send_debug()
func _send_debug() -> void:
	if not EngineDebugger.is_active(): return
	var current := {}
	if level_runner != null:
		var instance := str(get_path()) + "/level_logic"
		current[instance] = true
		EngineDebugger.send_message("godot_level_editor_narrative:state", [{"instance": instance, "world_id": world.world_id, "graph_id": level_runner.definition.graph_id, "topology_id": "", "event_revision": level_runner.definition.semantic_hash(), "values": level_runner.values.duplicate(), "persistent": level_runner.persistent.duplicate(), "local": level_runner.local_state.duplicate(), "reasons": level_runner.last_reason.duplicate(), "counts": level_runner.counts.duplicate(), "queued": level_runner.pending.size() + level_runner.waits.size()}])
	for id in active:
		var state: Dictionary = active[id]
		if state.runner == null or not _task_here(id): continue
		var instance := str(get_path()) + "/event_" + str(id)
		current[instance] = true
		var runner: RefCounted = state.runner
		EngineDebugger.send_message("godot_level_editor_narrative:state", [{"instance": instance, "world_id": world.world_id, "graph_id": runner.definition.graph_id, "topology_id": "", "event_revision": runner.definition.semantic_hash(), "values": runner.values.duplicate(), "persistent": runner.persistent.duplicate(), "local": runner.local_state.duplicate(), "reasons": runner.last_reason.duplicate(), "counts": runner.counts.duplicate(), "queued": runner.pending.size() + runner.waits.size()}])
	for instance in _debug_instances:
		if not current.has(instance): EngineDebugger.send_message("godot_level_editor_narrative:remove", [instance])
	_debug_instances = current
func _broadcast(kind: String, context: Dictionary) -> void:
	if _suppress_triggers > 0: return
	if level_runner != null:
		var message := context.duplicate()
		message.erase("task")
		if kind != "npc_interact": level_runner.queue_trigger(kind, message)
		elif not str(message.get("npc_ref", "")).is_empty():
			message.npc = message.npc_ref
			level_runner.queue_trigger(kind, message)
	for id in active:
		var state: Dictionary = active[id]
		var tasks: Array = catalog.event_tasks(id)
		if state.runner == null or tasks.is_empty() or not _task_here(id): continue
		var message := context.duplicate()
		message.task = str(tasks[mini(int(state.index), tasks.size() - 1)].task_id)
		state.runner.queue_trigger(kind, message)
func _finish_event(id: String) -> void:
	if event_states.get(id) != "active": return
	event_states[id] = "completed"
	active.erase(id)
	event_completed.emit(id)
	_hud()
func _refresh_npcs() -> void:
	for id in _npcs:
		var allowed := false
		if level_runner != null:
			for node in level_runner.definition.nodes:
				if node.kind == "npc_interact" and node.params.get("npc") == id: allowed = true
		for event_id in active:
			var state: Dictionary = active[event_id]
			if state.runner == null or not _task_here(event_id): continue
			for node in state.runner.active_nodes():
				if node.kind == "npc_interact" and node.params.get("npc") == _npcs[id].object_id and task_states.get(node.params.get("task")) == "active": allowed = true
		_npcs[id].interaction_allowed = allowed and not dialogue.is_active()
func _animate_task_completion(task_id: String) -> void:
	var task: Dictionary = catalog.task_by_id(task_id)
	if task.is_empty(): return
	var event: Dictionary = catalog.event_by_id(str(task.event_id))
	objective_label.complete({"event_id": str(task.event_id), "event": str(event.display_name), "task_id": task_id, "task": str(task.display_name)})

func _hud() -> void:
	if objective_label == null: return
	var messages := PackedStringArray()
	var entries: Array[Dictionary] = []
	if not level_objective.is_empty(): messages.append(level_objective)
	for event in catalog.events:
		if not active.has(event.event_id): continue
		var state: Dictionary = active[event.event_id]
		var tasks: Array = catalog.event_tasks(event.event_id)
		var task: Dictionary = tasks[mini(int(state.index), tasks.size() - 1)] if not tasks.is_empty() else {}
		entries.append({"event_id": str(event.event_id), "event": str(event.display_name), "task_id": str(task.get("task_id", "")), "task": str(task.get("display_name", ""))})
		messages.append(str(event.display_name) + ("：" + str(task.display_name) if not task.is_empty() else "") + (" — " + str(state.objective) if not str(state.objective).is_empty() else ""))
		for goal_id in state.get("objectives", {}):
			var goal: Dictionary = state.objectives[goal_id]
			var marker := {"active": "○", "completed": "✓", "failed": "×"}.get(goal.state, "○")
			messages.append("  " + marker + " " + str(goal.text) + ("（可选）" if goal.optional else ""))
	if not _failure_text.is_empty(): messages.append("任务失败：" + _failure_text)
	if not task_binding_notice.is_empty(): messages.append(task_binding_notice)
	objective_label.text = "\n".join(messages)
	objective_label.sync(entries, _failure_text, task_binding_notice)
	if retry_button != null:
		retry_button.visible = not _failure_text.is_empty() and not checkpoint.saved.is_empty() and checkpoint.saved.level == current_level_id
		retry_button.position = objective_label.position + Vector2(0, objective_label.get_combined_minimum_size().y + 12)
	objective_changed.emit(objective_label.text)
func _hide_ui() -> void:
	var nodes: Array[Node] = [objective_label]
	for npc in _npcs.values(): nodes.append(npc.prompt)
	for node in nodes: _hidden[node] = node.visible; node.visible = false
func _restore_ui() -> void:
	for node in _hidden:
		if is_instance_valid(node): node.visible = _hidden[node]
	_hidden.clear()
func capture_progress() -> Dictionary:
	var states := {}
	for id in active:
		var state: Dictionary = active[id]
		states[id] = {"index": state.index, "hold": state.hold, "advance": state.advance, "objective": state.objective, "runner": state.runner.capture() if state.runner != null else state.get("saved_runner", {}), "objectives": state.get("objectives", {}).duplicate(true)}
	var data := {"version": 1, "workbook": workbook, "events": event_states.duplicate(), "tasks": task_states.duplicate(), "active": states, "dialogues": dialogue.completed.duplicate(), "variables": variables.duplicate(true), "failure_text": _failure_text}
	if level_runner != null: data["level_logic"] = {"world_id": world.world_id, "graph_id": level_runner.definition.graph_id, "runner": level_runner.capture(), "variables": level_variables.duplicate(true), "objective": level_objective}
	return data
func restore_progress(data: Dictionary) -> bool:
	if data.get("version") != 1 or data.get("workbook") != workbook: return false
	for key in ["events", "tasks", "active", "dialogues"]:
		if not data.get(key) is Dictionary: return false
	for id in data.events:
		if catalog.event_by_id(id).is_empty() or data.events[id] not in ["active", "completed", "failed"]: return false
	for id in data.tasks:
		if catalog.task_by_id(id).is_empty() or data.tasks[id] not in ["active", "completed", "failed"]: return false
	for id in data.active:
		if not data.events.has(id) or data.events[id] != "active" or not data.active[id] is Dictionary: return false
		var index := int(data.active[id].get("index", -1))
		if index < 0 or index > catalog.event_tasks(id).size(): return false
	if data.has("variables") and not data.variables is Dictionary: return false
	for id in data.active:
		var record: Dictionary = data.active[id]
		if not record.get("runner", {}) is Dictionary or not record.get("objectives", {}) is Dictionary: return false
	if data.has("level_logic"):
		var level: Variant = data.level_logic
		if not level is Dictionary or level_runner == null or level.get("world_id") != world.world_id or level.get("graph_id") != level_runner.definition.graph_id or not level.get("runner") is Dictionary or not level.get("variables") is Dictionary: return false
	objective_label.reset()
	task_binding_notice = ""
	variables = data.get("variables", {}).duplicate(true)
	_failure_text = str(data.get("failure_text", ""))
	active.clear()
	event_states = data.events.duplicate()
	task_states = data.tasks.duplicate()
	dialogue.completed = data.dialogues.duplicate()
	for id in data.active:
		var saved: Dictionary = data.active[id]
		active[id] = {"index": int(saved.index), "hold": bool(saved.hold), "advance": bool(saved.get("advance", false)), "runner": null, "graph": null, "objective": str(saved.objective), "saved_runner": saved.runner.duplicate(true), "objectives": saved.get("objectives", {}).duplicate(true)}
		_attach_runner(id)
	if data.has("level_logic"):
		level_variables = data.level_logic.variables.duplicate(true)
		level_runner.variables = level_variables
		level_runner.restore(data.level_logic.runner)
		level_objective = str(data.level_logic.get("objective", ""))
	_hud()
	_refresh_npcs()
	return true
