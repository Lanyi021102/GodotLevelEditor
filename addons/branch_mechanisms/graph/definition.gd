@tool
extends Resource
const Schema := preload("res://addons/branch_mechanisms/graph/schema.gd")
@export var format_version := 1
@export var definition_id := ""
@export var display_name := "机关组合"
## Runtime semantics; IDs and named ports never depend on canvas positions.
@export var nodes: Array[Dictionary] = []
@export var edges: Array[Dictionary] = []
## Layout only.
@export var positions: Dictionary = {}
@export var view_offset := Vector2.ZERO
@export var view_zoom := 1.0

func find_node(id: String) -> Dictionary:
	for entry in nodes:
		if entry.get("id", "") == id:
			return entry
	return {}

func validate(bindings: Dictionary = {}, check_bindings := false) -> PackedStringArray:
	var errors := PackedStringArray()
	if format_version != 1:
		errors.append("不支持图版本 %s（支持版本 1）" % format_version)
	if definition_id.is_empty(): errors.append("图缺少稳定 definition_id")
	# Reject malformed resource shapes before typed access or runtime compilation.
	for entry in nodes:
		if not entry.get("id") is String or not entry.get("kind") is String or not entry.get("params", {}) is Dictionary:
			errors.append("节点需要字符串 id/kind 与字典 params")
	for edge in edges:
		for key in ["from", "out", "to", "in"]:
			if not edge.get(key) is String: errors.append("连线需要字符串端点和端口：" + key)
	if not errors.is_empty(): return errors
	var ids := {}
	var occupied := {}
	var drivers := {}
	var event_adjacency := {}
	for entry in nodes:
		var id := str(entry.get("id", ""))
		var kind := str(entry.get("kind", ""))
		if id.is_empty() or ids.has(id): errors.append("节点 ID 缺失或重复：" + id)
		ids[id] = true
		if not Schema.KINDS.has(kind):
			errors.append("未知节点类型：" + kind)
			continue
		var params: Dictionary = entry.get("params", {})
		if kind in ["bool", "set_lever"] and typeof(params.get("value")) != TYPE_BOOL:
			errors.append(id + " 的 value 必须为布尔值")
		if kind in ["number", "delay"]:
			var value: Variant = params.get("value") if kind == "number" else params.get("seconds")
			if not (value is float or value is int) or not is_finite(float(value)):
				errors.append(id + " 的数值无效")
			elif kind == "delay" and float(value) < 0.0:
				errors.append(id + " 的延迟不能为负")
		if Schema.KINDS[kind].has("binding"):
			var object_id := str(params.get("object_id", ""))
			if object_id.is_empty(): errors.append(id + " 缺少对象绑定")
			if check_bindings:
				var object: Node = bindings.get(object_id)
				if not is_instance_valid(object):
					errors.append(id + " 绑定对象不存在：" + object_id)
				else:
					var expected: String = Schema.KINDS[kind]["binding"]
					if not object.has_method("is_powered"):
						errors.append(id + " 绑定对象不提供 is_powered()")
					elif expected != "power" and object.get_meta("mechanism_kind", "") != expected:
						errors.append(id + " 绑定对象类型不匹配")
			if kind == "door":
				if drivers.has(object_id): errors.append("同一扇门只能有一个目标节点：" + object_id)
				drivers[object_id] = true
	for edge in edges:
		var source := find_node(str(edge.get("from", "")))
		var target := find_node(str(edge.get("to", "")))
		var output := Schema.port(str(source.get("kind", "")), "out", str(edge.get("out", "")))
		var input := Schema.port(str(target.get("kind", "")), "in", str(edge.get("in", "")))
		if source.is_empty() or target.is_empty() or output.is_empty() or input.is_empty():
			errors.append("连线含缺失节点或无效端口：" + str(edge))
			continue
		if output[1] != input[1]: errors.append("连线类型不匹配：" + str(edge))
		var key := str(edge.to) + ":" + str(edge["in"])
		if occupied.has(key): errors.append("输入端口存在多条连线：" + key)
		occupied[key] = true
		if output[1] == Schema.EVENT and source.kind != "delay":
			if not event_adjacency.has(str(edge.from)): event_adjacency[str(edge.from)] = []
			event_adjacency[str(edge.from)].append(str(edge.to))
	for entry in nodes:
		for input in Schema.KINDS.get(entry.get("kind", ""), {}).get("in", []):
			if not occupied.has(str(entry.get("id", "")) + ":" + input[0]):
				errors.append("输入端口未连接：%s.%s" % [entry.get("id", ""), input[0]])
	if data_order().size() != nodes.size(): errors.append("连续数据存在循环，请使用有状态事件节点推进")
	var visiting := {}
	var visited := {}
	for id in ids:
		if _has_cycle(id, event_adjacency, visiting, visited):
			errors.append("事件循环缺少延迟节点")
			break
	return errors

func data_order() -> Array[String]:
	var indegrees := {}
	var next := {}
	for entry in nodes:
		indegrees[str(entry.get("id", ""))] = 0
	for edge in edges:
		var source := find_node(str(edge.get("from", "")))
		var output := Schema.port(str(source.get("kind", "")), "out", str(edge.get("out", "")))
		if output.is_empty() or output[1] == Schema.EVENT: continue
		if not indegrees.has(str(edge.get("from", ""))) or not indegrees.has(str(edge.get("to", ""))): continue
		indegrees[str(edge.to)] += 1
		if not next.has(str(edge.from)): next[str(edge.from)] = []
		next[str(edge.from)].append(str(edge.to))
	var ready: Array = []
	for id in indegrees:
		if indegrees[id] == 0: ready.append(id)
	ready.sort()
	var order: Array[String] = []
	while not ready.is_empty():
		var id: String = ready.pop_front()
		order.append(id)
		for target in next.get(id, []):
			indegrees[target] -= 1
			if indegrees[target] == 0:
				ready.append(target)
				ready.sort()
	return order

func _has_cycle(id: String, adjacency: Dictionary, visiting: Dictionary, visited: Dictionary) -> bool:
	if visiting.has(id): return true
	if visited.has(id): return false
	visiting[id] = true
	for target in adjacency.get(id, []):
		if _has_cycle(target, adjacency, visiting, visited): return true
	visiting.erase(id)
	visited[id] = true
	return false
