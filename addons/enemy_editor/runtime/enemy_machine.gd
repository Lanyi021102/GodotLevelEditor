class_name EnemyMachine
extends RefCounted
## Instance state only. No resource mutation and no side effects during restore.
var definition: EnemyDefinition
var state_id := "patrol"
var timer := 0.0
var last_transition := ""
var last_reason := ""

func configure(source: EnemyDefinition) -> bool:
	if source == null or not source.validate().is_empty():
		return false
	# Freeze a private definition for this run; editing a shared asset cannot alter history.
	definition = source.duplicate(true)
	state_id = definition.initial_state
	timer = float(current().duration)
	last_transition = ""
	last_reason = ""
	return true

func current() -> Dictionary:
	return definition.state_by_id(state_id) if definition != null else {}

func advance(delta: float) -> void:
	timer = maxf(timer - maxf(delta, 0.0), 0.0)

func evaluate(event: String, facts: Dictionary) -> Dictionary:
	if definition == null:
		return {}
	var context := facts.duplicate()
	context["timer"] = timer
	var best: Dictionary = {}
	for edge in definition.transitions:
		if edge.from != state_id or edge.event != event:
			continue
		if not best.is_empty() and int(edge.priority) <= int(best.priority):
			continue
		var matches := true
		for condition in edge.conditions:
			if not _matches(condition, context):
				matches = false
				break
		if matches:
			best = edge
	if not best.is_empty():
		var previous_label := str(current().get("label", state_id))
		state_id = str(best.to)
		timer = float(current().duration)
		last_transition = str(best.id)
		var events := {"perception": "感知更新", "tick": "计时与思考", "noise": "听到噪音", "help": "同伴求援"}
		var facts_labels := {"seen": "看见目标", "has_last_known": "最后位置有效", "alert": "警觉", "timer": "剩余时间"}
		var operators := {"eq": "=", "ne": "≠", "gt": ">", "ge": "≥", "lt": "<", "le": "≤"}
		var reasons := PackedStringArray()
		for condition in best.conditions:
			reasons.append("%s(%s) %s %s" % [facts_labels[condition.fact], context.get(condition.fact), operators[condition.op], condition.value])
		last_reason = "%s → %s · %s · %s" % [previous_label, current().label, events[event], " 且 ".join(reasons)]
	return best

static func _matches(c: Dictionary, facts: Dictionary) -> bool:
	if not facts.has(c.fact):
		return false
	var value: Variant = facts[c.fact]
	match str(c.op):
		"eq": return value == c.value
		"ne": return value != c.value
		"gt": return value > c.value
		"ge": return value >= c.value
		"lt": return value < c.value
		"le": return value <= c.value
	return false

func capture() -> Dictionary:
	return {"state_id": state_id, "timer": timer, "last_transition": last_transition, "last_reason": last_reason}

func restore(data: Dictionary) -> bool:
	var id := str(data.get("state_id", ""))
	if definition == null or definition.state_by_id(id).is_empty():
		return false
	var remaining: Variant = data.get("timer", 0.0)
	if not EnemyDefinition._number(remaining) or not is_finite(float(remaining)):
		return false
	state_id = id
	timer = maxf(float(remaining), 0.0)
	last_transition = str(data.get("last_transition", ""))
	last_reason = str(data.get("last_reason", ""))
	return true
