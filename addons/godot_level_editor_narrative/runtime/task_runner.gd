extends "res://addons/godot_level_editor/runtime/event_runner.gd"
const MECHANISMS := preload("res://addons/godot_level_editor_mechanisms/task_nodes.gd")
## Task-local asynchronous work. Nothing sleeps the engine or mutates authoring resources.
var variables: Dictionary = {}
var flow: Dictionary = {}
var waits: Dictionary = {}
var children: Dictionary = {}
var cancelled: Dictionary = {}
var completed := false
var succeeded := true
var depth := 0
var task_id := ""

func configure(graph: GodotLevelEditorLevelGraph, lookup: Callable, actions: Callable = Callable(), conditions: Callable = Callable()) -> bool:
	flow.clear(); waits.clear(); children.clear(); cancelled.clear()
	completed = false
	succeeded = true
	return super.configure(graph, lookup, actions, conditions)

func _child_action(n: Dictionary, context: Dictionary, table: String) -> Dictionary:
	var message := context.duplicate(true)
	message["_dialogue_xlsx"] = table
	return action_handler.call(n, message) if action_handler.is_valid() else {"ok": false}

func queue_trigger(kind: String, context: Dictionary = {}) -> void:
	super.queue_trigger(kind, context)
	for child in children.values():
		if not child.runner.completed: child.runner.queue_trigger(kind, context)

func active_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = definition.nodes.duplicate(true)
	for child in children.values(): result.append_array(child.runner.active_nodes())
	return result

func _bind_child(child: RefCounted) -> void:
	child.variables = variables
	child.depth = depth + 1
	child.task_id = task_id
	for n in child.definition.nodes:
		if n.params.has("task") and not task_id.is_empty(): n.params.task = task_id

func _value(id: String, visiting: Dictionary) -> Variant:
	if visiting.has(id): return false
	var n := definition.node_by_id(id)
	if n.is_empty(): return false
	var seen := visiting.duplicate()
	seen[id] = true
	var p: Dictionary = n.params
	var result: Variant
	match str(n.kind):
		"any": result = _input(id, "a", seen) or _input(id, "b", seen)
		"not": result = not _input(id, "condition", seen)
		"has_equipped", "actor_state", "objective_state", "mechanism_state": result = condition_handler.call(n) if condition_handler.is_valid() else false
		"get_variable": result = variables.get(p.key, p.fallback) == true
		"get_number":
			var v: Variant = variables.get(p.key, p.fallback)
			result = float(v) if v is float or v is int else float(p.fallback)
		"timer": result = float(waits.get(id, {}).get("remaining", 0.0))
		"counter": result = int(flow.get(id, {}).get("count", 0))
		"compare":
			var a := float(_raw_input(id, "a", seen, 0.0))
			var b := float(_raw_input(id, "b", seen, 0.0))
			match str(p.operator):
				"==": result = a == b
				"!=": result = a != b
				">": result = a > b
				">=": result = a >= b
				"<": result = a < b
				_: result = a <= b
		_: return super._value(id, visiting)
	values[id] = result
	return result

func refresh_values() -> void:
	super.refresh_values()
	for n in definition.nodes:
		if n.kind in ["any", "not", "has_equipped", "actor_state", "objective_state", "get_variable", "get_number", "timer", "counter", "compare", "mechanism_state"]: _value(n.id, {})

func _matches_trigger(n: Dictionary, context: Dictionary) -> bool:
	if MECHANISMS.DEFINITIONS.has(n.kind): return MECHANISMS.matches(n, context)
	if n.kind == "state_changed": return n.params.get("actor", "") == context.get("actor_id", "") and n.params.key == context.get("key") and n.params.expected == context.get("value")
	return true

func _scope_cancelled(scope: String) -> bool:
	for key in cancelled:
		if scope == key or scope.begins_with(str(key) + ":"): return true
	return false

func _accept_event(event: Dictionary) -> bool:
	return not completed and not _scope_cancelled(str(event.get("context", {}).get("_scope", "")))

func cancel_scope(scope: String) -> void:
	if scope.is_empty(): return
	cancelled[scope] = true
	for id in waits.keys():
		var group := str(waits[id].context.get("_scope", ""))
		if _scope_cancelled(group): waits.erase(id)
	for id in children.keys():
		if _scope_cancelled(str(children[id].context.get("_scope", ""))): children.erase(id)

