@tool
class_name GodotLevelEditorLevelGraph
extends Resource
## Definition only. Semantic data and canvas layout have separate fields.
const VERSION := 1
const TASK_NODES := preload("res://addons/godot_level_editor_narrative/runtime/task_nodes.gd")
const PORTS := {
	"task_accept": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"event_hold": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"event_complete": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"npc_interact": {"in": {}, "out": {"then": "event"}},
	"dialog_completed": {"in": {}, "out": {"then": "event"}},
	"show_dialog": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"task_start": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"task_complete": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"start": {"in": {}, "out": {"then": "event"}},
	"room_enter": {"in": {}, "out": {"then": "event"}},
	"region_enter": {"in": {}, "out": {"then": "event"}},
	"event_received": {"in": {}, "out": {"then": "event"}},
	"emit_event": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"set_switch": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"enemy_patrol": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"kill_player": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"set_visibility": {"in": {"run": "event"}, "out": {"then": "event", "failed": "event"}},
	"player_state": {"in": {}, "out": {"value": "bool"}},
	"has_item": {"in": {}, "out": {"value": "bool"}},
	"branch": {"in": {"run": "event", "condition": "bool"}, "out": {"yes": "event", "no": "event"}},
	"port": {"in": {"space": "space"}, "out": {"space": "space"}},
	"source": {"in": {}, "out": {"value": "bool"}},
	"constant": {"in": {}, "out": {"value": "bool"}},
	"number": {"in": {}, "out": {"value": "number"}},
	"greater": {"in": {"a": "number", "b": "number"}, "out": {"value": "bool"}},
	"object": {"in": {}, "out": {"value": "object"}},
	"read_state": {"in": {"target": "object"}, "out": {"value": "bool"}},
	"all": {"in": {"a": "bool", "b": "bool"}, "out": {"value": "bool"}},
	"goal": {"in": {"condition": "bool"}, "out": {"completed": "event"}},
	"latch": {"in": {"set": "event"}, "out": {"value": "bool"}},
	"unlock": {"in": {"enabled": "bool"}, "out": {}},
	"objective": {"in": {"run": "event"}, "out": {}},
	"checkpoint": {"in": {"run": "event"}, "out": {}},
}
const LABELS := {"event_hold": "等待显式结束事件", "event_complete": "结束当前事件", "npc_interact": "玩家与 NPC 互动时", "dialog_completed": "对话完成时", "show_dialog": "ShowDialog", "task_start": "开始任务", "task_complete": "完成任务", "region_enter": "玩家进入触发区域时", "start": "游戏开始时", "room_enter": "玩家进入房间时", "event_received": "收到事件时", "emit_event": "发送事件", "set_switch": "打开／关闭开关", "enemy_patrol": "敌人开始巡逻", "kill_player": "击杀玩家", "set_visibility": "显示／隐藏物件", "player_state": "检测玩家当前状态", "has_item": "检查背包物件", "branch": "如果条件成立", "port": "房间接驳点", "source": "检测机关是否开启", "constant": "是／否", "number": "数值", "greater": "比较两个数值", "object": "引用场景物件", "read_state": "检测引用物件状态", "all": "同时满足两个条件", "goal": "完成房间目标", "latch": "记住已发生的事件", "unlock": "允许房间之间通行", "objective": "更新玩家目标", "checkpoint": "请求保存进度"}
const CATEGORIES := {"event_hold": "操作", "event_complete": "操作", "npc_interact": "触发", "dialog_completed": "触发", "show_dialog": "操作", "task_start": "操作", "task_complete": "操作", "region_enter": "触发", "start": "触发", "room_enter": "触发", "event_received": "触发", "goal": "触发", "emit_event": "操作", "set_switch": "操作", "enemy_patrol": "操作", "kill_player": "操作", "set_visibility": "操作", "latch": "操作", "unlock": "操作", "objective": "操作", "checkpoint": "操作", "player_state": "判断", "has_item": "判断", "branch": "判断", "source": "判断", "read_state": "判断", "all": "判断", "greater": "判断"}
const PORT_LABELS := {"cancel": "取消", "cancelled": "已取消", "timeout": "超时", "reset": "重置", "remaining": "剩余秒数", "reached": "达到次数", "open": "开启", "close": "关闭", "closed": "未通过", "c": "分支 C", "d": "分支 D", "space": "空间接口", "value": "结果", "condition": "条件", "completed": "完成时", "set": "记录事件", "enabled": "允许通行", "run": "执行", "then": "继续", "failed": "失败", "yes": "成立", "no": "不成立", "a": "条件 A", "b": "条件 B", "target": "目标物件"}
const TYPE_LABELS := {"space": "空间", "bool": "是／否", "event": "事件", "number": "数值", "object": "物件"}
const OLD_LABELS := ["对话完成时 Trigger", "ShowDialog 播放 comment", "ShowDialog 显示对话组", "玩家是否解锁道具", "空间接驳点", "读取机关布尔状态", "布尔常量", "数值常量", "数值大于", "场景对象引用", "读取引用对象状态", "布尔 AND", "区域目标完成事件", "事件 → 持续布尔", "解锁空间连接", "更新目标"]

