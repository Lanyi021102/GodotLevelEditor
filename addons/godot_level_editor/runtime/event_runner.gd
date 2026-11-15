extends RefCounted
## Deterministic physics-frame evaluator, separate from both authoring and canvas.
signal executed(node_id: String, reason: String)
signal objective_requested(text: String)
signal checkpoint_requested
const BUDGET := 64
var definition: GodotLevelEditorLevelGraph
var resolver: Callable
var persistent: Dictionary = {}
var local_state: Dictionary = {}
var pending: Array[Dictionary] = []
var values: Dictionary = {}
var last_reason: Dictionary = {}
var frame := 0
var overflowed := false
var action_handler: Callable
var condition_handler: Callable
var incoming: Array[Dictionary] = []
var counts: Dictionary = {}
var started := false
const MAX_QUEUE := 256

func configure(graph: GodotLevelEditorLevelGraph, lookup: Callable, actions: Callable = Callable(), conditions: Callable = Callable()) -> bool:
	if graph == null or graph.graph_kind != "events" or not graph.validate().is_empty():
		return false
	definition = graph.duplicate(true)
	resolver = lookup
	action_handler = actions
	condition_handler = conditions
	incoming.clear()
	counts.clear()
	started = false
	persistent.clear()
	local_state.clear()
	pending.clear()
	values.clear()
	return true

func _state(id: String) -> bool:
	return bool(persistent.get(id, local_state.get(id, false)))

func _set_state(n: Dictionary, value: bool) -> void:
	if n.get("params", {}).get("persistent", true):
		persistent[n.id] = value
	else:
		local_state[n.id] = value

func _input(id: String, port: String, visiting: Dictionary) -> bool:
	return bool(_raw_input(id, port, visiting, false))

func _raw_input(id: String, port: String, visiting: Dictionary, fallback: Variant) -> Variant:
	for e in definition.edges:
		if e.to == id and e.to_port == port:
			return _value(str(e.from), visiting)
	return fallback

func _value(id: String, visiting: Dictionary) -> Variant:
	if visiting.has(id):
		return false
	visiting = visiting.duplicate()
	visiting[id] = true
	var n := definition.node_by_id(id)
	if n.is_empty():
		return false
	var p: Dictionary = n.get("params", {})
	var result: Variant = false
	match str(n.kind):
		"player_state", "has_item": result = condition_handler.call(n) if condition_handler.is_valid() else false
		"constant": result = bool(p.get("value", false))
		"number": result = float(p.get("value", 0))
		"object": result = str(p.get("object", ""))
		"greater": result = float(_raw_input(id, "a", visiting, 0.0)) > float(_raw_input(id, "b", visiting, 0.0))
		"latch": result = _state(id)
		"source", "read_state":
			var object_id := str(p.get("object", "")) if n.kind == "source" else str(_raw_input(id, "target", visiting, ""))
			var anchor: Node = resolver.call(object_id) if resolver.is_valid() else null
			var component: Node = anchor.call("output_component") if anchor != null and anchor.has_method("output_component") else null
			var method := "is_open" if p.get("query", "powered") == "open" else "is_powered"
			result = component != null and component.has_method(method) and component.call(method)
		"all": result = _input(id, "a", visiting) and _input(id, "b", visiting)
	values[id] = result
	return result

func _emit_event(id: String, port: String, context: Dictionary = {}) -> void:
	var edges := definition.edges.duplicate(true)
	edges.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.id) < str(b.id))
	for e in edges:
		if e.from == id and e.from_port == port:
			if pending.size() < MAX_QUEUE:
				pending.append({"to": e.to, "port": e.to_port, "from": id, "context": context.duplicate(true)})
			else: last_reason[id] = "事件队列超过 256，已停止追加"

func _advance_waits(_delta: float) -> void: pass
func _custom_event(_node: Dictionary, _event: Dictionary) -> String: return "不支持的节点"
func _accept_event(_event: Dictionary) -> bool: return true
func _matches_trigger(_node: Dictionary, _context: Dictionary) -> bool: return true

