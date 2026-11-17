@tool
extends RefCounted
## Port IDs are stable; labels and GraphNode slot indices are presentation only.
const BOOL := 1
const NUMBER := 2
const OBJECT := 3
const EVENT := 4
const COMPONENT_KINDS := ["double_door", "single_door", "pressure_plate", "button", "lift_platform"]
const ROTATING_DOOR_KINDS := ["single_door", "double_door", "door_leaf", "door_animation", "door_state"]
const LEGACY_DOOR_KINDS := ["door", "sliding_door", "hinged_door"]
const COMPATIBILITY_KINDS := ["lever", "plate", "door", "toggle_switch", "sliding_door", "hinged_door", "terminal", "set_lever"]
const KINDS := {
	"single_door": {"title": "2×3 单开门", "in": [], "out": [["value", OBJECT]], "binding": "rotating_door"},
	"double_door": {"title": "4×3 双开门", "in": [], "out": [["value", OBJECT]], "binding": "rotating_door"},
	"door_leaf": {"title": "旋转门扇", "in": [["frame", OBJECT]], "out": [["value", OBJECT]], "binding": "rotating_door"},
	"door_animation": {"title": "旋转动画 · 0° ↔ 90°", "in": [["trigger", EVENT], ["leaf", OBJECT]], "out": [["success", EVENT], ["failed", EVENT], ["completed", EVENT], ["value", OBJECT]], "binding": "rotating_door"},
	"door_state": {"title": "门状态", "in": [["target", OBJECT]], "out": [["value", BOOL], ["entered", EVENT]], "binding": "rotating_door"},
	"button": {"title": "按钮组件", "in": [], "out": [["value", BOOL]], "binding": "button"},
	"toggle_switch": {"title": "拉杆组件", "in": [], "out": [["value", BOOL]], "binding": "toggle_switch"},
	"pressure_plate": {"title": "压力板组件", "in": [], "out": [["value", BOOL]], "binding": "pressure_plate"},
	"sliding_door": {"title": "滑动门组件", "in": [], "out": [["value", BOOL]], "binding": "sliding_door"},
	"hinged_door": {"title": "旋转门组件", "in": [], "out": [["value", BOOL]], "binding": "hinged_door"},
	"lift_platform": {"title": "升降台组件", "in": [], "out": [["value", BOOL]], "binding": "lift_platform"},
	"terminal": {"title": "交互终端组件", "in": [], "out": [["value", BOOL]], "binding": "terminal"},
	"state_is": {"title": "检测机关当前状态", "in": [], "out": [["value", BOOL]], "binding": "stateful"},
	"interacted": {"title": "交互成功时", "in": [], "out": [["fired", EVENT]], "binding": "stateful"},
	"state_changed": {"title": "机关状态变化时", "in": [], "out": [["fired", EVENT]], "binding": "stateful"},
	"state_entered": {"title": "进入指定状态时", "in": [], "out": [["fired", EVENT]], "binding": "stateful"},
	"state_exited": {"title": "退出指定状态时", "in": [], "out": [["fired", EVENT]], "binding": "stateful"},
	"action_finished": {"title": "机关动作完成时", "in": [], "out": [["fired", EVENT]], "binding": "stateful"},
	"region_entered": {"title": "进入机关感应区域时", "in": [], "out": [["fired", EVENT]], "binding": "stateful"},
	"region_exited": {"title": "离开机关感应区域时", "in": [], "out": [["fired", EVENT]], "binding": "stateful"},
	"request_state": {"title": "请求机关改变状态", "in": [["trigger", EVENT]], "out": [["success", EVENT], ["failed", EVENT]], "binding": "stateful"},
	"perform_action": {"title": "请求机关执行动作", "in": [["trigger", EVENT]], "out": [["success", EVENT], ["failed", EVENT]], "binding": "stateful"},
	"set_interaction": {"title": "设置机关交互可用", "in": [["trigger", EVENT]], "out": [["success", EVENT], ["failed", EVENT]], "binding": "stateful"},
	"set_property": {"title": "设置机关属性", "in": [["trigger", EVENT]], "out": [["success", EVENT], ["failed", EVENT]], "binding": "stateful"},
	"branch": {"title": "如果条件成立", "in": [["trigger", EVENT], ["condition", BOOL]], "out": [["yes", EVENT], ["no", EVENT]]},
	"lever": {"title": "拉杆状态", "in": [], "out": [["value", BOOL]], "binding": "lever"},
	"plate": {"title": "压力板状态", "in": [], "out": [["value", BOOL]], "binding": "plate"},
	"door": {"title": "门目标开合", "in": [["powered", BOOL]], "out": [], "binding": "door"},
	"and": {"title": "AND · 同时满足", "in": [["a", BOOL], ["b", BOOL]], "out": [["value", BOOL]]},
	"or": {"title": "OR · 任一满足", "in": [["a", BOOL], ["b", BOOL]], "out": [["value", BOOL]]},
	"not": {"title": "NOT · 取反", "in": [["value", BOOL]], "out": [["value", BOOL]]},
	"bool": {"title": "布尔常量", "in": [], "out": [["value", BOOL]]},
	"number": {"title": "数值常量", "in": [], "out": [["value", NUMBER]]},
	"greater": {"title": "数值大于", "in": [["a", NUMBER], ["b", NUMBER]], "out": [["value", BOOL]]},
	"object": {"title": "对象引用", "in": [], "out": [["value", OBJECT]], "binding": "power"},
	"read_power": {"title": "读取对象供电", "in": [["target", OBJECT]], "out": [["value", BOOL]]},
	"rising": {"title": "布尔上升沿 → 事件", "in": [["value", BOOL]], "out": [["fired", EVENT]]},
	"delay": {"title": "事件延迟", "in": [["trigger", EVENT]], "out": [["fired", EVENT]]},
	"set_lever": {"title": "事件 → 设置拉杆", "in": [["trigger", EVENT]], "out": [], "binding": "lever"},
}
const TYPE_NAMES := {BOOL: "布尔状态", NUMBER: "数值", OBJECT: "对象引用", EVENT: "一次事件"}
const TYPE_TAGS := {BOOL: "布尔", NUMBER: "数值", OBJECT: "对象", EVENT: "事件"}
const PORT_LABELS := {"success": "已接受", "failed": "失败", "condition": "条件", "yes": "成立", "no": "不成立", "value": "值", "powered": "目标", "target": "对象", "fired": "触发", "trigger": "事件", "a": "A", "b": "B"}
const TYPE_COLORS := {BOOL: Color("64cbb5"), NUMBER: Color("a5bbef"), OBJECT: Color("e3b46c"), EVENT: Color("eeeeee")}