static func ports(kind: String) -> Dictionary:
	return PORTS.get(kind, TASK_NODES.PORTS.get(kind, {}))

static func labels() -> Dictionary:
	var result := LABELS.duplicate()
	result["task_accept"] = "接受任务"
	for kind in TASK_NODES.DEFINITIONS: result[kind] = TASK_NODES.DEFINITIONS[kind][0]
	return result

static func category(kind: String) -> String: return str(CATEGORIES.get(kind, "基础"))

static func display_label(node: Dictionary) -> String:
	var label := str(node.get("label", ""))
	return str(labels().get(node.kind, node.kind)) if label.is_empty() or OLD_LABELS.has(label) else label

@export var schema_version := VERSION
@export var graph_id := ""
@export_enum("topology", "events") var graph_kind := "events"
@export var nodes: Array[Dictionary] = []
@export var edges: Array[Dictionary] = []
@export var positions: Dictionary = {}
@export var view_scroll := Vector2.ZERO
@export var view_zoom := 1.0

func is_level_logic() -> bool: return false

static func fresh_id(prefix: String = "n") -> String:
	return prefix + "_" + Crypto.new().generate_random_bytes(12).hex_encode()

func node_by_id(id: String) -> Dictionary:
	for n in nodes:
		if n.get("id") == id:
			return n
	return {}

func semantic_hash() -> String:
	return JSON.stringify({"version": schema_version, "id": graph_id, "kind": graph_kind, "nodes": nodes, "edges": edges}, "", true).sha256_text()

func snapshot() -> Dictionary:
	return {"nodes": nodes.duplicate(true), "edges": edges.duplicate(true), "positions": positions.duplicate(true), "view_scroll": view_scroll, "view_zoom": view_zoom}

