@tool
extends RefCounted
## Task-only schema. Display names, English search names and editable defaults share one source.
const MECHANISMS := preload("res://addons/godot_level_editor_mechanisms/task_nodes.gd")
const DEFINITIONS := {
	"mechanism_state_changed": MECHANISMS.DEFINITIONS["mechanism_state_changed"],
	"mechanism_interacted": MECHANISMS.DEFINITIONS["mechanism_interacted"],
	"mechanism_action_finished": MECHANISMS.DEFINITIONS["mechanism_action_finished"],
	"mechanism_region_enter": MECHANISMS.DEFINITIONS["mechanism_region_enter"],
	"mechanism_region_exit": MECHANISMS.DEFINITIONS["mechanism_region_exit"],
	"mechanism_state": MECHANISMS.DEFINITIONS["mechanism_state"],
	"wait_mechanism_state": MECHANISMS.DEFINITIONS["wait_mechanism_state"],
	"mechanism_request_state": MECHANISMS.DEFINITIONS["mechanism_request_state"],
	"mechanism_action": MECHANISMS.DEFINITIONS["mechanism_action"],
	"mechanism_set_interaction": MECHANISMS.DEFINITIONS["mechanism_set_interaction"],
	"mechanism_set_property": MECHANISMS.DEFINITIONS["mechanism_set_property"],

	"region_exit": ["离开区域", "On Region Exit", "trigger", {"object": "", "once": false}],
	"object_interacted": ["物件交互时", "On Object Interacted", "trigger", {"object": "", "once": false}],
	"state_changed": ["角色状态变化时", "On Actor State Changed", "trigger", {"actor": "", "key": "ready", "expected": true, "once": false}],
	"has_equipped": ["检查角色穿着", "Check Equipped Item", "condition", {"actor": "", "slot": "body", "key": "uniform"}],
	"actor_state": ["检查角色状态", "Check Actor State", "condition", {"actor": "", "key": "ready", "expected": true}],
	"any": ["任一条件成立", "Any Condition", "condition", {}],
	"not": ["条件取反", "Not", "condition", {}],
	"compare": ["比较数值", "Compare Numbers", "condition", {"operator": "=="}],
	"get_variable": ["读取布尔变量", "Get Boolean Variable", "state", {"key": "flag", "fallback": false}],
	"get_number": ["读取数值变量", "Get Number Variable", "data", {"key": "count", "fallback": 0.0}],
	"set_variable": ["设置变量", "Set Variable", "action", {"key": "flag", "type": "bool", "bool_value": true, "number_value": 0.0}],
	"change_item": ["增减背包物件", "Change Inventory Item", "action", {"actor": "", "key": "key", "amount": 1}],
	"equip_item": ["设置角色穿着", "Set Equipped Item", "action", {"actor": "", "slot": "body", "key": "uniform"}],
	"set_actor_state": ["设置角色状态", "Set Actor State", "action", {"actor": "", "key": "ready", "enabled": true}],
	"delay": ["等待时长", "Delay", "flow", {"seconds": 1.0, "scope": ""}],
	"timer": ["计时器", "Timer", "flow", {"seconds": 30.0, "scope": ""}],
	"wait_until": ["等待条件成立", "Wait Until", "flow", {"timeout": 0.0, "scope": ""}],
	"wait_event": ["等待事件", "Wait For Event", "flow", {"key": "ready", "scope": ""}],
	"parallel": ["并行执行", "Parallel", "flow", {"scope": ""}],
	"wait_all": ["等待全部完成", "Wait All", "flow", {}],
	"wait_any": ["等待任一完成", "Wait Any", "flow", {"cancel_others": false}],
	"counter": ["计数器", "Counter", "flow", {"target": 3}],
	"gate": ["流程开关", "Gate", "flow", {"opened": true}],
	"cancel_branch": ["取消分支", "Cancel Branch", "flow", {"scope": "parallel:a"}],
	"objective_start": ["激活子目标", "Activate Objective", "action", {"key": "objective", "text": "新目标", "optional": false}],
	"objective_complete": ["完成子目标", "Complete Objective", "action", {"key": "objective"}],
	"objective_fail": ["子目标失败", "Fail Objective", "action", {"key": "objective"}],
	"objective_state": ["检查子目标状态", "Check Objective State", "condition", {"key": "objective", "status": "completed"}],
	"task_fail": ["任务失败", "Fail Task", "action", {"task": "", "reason": "任务条件未达成"}],
	"checkpoint_save": ["保存检查点", "Save Checkpoint", "action", {}],
	"checkpoint_restore": ["恢复检查点", "Restore Checkpoint", "action", {}],
	"run_subgraph": ["执行子图", "Run Subgraph", "flow", {"graph_path": "", "scope": ""}],
	"subgraph_end": ["结束子图", "End Subgraph", "action", {"success": true}],
}
const EVENT := {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}}
const PORTS := {
	"mechanism_state_changed": MECHANISMS.PORTS["mechanism_state_changed"],
	"mechanism_interacted": MECHANISMS.PORTS["mechanism_interacted"],
	"mechanism_action_finished": MECHANISMS.PORTS["mechanism_action_finished"],
	"mechanism_region_enter": MECHANISMS.PORTS["mechanism_region_enter"],
	"mechanism_region_exit": MECHANISMS.PORTS["mechanism_region_exit"],
	"mechanism_state": MECHANISMS.PORTS["mechanism_state"],
	"wait_mechanism_state": MECHANISMS.PORTS["wait_mechanism_state"],
	"mechanism_request_state": MECHANISMS.PORTS["mechanism_request_state"],
	"mechanism_action": MECHANISMS.PORTS["mechanism_action"],
	"mechanism_set_interaction": MECHANISMS.PORTS["mechanism_set_interaction"],
	"mechanism_set_property": MECHANISMS.PORTS["mechanism_set_property"],

	"region_exit": {"in": {}, "out": {"then": "event"}},
	"object_interacted": {"in": {}, "out": {"then": "event"}},
	"state_changed": {"in": {}, "out": {"then": "event"}},
	"has_equipped": {"in": {}, "out": {"value": "bool"}},
	"actor_state": {"in": {}, "out": {"value": "bool"}},
	"objective_state": {"in": {}, "out": {"value": "bool"}},
	"any": {"in": {"a": "bool", "b": "bool"}, "out": {"value": "bool"}},
	"not": {"in": {"condition": "bool"}, "out": {"value": "bool"}},
	"compare": {"in": {"a": "number", "b": "number"}, "out": {"value": "bool"}},
	"get_variable": {"in": {}, "out": {"value": "bool"}},
	"get_number": {"in": {}, "out": {"value": "number"}},
	"set_variable": EVENT, "change_item": EVENT, "equip_item": EVENT, "set_actor_state": EVENT,
	"objective_start": EVENT, "objective_complete": EVENT, "objective_fail": EVENT,
	"task_fail": EVENT, "checkpoint_save": EVENT, "checkpoint_restore": EVENT, "subgraph_end": EVENT,
	"delay": {"in": {"run": "event", "cancel": "event"}, "out": {"then": "event", "cancelled": "event"}},
	"timer": {"in": {"run": "event", "cancel": "event"}, "out": {"then": "event", "cancelled": "event", "remaining": "number"}},
	"wait_until": {"in": {"run": "event", "condition": "bool", "cancel": "event"}, "out": {"then": "event", "timeout": "event", "cancelled": "event"}},
	"wait_event": {"in": {"run": "event", "cancel": "event"}, "out": {"then": "event", "cancelled": "event"}},
	"parallel": {"in": {"run": "event"}, "out": {"a": "event", "b": "event", "c": "event", "d": "event"}},
	"wait_all": {"in": {"a": "event", "b": "event", "c": "event", "d": "event", "reset": "event"}, "out": {"then": "event"}},
	"wait_any": {"in": {"a": "event", "b": "event", "c": "event", "d": "event", "reset": "event"}, "out": {"then": "event"}},
	"counter": {"in": {"run": "event", "reset": "event"}, "out": {"then": "event", "reached": "event", "value": "number"}},
	"gate": {"in": {"run": "event", "open": "event", "close": "event"}, "out": {"then": "event", "closed": "event"}},
	"cancel_branch": {"in": {"run": "event"}, "out": {"then": "event"}},
	"run_subgraph": {"in": {"run": "event", "cancel": "event"}, "out": {"then": "event", "failed": "event", "cancelled": "event"}},
}
const FIELD_LABELS := {
	"actor": "角色对象 ID（留空为玩家）", "key": "标识", "slot": "穿着部位", "amount": "物件数量／增减量", "expected": "期望状态",
	"seconds": "时长（秒）", "timeout": "超时（秒，0 为不限）", "scope": "分支组名", "target": "目标次数", "opened": "初始允许通过",
	"cancel_others": "完成后取消同组其他分支", "fallback": "默认值", "type": "变量类型", "bool_value": "布尔值", "number_value": "数值",
	"once": "本次运行只触发一次", "enabled": "状态值", "optional": "可选目标", "status": "目标状态", "graph_path": "子图资源路径", "success": "子图成功", "reason": "失败原因", "text": "目标文字", "operator": "比较方式",
}