func _advance_waits(delta: float) -> void:
	if completed: return
	for id in waits.keys():
		var w: Dictionary = waits[id]
		var n := definition.node_by_id(id)
		var output := ""
		match str(n.kind):
			"wait_mechanism_state":
				var component := MECHANISMS.ACCESS.resolve_with(resolver, str(n.params.mechanism))
				if component == null or str(n.params.state) not in component.state_names(): output = "failed"
				elif condition_handler.is_valid() and condition_handler.call(n): output = "then"
				elif n.params.timeout > 0:
					w.remaining -= delta
					if w.remaining <= 0: output = "timeout"
			"delay", "timer":
				w.remaining = maxf(0, float(w.remaining) - delta)
				if w.remaining <= 0: output = "then"
			"wait_until":
				if _input(id, "condition", {}): output = "then"
				elif n.params.timeout > 0:
					w.remaining -= delta
					if w.remaining <= 0: output = "timeout"
			"wait_event":
				for trigger in incoming:
					if trigger.kind == "event_received" and trigger.context.get("key") == n.params.key: output = "then"; break
		if not output.is_empty():
			waits.erase(id)
			_record(id, "等待结束：" + output)
			_emit_event(id, output, w.context)
	for id in children.keys():
		if not children.has(id): continue
		var child: Dictionary = children[id]
		child.runner.tick(delta)
		if child.runner.completed:
			children.erase(id)
			_emit_event(id, "then" if child.runner.succeeded else "failed", child.context)

func _custom_event(n: Dictionary, event: Dictionary) -> String:
	var p: Dictionary = n.params
	var context: Dictionary = event.get("context", {}).duplicate(true)
	var port := str(event.port)
	if MECHANISMS.is_action(str(n.kind)):
		var result: Dictionary = action_handler.call(n, context) if action_handler.is_valid() else {"ok": false, "reason": "未接入机关动作"}
		_emit_event(n.id, "then" if result.get("ok", false) else "failed", context)
		return str(result.get("reason", ""))
	match str(n.kind):
		"wait_mechanism_state":
			if port == "cancel":
				if waits.has(n.id): waits.erase(n.id); _emit_event(n.id, "cancelled", context)
			elif waits.has(n.id): return "等待已启动"
			else:
				var component := MECHANISMS.ACCESS.resolve_with(resolver, str(p.mechanism))
				if component == null or str(p.state) not in component.state_names(): _emit_event(n.id, "failed", context); return "机关或状态不存在"
				if condition_handler.is_valid() and condition_handler.call(n): _emit_event(n.id, "then", context)
				else:
					if not str(p.scope).is_empty(): context._scope = p.scope
					waits[n.id] = {"remaining": float(p.timeout), "context": context}
		"set_variable":
			variables[p.key] = p.bool_value if p.type == "bool" else p.number_value
			_emit_event(n.id, "then", context)
		"delay", "timer", "wait_until", "wait_event":
			if port == "cancel":
				if waits.has(n.id): waits.erase(n.id); _emit_event(n.id, "cancelled", context)
			elif waits.has(n.id): return "等待已启动，忽略重复执行"
			else:
				if not str(p.get("scope", "")).is_empty(): context._scope = p.scope
				if n.kind == "wait_until" and _input(n.id, "condition", {}): _emit_event(n.id, "then", context)
				else: waits[n.id] = {"remaining": float(p.get("seconds", p.get("timeout", 0.0))), "context": context}
		"parallel":
			var parent_scope := str(context.get("_scope", ""))
			var group := str(p.scope) if not str(p.scope).is_empty() else str(n.id)
			var scope := (parent_scope + ":" if not parent_scope.is_empty() else "") + group
			for key in cancelled.keys():
				if key == scope or str(key).begins_with(scope + ":"): cancelled.erase(key)
			for output in ["a", "b", "c", "d"]:
				var branch := context.duplicate(true)
				var stack: Array = branch.get("_flow_stack", []).duplicate(true)
				stack.append({"parent_scope": parent_scope, "parent_parallel": str(context.get("_parallel", ""))})
				branch._flow_stack = stack
				branch._scope = scope + ":" + output
				branch._parallel = scope
				_emit_event(n.id, output, branch)
		"wait_all", "wait_any":
			if port == "reset": flow.erase(n.id); return "已重置汇合"
			var state: Dictionary = flow.get(n.id, {"seen": {}, "done": false})
			if state.done: return "汇合已完成，忽略重复输入"
			state.seen[port] = true
			var required := {}
			for edge in definition.edges:
				if edge.to == n.id and edge.to_port != "reset": required[edge.to_port] = true
			if n.kind == "wait_any" or state.seen.size() >= required.size():
				state.done = true
				if n.kind == "wait_any" and p.cancel_others and context.has("_parallel"):
					var winning := str(context.get("_scope", ""))
					for branch in ["a", "b", "c", "d"]:
						var scope: String = str(context._parallel) + ":" + str(branch)
						if winning != scope: cancel_scope(scope)
				var stack: Array = context.get("_flow_stack", []).duplicate(true)
				if not stack.is_empty():
					var parent: Dictionary = stack.pop_back()
					context._flow_stack = stack
					context._scope = parent.parent_scope
					context._parallel = parent.parent_parallel
				else:
					context.erase("_scope")
					context.erase("_parallel")
				_emit_event(n.id, "then", context)
			flow[n.id] = state
		"counter":
			var count := 0 if port == "reset" else int(flow.get(n.id, {}).get("count", 0)) + 1
			flow[n.id] = {"count": count}
			if port != "reset":
				_emit_event(n.id, "then", context)
				if count == p.target: _emit_event(n.id, "reached", context)
		"gate":
			var opened: bool = flow.get(n.id, {}).get("opened", p.opened)
			if port in ["open", "close"]: flow[n.id] = {"opened": port == "open"}
			else: _emit_event(n.id, "then" if opened else "closed", context)
		"cancel_branch": cancel_scope(p.scope); _emit_event(n.id, "then", context)
		"run_subgraph":
			if port == "cancel":
				if children.has(n.id): children.erase(n.id); _emit_event(n.id, "cancelled", context)
			elif children.has(n.id): return "子图正在执行"
			elif depth >= 8: _emit_event(n.id, "failed", context); return "子图深度超过 8"
			else:
				var graph: Resource = load(p.graph_path)
				var child: RefCounted = get_script().new()
				if graph == null or not graph.has_method("load_dialogue") or not child.configure(graph, resolver, _child_action.bind(graph.table_file()), condition_handler): _emit_event(n.id, "failed", context); return "子图校验失败"
				_bind_child(child)
				if not str(p.scope).is_empty(): context._scope = p.scope
				children[n.id] = {"runner": child, "context": context}
		"subgraph_end":
			if depth == 0:
				_emit_event(n.id, "failed", context)
				return "结束子图仅用于子图实例"
			completed = true
			succeeded = p.success
			waits.clear(); children.clear(); pending.clear(); incoming.clear()
		"checkpoint_save":
			# Capture after queuing continuation; restore resumes after this node.
			_emit_event(n.id, "then", context)
			var result: Dictionary = action_handler.call(n, context) if action_handler.is_valid() else {"ok": false}
			if not result.get("ok", false):
				pending = pending.filter(func(e: Dictionary): return e.from != n.id)
				_emit_event(n.id, "failed", context)
		"change_item", "equip_item", "set_actor_state", "objective_start", "objective_complete", "objective_fail", "task_fail", "checkpoint_restore":
			var result: Dictionary = action_handler.call(n, context) if action_handler.is_valid() else {"ok": false, "reason": "未接入任务动作"}
			if n.kind == "checkpoint_restore" and result.get("ok", false):
				completed = true; pending.clear(); waits.clear(); children.clear()
			else: _emit_event(n.id, "then" if result.get("ok", false) else "failed", context)
			return str(result.get("reason", ""))
		_: return "不支持的任务节点"
	return "已执行：" + str(n.kind)