func apply_snapshot(data: Dictionary) -> void:
	nodes.assign(data.nodes.duplicate(true))
	edges.assign(data.edges.duplicate(true))
	positions = data.positions.duplicate(true)
	view_scroll = data.view_scroll
	view_zoom = data.view_zoom
	emit_changed()

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != VERSION:
		errors.append("不支持的图版本：%s" % schema_version)
	if graph_id.is_empty() or not ["topology", "events"].has(graph_kind):
		errors.append("图缺少稳定 ID 或图类型无效")
	var ids := {}
	for n in nodes:
		var id := str(n.get("id", ""))
		var kind := str(n.get("kind", ""))
		if not id.is_valid_identifier() or ids.has(id):
			errors.append("节点 ID 无效或重复：" + id)
		ids[id] = true
		if ports(kind).is_empty() or (graph_kind == "topology") != (kind == "port"):
			errors.append(id + "：节点类型不属于此图")
		if not n.get("params") is Dictionary:
			errors.append(id + "：参数格式无效")
			continue
		var p: Dictionary = n.get("params", {})
		for required in {"npc_interact": ["npc"] if is_level_logic() else ["npc", "task"], "dialog_completed": ["dialog_id"] if is_level_logic() else ["dialog_id", "task"], "show_dialog": ["dialog_id"], "task_start": ["task"], "task_complete": ["task"], "task_accept": ["task"]}.get(kind, []):
			if required == "npc" and is_level_logic():
				if str(p.get(required, "")).is_empty(): errors.append(id + "：请选择关卡常驻 NPC")
				continue
			if not str(p.get(required, "")).is_valid_identifier() and not (required in ["dialog_id", "task"] and str(p.get(required, "")).is_valid_int()): errors.append(id + "：缺少有效标识 " + required)
		if TASK_NODES.DEFINITIONS.has(kind):
			if not has_method("load_dialogue"): errors.append(id + "：此节点仅用于任务图")
			errors.append_array(TASK_NODES.validate_node(n))
		if kind in ["port", "source", "goal", "region_enter", "object", "set_switch", "enemy_patrol", "set_visibility"] and str(p.get("object", "")).is_empty():
			errors.append(id + "：缺少场景对象引用")
		if kind in ["source", "read_state"] and not ["powered", "open"].has(p.get("query", "powered")):
			errors.append(id + "：未知状态查询")
		if kind == "room_enter" and str(p.get("room", "")).is_empty(): errors.append(id + "：请选择房间")
		if kind in ["event_received", "emit_event", "has_item"] and str(p.get("key", "")).strip_edges().is_empty(): errors.append(id + "：请填写事件／道具名称")
		if kind == "player_state" and not ["alive", "crouching", "moving", "clone", "on_floor"].has(p.get("state", "alive")): errors.append(id + "：玩家状态无效")
		for key in ["once", "enabled"]:
			if p.has(key) and typeof(p[key]) != TYPE_BOOL: errors.append(id + "：参数必须为是／否 " + key)
		if kind == "unlock" and str(p.get("link", "")).is_empty():
			errors.append(id + "：缺少空间连线引用")
		if kind == "constant" and typeof(p.get("value", false)) != TYPE_BOOL:
			errors.append(id + "：常量必须为布尔值")
		if kind == "number" and (not (p.get("value") is float or p.get("value") is int) or not is_finite(float(p.get("value", 0)))):
			errors.append(id + "：数值必须有限")
		if kind in ["goal", "latch"] and typeof(p.get("persistent", true)) != TYPE_BOOL:
			errors.append(id + "：持续进度参数必须为布尔值")
		if positions.has(id) and (not positions[id] is Vector2 or not positions[id].is_finite()):
			errors.append(id + "：排版坐标无效")
	var edge_ids := {}
	var inputs := {}
	var endpoints := {}
	for e in edges:
		var id := str(e.get("id", ""))
		if not id.is_valid_identifier() or edge_ids.has(id):
			errors.append("连线 ID 无效或重复：" + id)
		edge_ids[id] = true
		var a := node_by_id(str(e.get("from", "")))
		var b := node_by_id(str(e.get("to", "")))
		if a.is_empty() or b.is_empty() or ports(str(a.get("kind"))).is_empty() or ports(str(b.get("kind"))).is_empty():
			errors.append(id + "：悬空节点引用")
			continue
		var out: Dictionary = ports(a.kind).out
		var inp: Dictionary = ports(b.kind).in
		var fp := str(e.get("from_port", ""))
		var tp := str(e.get("to_port", ""))
		if not out.has(fp) or not inp.has(tp) or out.get(fp) != inp.get(tp):
			errors.append(id + "：端口无效或类型不匹配")
			continue
		if graph_kind == "topology":
			for end in [a.id, b.id]:
				if endpoints.has(end):
					errors.append(id + "：空间接驳点被重复连接")
				endpoints[end] = true
		elif inp[tp] != "event":
			var key: String = b.id + "/" + tp
			if inputs.has(key):
				errors.append(id + "：布尔输入只能有一个来源")
			inputs[key] = true
	if graph_kind == "events":
		# No implicit feedback: this version rejects every directed cycle.
		var remaining := ids.duplicate()
		for _i in nodes.size():
			var removable := []
			for id in remaining:
				var blocked := false
				for e in edges:
					if e.get("to") == id and remaining.has(e.get("from")):
						blocked = true
				if not blocked:
					removable.append(id)
			for id in removable:
				remaining.erase(id)
		if not remaining.is_empty():
			errors.append("存在没有明确推进规则的循环")
	if not view_scroll.is_finite() or not is_finite(view_zoom) or view_zoom < 0.2 or view_zoom > 3.0:
		errors.append("画布视图无效")
	return errors
