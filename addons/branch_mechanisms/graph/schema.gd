@tool
extends RefCounted
## Port IDs are stable; labels and GraphNode slot indices are presentation only.
const BOOL := 1
const NUMBER := 2
const OBJECT := 3
const EVENT := 4
const KINDS := {
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
const PORT_LABELS := {"value": "值", "powered": "目标", "target": "对象", "fired": "触发", "trigger": "事件", "a": "A", "b": "B"}
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
		"bool", "set_lever": return {"value": false}
		"number": return {"value": 0.0}
		"delay": return {"seconds": 0.5}
	return {}