func capture() -> Dictionary:
	var data := super.capture()
	data["persistent"] = persistent.duplicate(true)
	data["flow"] = flow.duplicate(true)
	data["waits"] = waits.duplicate(true)
	data["cancelled"] = cancelled.duplicate(true)
	data["completed"] = completed
	data["succeeded"] = succeeded
	data["children"] = {}
	for id in children: data.children[id] = {"context": children[id].context.duplicate(true), "state": children[id].runner.capture()}
	return data

func restore(data: Dictionary) -> void:
	flow = data.get("flow", {}).duplicate(true)
	waits = data.get("waits", {}).duplicate(true)
	cancelled = data.get("cancelled", {}).duplicate(true)
	persistent = data.get("persistent", {}).duplicate(true)
	completed = bool(data.get("completed", false))
	succeeded = bool(data.get("succeeded", true))
	children.clear()
	for id in data.get("children", {}):
		var n := definition.node_by_id(id)
		if n.is_empty() or n.kind != "run_subgraph" or depth >= 8: continue
		var child: RefCounted = get_script().new()
		var graph: Resource = load(n.params.graph_path)
		if child.configure(graph, resolver, _child_action.bind(graph.table_file()), condition_handler):
			_bind_child(child)
			child.restore(data.children[id].state)
			children[id] = {"runner": child, "context": data.children[id].context.duplicate(true)}
	super.restore(data)
