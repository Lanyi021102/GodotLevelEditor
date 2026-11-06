@tool
extends RefCounted

static func create() -> EnemyDefinition:
	var d := EnemyDefinition.new()
	d.display_name = "守卫 · 巡逻 / 怀疑 / 警戒 / 搜索"
	d.states.assign([
		_state("patrol", "巡逻", "patrol", 2.0, 0.0, 0.0, Vector2(60, 80)),
		_state("suspicious", "怀疑", "investigate", 3.2, 6.0, 70.0, Vector2(400, 80)),
		_state("alert", "警戒", "chase", 4.8, 8.0, 0.0, Vector2(740, 80)),
		_state("search", "搜索", "investigate", 3.2, 6.0, 70.0, Vector2(400, 420)),
	])
	for state in d.states:
		d.layout.nodes[state.id] = state.position
		state.erase("position")
	for id in ["patrol", "suspicious", "search"]:
		d.transitions.append(_edge(id + "_expose", id, "alert", "perception", 100, [_c("alert", "ge", 100.0)], "expose"))
		for event in ["noise", "help"]:
			d.transitions.append(_edge(id + "_" + event, id, "suspicious", event, 50, [_c("has_last_known", "eq", true)]))
	d.transitions.append(_edge("patrol_seen", "patrol", "suspicious", "perception", 20, [_c("seen", "eq", true)]))
	d.transitions.append(_edge("patrol_uneasy", "patrol", "suspicious", "tick", 10, [_c("has_last_known", "eq", true), _c("alert", "gt", 1.0)]))
	d.transitions.append(_edge("suspicious_calm", "suspicious", "patrol", "tick", 10, [_c("alert", "le", 0.5), _c("timer", "le", 0.0)]))
	d.transitions.append(_edge("alert_timeout", "alert", "search", "tick", 10, [_c("timer", "le", 0.0)]))
	d.transitions.append(_edge("search_seen", "search", "suspicious", "tick", 20, [_c("seen", "eq", true)]))
	d.transitions.append(_edge("search_timeout", "search", "patrol", "tick", 10, [_c("timer", "le", 0.0)]))
	return d

static func _state(id: String, label: String, behavior: String, speed: float, duration: float, scan: float, position: Vector2) -> Dictionary:
	return {"id": id, "label": label, "behavior": behavior, "speed": speed, "duration": duration, "scan_degrees": scan, "position": position}

static func _c(fact: String, op: String, value: Variant) -> Dictionary:
	return {"fact": fact, "op": op, "value": value}

static func _edge(id: String, from: String, to: String, event: String, priority: int, conditions: Array, effect := "none") -> Dictionary:
	return {"id": id, "from": from, "to": to, "from_port": EnemyDefinition.OUTPUT_PORT, "to_port": EnemyDefinition.INPUT_PORT, "event": event, "priority": priority, "conditions": conditions, "effect": effect}
