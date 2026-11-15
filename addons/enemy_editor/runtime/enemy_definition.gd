@tool
class_name EnemyDefinition
extends Resource
## Authoring data only. Runtime instances never write to this resource.
const VERSION := 1
const INPUT_PORT := "state_enter"
const OUTPUT_PORT := "state_exit"
const BEHAVIORS := ["patrol", "investigate", "chase", "idle"]
const EVENTS := ["perception", "tick", "noise", "help"]
const FACTS := {"seen": TYPE_BOOL, "has_last_known": TYPE_BOOL, "alert": TYPE_FLOAT, "timer": TYPE_FLOAT}
const OPS := ["eq", "ne", "gt", "ge", "lt", "le"]
const PARAM_DEFAULTS := {"alert_rate": 100.0, "alert_decay": 40.0, "noise_alert": 25.0, "expose_penalty": 25.0, "help_radius": 12.0, "waypoint_wait": 1.5}

@export var schema_version := VERSION
@export var display_name := "守卫"
@export var initial_state := "patrol"
@export var states: Array[Dictionary] = []
@export var transitions: Array[Dictionary] = []
@export var parameters: Dictionary = PARAM_DEFAULTS.duplicate()
## Layout is editor-only; it does not determine evaluation order or world position.
@export var layout: Dictionary = {"nodes": {}, "scroll": Vector2.ZERO, "zoom": 1.0}
## Optional model/rig/motion configuration; null preserves legacy scenes.
@export var appearance: Resource

func state_by_id(id: String) -> Dictionary:
	for entry in states:
		if entry.get("id", "") == id:
			return entry
	return {}

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != VERSION:
		errors.append("不支持的定义版本：%s" % schema_version)
	if appearance != null:
		if appearance.get_script() != preload("res://addons/enemy_editor/appearance_data.gd"): errors.append("NPC 外观资源类型无效。")
		else: errors.append_array(appearance.validate())
	var ids: Array[String] = []
	for s in states:
		var id := str(s.get("id", ""))
		if not id.is_valid_identifier() or ids.has(id):
			errors.append("状态 ID 必须唯一且为有效标识符：" + id)
		ids.append(id)
		if str(s.get("label", "")).strip_edges().is_empty():
			errors.append(id + "：缺少显示名称")
		if not BEHAVIORS.has(s.get("behavior", "")):
			errors.append(id + "：未知行为")
		for key in ["speed", "duration", "scan_degrees"]:
			if not _number(s.get(key)) or not is_finite(float(s.get(key, 0))) or float(s.get(key, -1)) < 0:
				errors.append(id + "：参数必须为有限非负数 " + key)

	if not ids.has(initial_state):
		errors.append("初始状态不存在")
	var edge_ids: Array[String] = []
	for t in transitions:
		var id := str(t.get("id", ""))
		if not id.is_valid_identifier() or edge_ids.has(id):
			errors.append("转换 ID 必须唯一：" + id)
		edge_ids.append(id)
		if not ids.has(str(t.get("from", ""))) or not ids.has(str(t.get("to", ""))):
			errors.append(id + "：转换端点不存在")
		if t.get("from_port", "") != OUTPUT_PORT or t.get("to_port", "") != INPUT_PORT:
			errors.append(id + "：状态转换端口无效或类型不匹配")
		if not EVENTS.has(t.get("event", "")):
			errors.append(id + "：事件无效")
		if typeof(t.get("priority")) != TYPE_INT:
			errors.append(id + "：优先级必须为整数")
		if not ["none", "expose"].has(t.get("effect", "")):
			errors.append(id + "：入场效果无效")
		if not t.get("conditions") is Array or (t.get("conditions", []) as Array).is_empty():
			errors.append(id + "：至少需要一个条件")
			continue
		for c in t.conditions:
			if not c is Dictionary:
				errors.append(id + "：条件格式无效")
				continue
			var fact := str(c.get("fact", ""))
			var op := str(c.get("op", ""))
			if not FACTS.has(fact) or not OPS.has(op):
				errors.append(id + "：条件事实或比较符无效")
			elif FACTS[fact] == TYPE_BOOL:
				if typeof(c.get("value")) != TYPE_BOOL or not ["eq", "ne"].has(op):
					errors.append(id + "：布尔条件只能使用等于/不等于和布尔值")
			elif not _number(c.get("value")) or not is_finite(float(c.get("value", 0))):
				errors.append(id + "：条件值必须为有限数值")
	for key in PARAM_DEFAULTS:
		if not _number(parameters.get(key)) or not is_finite(float(parameters.get(key, 0))) or float(parameters.get(key, -1)) < 0:
			errors.append("感知参数无效：" + key)
	if not layout.get("nodes") is Dictionary or not layout.get("scroll") is Vector2 or not (layout.get("scroll", Vector2.ZERO) as Vector2).is_finite() or not _number(layout.get("zoom")) or not is_finite(float(layout.get("zoom", 1))) or float(layout.get("zoom", 0)) <= 0:
		errors.append("画布视图无效")
	else:
		for id in layout.nodes:
			if not ids.has(str(id)) or not layout.nodes[id] is Vector2 or not (layout.nodes[id] as Vector2).is_finite():
				errors.append("节点布局引用无效：" + str(id))
	return errors

func warnings() -> PackedStringArray:
	var result := PackedStringArray()
	var reached: Array[String] = [initial_state]
	for _i in states.size():
		for t in transitions:
			if reached.has(str(t.get("from", ""))) and not reached.has(str(t.get("to", ""))):
				reached.append(str(t.get("to", "")))
	for s in states:
		if not reached.has(str(s.get("id", ""))):
			result.append("不可达状态：" + str(s.get("id", "")))
	var seen := {}
	for t in transitions:
		var key := "%s/%s/%s" % [t.get("from"), t.get("event"), t.get("priority")]
		if seen.has(key):
			result.append("同优先级按列表顺序：" + key)
		seen[key] = true
	return result

static func _number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