func tick(delta: float = 1.0 / 60.0) -> void:
	if definition == null:
		return
	frame += 1
	_advance_waits(delta)
	values.clear()
	var ordered := definition.nodes.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.id) < str(b.id))
	var triggers := incoming.duplicate(true)
	incoming.clear()
	if not started:
		started = true
		triggers.push_front({"kind": "start", "context": {}})
	for trigger in triggers:
		for n in ordered:
			if n.kind != trigger.kind or not _matches_trigger(n, trigger.context): continue
			var context: Dictionary = trigger.context
			if n.kind == "room_enter" and n.params.get("room") != context.get("room"): continue
			if n.kind in ["region_enter", "region_exit", "object_interacted"] and n.params.get("object") != context.get("object"): continue
			if n.kind == "event_received" and n.params.get("key") != context.get("key"): continue
			if n.kind in ["npc_interact", "dialog_completed"]:
				var key := "npc" if n.kind == "npc_interact" else "dialog_id"
				if n.params.get(key) != context.get(key) or n.params.get("task") != context.get("task"): continue
			if n.params.get("once", false) and _state(n.id): continue
			if n.params.get("once", false): local_state[n.id] = true
			var trigger_reason := "游戏开始" if n.kind == "start" else "玩家进入房间 " + str(context.get("room_label", context.get("room", ""))) if n.kind == "room_enter" else "玩家进入触发区域 " + str(context.get("object", "")) if n.kind == "region_enter" else "收到事件 " + str(context.get("key", ""))
			if n.kind == "npc_interact": trigger_reason = "NPC 互动：" + str(context.get("npc", ""))
			if n.kind == "dialog_completed": trigger_reason = "台本完成：" + str(context.get("dialog_id", ""))
			_record(n.id, trigger_reason)
			_emit_event(n.id, "then", context)
	for n in ordered:
		if n.kind != "goal" or _state(str(n.id)) or not _input(str(n.id), "condition", {}):
			continue
		var region: Node = resolver.call(str(n.params.get("object", "")))
		if region == null or not region.has_method("controlled_actor") or region.call("controlled_actor") == null:
			continue
		_set_state(n, true)
		last_reason[n.id] = "玩家已进入区域，且完成条件成立"
		_record(n.id, last_reason[n.id])
		var actor: Node = region.call("controlled_actor")
		_emit_event(n.id, "completed", {"actor": str(actor.get_path())})
	var processed := 0
	while not pending.is_empty() and processed < BUDGET:
		var event: Dictionary = pending.pop_front()
		if not _accept_event(event): continue
		var n := definition.node_by_id(str(event.to))
		processed += 1
		if n.is_empty():
			continue
		var context: Dictionary = event.get("context", {})
		var reason := "事件来自 " + str(event.from)
		match str(n.kind):
			"latch": _set_state(n, true)
			"objective": objective_requested.emit(str(n.params.get("text", "")))
			"checkpoint": checkpoint_requested.emit()
			"branch":
				var yes := _input(n.id, "condition", {})
				local_state["$branch:" + n.id] = yes
				reason = "条件成立" if yes else "条件不成立"
				_emit_event(n.id, "yes" if yes else "no", context)
			"emit_event":
				var next_context := context.duplicate(true)
				next_context["key"] = str(n.params.key)
				queue_trigger("event_received", next_context)
				reason = "事件将在下一物理帧送达：" + str(n.params.key)
				_emit_event(n.id, "then", context)
			"set_switch", "enemy_patrol", "kill_player", "set_visibility", "show_dialog", "task_start", "task_complete", "task_accept", "event_hold", "event_complete":
				var result: Dictionary = action_handler.call(n, context) if action_handler.is_valid() else {"ok": false, "reason": "尚未接入操作接口"}
				reason = str(result.get("reason", ""))
				_emit_event(n.id, "then" if result.get("ok", false) else "failed", context)
			_: reason = _custom_event(n, event)
		_record(n.id, reason)

	overflowed = not pending.is_empty() # Remaining work continues next physics frame.
	refresh_values()

func refresh_values() -> void:
	values.clear()
	for n in definition.nodes:
		if n.kind in ["player_state", "has_item", "source", "constant", "number", "greater", "object", "read_state", "all", "latch"]:
			_value(str(n.id), {})
		elif n.kind == "branch": values[n.id] = local_state.get("$branch:" + n.id, false)

func link_enabled(link: String) -> bool:
	var has_controller := false
	var enabled := true
	for n in definition.nodes:
		if n.kind == "unlock" and n.params.get("link") == link:
			has_controller = true
			enabled = enabled and _input(str(n.id), "enabled", {})
			values[n.id] = enabled
	return enabled if has_controller else true

func capture() -> Dictionary:
	return {"local": local_state.duplicate(true), "pending": pending.duplicate(true), "frame": frame, "reason": last_reason.duplicate(true), "incoming": incoming.duplicate(true), "counts": counts.duplicate(), "started": started}

func restore(data: Dictionary) -> void:
	local_state = data.get("local", {}).duplicate(true)
	pending.assign(data.get("pending", []).duplicate(true))
	frame = int(data.get("frame", 0))
	last_reason = data.get("reason", {}).duplicate(true)
	incoming.assign(data.get("incoming", []).duplicate(true))
	counts = data.get("counts", {}).duplicate()
	started = bool(data.get("started", false))
	refresh_values() # Read only: no effects or event dispatch on restore.

func restore_progress(data: Dictionary) -> bool:
	for id in data:
		var n := definition.node_by_id(str(id))
		if n.is_empty() or not n.kind in ["goal", "latch"] or not n.params.get("persistent", true) or typeof(data[id]) != TYPE_BOOL:
			return false
	persistent = data.duplicate(true)
	pending.clear()
	values.clear()
	return true

func queue_trigger(kind: String, context: Dictionary = {}) -> void:
	if incoming.size() < MAX_QUEUE: incoming.append({"kind": kind, "context": context.duplicate(true)})
	else: last_reason["$budget"] = "触发队列超过 256，已停止追加"

func _record(id: String, reason: String) -> void:
	last_reason[id] = reason
	counts[id] = int(counts.get(id, 0)) + 1
	executed.emit(id, reason)
