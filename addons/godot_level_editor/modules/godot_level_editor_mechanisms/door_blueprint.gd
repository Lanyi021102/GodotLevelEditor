@tool
extends RefCounted
const SCHEMA := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/graph/schema.gd")

static func append_nodes(graph: Resource, kind: String, object_id: String, origin := Vector2(40, 20), stable_ids := false) -> Dictionary:
	var ids := {}
	var entries := [
		["frame", kind, "门框", {}, Vector2.ZERO],
		["leaf", "door_leaf", "旋转门扇", {}, Vector2(310, 0)],
		["interact", "interacted", "玩家交互 · 切换门状态", {}, Vector2(310, 280)],
		["rotate", "door_animation", "旋转动画 · 0° ↔ 90°", {"action": "toggle"}, Vector2(620, 0)],
		["close", "door_state", "close", {"state": "close"}, Vector2(0, 440)],
		["moving", "door_state", "moving", {"state": "moving"}, Vector2(320, 440)],
		["open", "door_state", "open", {"state": "open"}, Vector2(640, 440)]
	]
	for entry in entries:
		var id: String = entry[0] if stable_ids else SCHEMA.uid("door_" + str(entry[0]))
		ids[str(entry[0])] = id
		var params: Dictionary = entry[3].duplicate(true); params.object_id = object_id
		graph.nodes.append({"id": id, "kind": entry[1], "label": entry[2], "params": params})
		graph.positions[id] = origin + entry[4]
	for edge in [["frame", "value", "leaf", "frame"], ["leaf", "value", "rotate", "leaf"], ["interact", "fired", "rotate", "trigger"], ["rotate", "value", "close", "target"], ["rotate", "value", "moving", "target"], ["rotate", "value", "open", "target"]]:
		graph.edges.append({"from": ids[edge[0]], "out": edge[1], "to": ids[edge[2]], "in": edge[3]})
	return ids
