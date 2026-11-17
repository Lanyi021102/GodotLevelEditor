@tool
extends RefCounted
const ACCESS := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/state_access.gd")
const DEFINITIONS := {
	"mechanism_state_changed": ["机关状态变化时", "On Mechanism State Changed", "trigger", {"mechanism": "", "from_state": "", "to_state": "", "once": false}],
	"mechanism_interacted": ["机关交互成功时", "On Mechanism Interacted", "trigger", {"mechanism": "", "player_only": true, "once": false}],
	"mechanism_action_finished": ["机关动作完成时", "On Mechanism Action Finished", "trigger", {"mechanism": "", "action": "", "succeeded": true, "once": false}],
	"mechanism_region_enter": ["进入机关感应区域时", "On Mechanism Region Enter", "trigger", {"mechanism": "", "player_only": true, "once": false}],
	"mechanism_region_exit": ["离开机关感应区域时", "On Mechanism Region Exit", "trigger", {"mechanism": "", "player_only": true, "once": false}],
	"mechanism_state": ["检测机关当前状态", "Check Mechanism State", "condition", {"mechanism": "", "state": ""}],
	"wait_mechanism_state": ["等待机关到达状态", "Wait For Mechanism State", "flow", {"mechanism": "", "state": "", "timeout": 0.0, "scope": ""}],
	"mechanism_request_state": ["请求机关改变状态", "Request Mechanism State", "action", {"mechanism": "", "state": ""}],
	"mechanism_action": ["请求机关执行动作", "Request Mechanism Action", "action", {"mechanism": "", "action": ""}],
	"mechanism_set_interaction": ["设置机关交互可用", "Set Mechanism Interaction Enabled", "action", {"mechanism": "", "enabled": true}],
	"mechanism_set_property": ["设置机关属性", "Set Mechanism Property", "action", {"mechanism": "", "property": "locked", "bool_value": false, "number_value": 1.0}],
}
const EVENT := {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}}
const TRIGGER := {"in": {}, "out": {"then": "event"}}
const PORTS := {"mechanism_state_changed": TRIGGER, "mechanism_interacted": TRIGGER, "mechanism_action_finished": TRIGGER, "mechanism_region_enter": TRIGGER, "mechanism_region_exit": TRIGGER, "mechanism_state": {"in": {}, "out": {"value": "bool"}}, "wait_mechanism_state": {"in": {"run": "event", "cancel": "event"}, "out": {"then": "event", "timeout": "event", "failed": "event", "cancelled": "event"}}, "mechanism_request_state": EVENT, "mechanism_action": EVENT, "mechanism_set_interaction": EVENT, "mechanism_set_property": EVENT}

static func is_action(kind: String) -> bool:
	return DEFINITIONS.has(kind) and DEFINITIONS[kind][2] == "action"

static func matches(node: Dictionary, context: Dictionary) -> bool:
	var p: Dictionary = node.params
	if not context.get("references", [context.get("mechanism", "")]).has(p.mechanism): return false
	match str(node.kind):
		"mechanism_state_changed": return (str(p.from_state).is_empty() or p.from_state == context.get("from_state")) and (str(p.to_state).is_empty() or p.to_state == context.get("to_state"))
		"mechanism_action_finished": return (str(p.action).is_empty() or p.action == context.get("action")) and p.succeeded == context.get("succeeded")
		_: return not p.get("player_only", false) or context.get("is_player", false)

static func condition(world: Node, node: Dictionary) -> bool:
	var component := ACCESS.resolve(world, str(node.params.mechanism))
	return component != null and component.get_state() == str(node.params.state)

static func perform(world: Node, node: Dictionary) -> Dictionary:
	var component := ACCESS.resolve(world, str(node.params.mechanism))
	if component == null: return {"ok": false, "reason": "机关实例或组件不存在"}
	match str(node.kind):
		"mechanism_request_state": return component.request_state(str(node.params.state))
		"mechanism_action": return component.perform_action(str(node.params.action))
		"mechanism_set_interaction": return component.set_property_value("interaction_enabled", node.params.enabled)
		"mechanism_set_property": return component.set_property_value(str(node.params.property), node.params.bool_value if node.params.property in ["locked", "interaction_enabled"] else node.params.number_value)
	return {"ok": false, "reason": "未知机关操作"}

static func validate(node: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not DEFINITIONS.has(node.kind): return errors
	var p: Dictionary = node.params
	if str(p.get("mechanism", "")).is_empty(): errors.append(str(node.id) + "：请选择机关实例与组件")
	if node.kind in ["mechanism_state", "wait_mechanism_state", "mechanism_request_state"] and str(p.get("state", "")).is_empty(): errors.append(str(node.id) + "：请选择机关状态")
	if node.kind == "mechanism_action" and str(p.get("action", "")).is_empty(): errors.append(str(node.id) + "：请选择机关动作")
	if node.kind == "mechanism_set_property" and p.get("property", "") not in ["locked", "interaction_enabled", "motion_seconds", "reset_after"]: errors.append(str(node.id) + "：不支持该机关属性")
	return errors

static func validate_bindings(world: Node, node: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not DEFINITIONS.has(node.kind): return errors
	var description := {}
	for target in ACCESS.descriptions(world):
		if target.reference == node.params.get("mechanism", ""): description = target; break
	if description.is_empty():
		var component := ACCESS.resolve(world, str(node.params.get("mechanism", "")))
		if component != null: description = {"states": component.state_names(), "requestable": component.requestable_states(), "actions": component.action_names()}
	if description.is_empty(): errors.append(str(node.id) + "：机关实例或组件引用失效"); return errors
	for key in ["state", "from_state", "to_state"]:
		if node.params.has(key) and not str(node.params[key]).is_empty() and node.params[key] not in description.states: errors.append(str(node.id) + "：机关状态不存在")
	if node.kind == "mechanism_request_state" and node.params.get("state") not in description.requestable: errors.append(str(node.id) + "：该状态不能直接请求")
	if node.params.has("action") and not str(node.params.action).is_empty() and node.params.action not in description.actions: errors.append(str(node.id) + "：机关动作不存在")
	return errors