static func english_name(kind: String) -> String:
	if DEFINITIONS.has(kind): return str(DEFINITIONS[kind][1])
	return str({"has_item": "Check Inventory Item", "all": "All Conditions", "latch": "Event Latch", "checkpoint": "Save Progress", "source": "Get Mechanism State", "read_state": "Get Object State", "region_enter": "On Region Enter", "branch": "Branch", "objective": "Update Objective"}.get(kind, kind.replace("_", " ").capitalize()))

static func defaults(kind: String) -> Dictionary:
	return DEFINITIONS[kind][3].duplicate(true) if DEFINITIONS.has(kind) else {}

static func validate_node(n: Dictionary) -> PackedStringArray:
	var errors := MECHANISMS.validate(n)
	var p: Dictionary = n.params
	var kind: String = n.kind
	for key in defaults(kind):
		if not p.has(key): errors.append(str(n.id) + "：缺少参数 " + key)
		elif typeof(p[key]) != typeof(defaults(kind)[key]) and not (defaults(kind)[key] is float and (p[key] is int or p[key] is float)):
			errors.append(str(n.id) + "：参数类型无效 " + key)
	if not errors.is_empty(): return errors
	for key in ["seconds", "timeout", "number_value", "fallback"]:
		if p.has(key) and (p[key] is float or p[key] is int) and not is_finite(float(p[key])): errors.append(str(n.id) + "：数值必须有限")
	for key in ["seconds", "timeout"]:
		if p.has(key) and (float(p[key]) < 0 or float(p[key]) > 86400): errors.append(str(n.id) + "：时长必须在 0 到 86400 秒之间")
	if kind == "counter" and int(p.target) < 1: errors.append(str(n.id) + "：计数目标至少为 1")
	if kind == "set_variable" and p.type not in ["bool", "number"]: errors.append(str(n.id) + "：未知变量类型")
	if kind == "compare" and p.operator not in ["==", "!=", ">", ">=", "<", "<="]: errors.append(str(n.id) + "：未知比较方式")
	if kind == "objective_state" and p.status not in ["active", "completed", "failed"]: errors.append(str(n.id) + "：未知目标状态")
	if p.has("key") and str(p.key).strip_edges().is_empty() and kind != "equip_item": errors.append(str(n.id) + "：标识不能为空")
	if kind in ["region_exit", "object_interacted"] and str(p.object).is_empty(): errors.append(str(n.id) + "：缺少场景对象")
	if kind == "cancel_branch" and str(p.scope).strip_edges().is_empty(): errors.append(str(n.id) + "：取消分支必须指定作用域")
	if kind == "run_subgraph" and (not str(p.graph_path).begins_with("res://") or not str(p.graph_path).ends_with(".tres") or not FileAccess.file_exists(p.graph_path)): errors.append(str(n.id) + "：子图资源不存在")
	return errors