static func uid(prefix: String) -> String:
	return prefix + "_" + Crypto.new().generate_random_bytes(8).hex_encode()

static func port(kind: String, direction: String, id: String) -> Array:
	for p in KINDS.get(kind, {}).get(direction, []):
		if p[0] == id:
			return p
	return []

static func defaults(kind: String) -> Dictionary:
	match kind:
		"door_state": return {"state": "close"}
		"door_animation": return {"action": "toggle"}
		"state_is", "state_entered", "state_exited", "request_state": return {"state": ""}
		"state_changed": return {"from_state": "", "to_state": ""}
		"perform_action": return {"action": ""}
		"action_finished": return {"action": "", "succeeded": true}
		"set_interaction": return {"enabled": true}
		"set_property": return {"property": "locked", "bool_value": false, "number_value": 1.0}
		"bool", "set_lever": return {"value": false}
		"number": return {"value": 0.0}
		"delay": return {"seconds": 0.5}
	return {}

static func port_label(kind: String, id: String, output := false) -> String:
	if output and id == "value":
		if kind in ["single_door", "double_door"]: return "门框"
		if kind == "door_leaf": return "门扇"
		if kind == "door_animation": return "门状态"
		if kind == "door_state": return "成立"
	return {"frame": "门框", "leaf": "门扇", "completed": "动画到位", "entered": "进入时"}.get(id, PORT_LABELS.get(id, id))
