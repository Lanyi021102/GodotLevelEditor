@tool
extends Node3D
const Schema := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/graph/schema.gd")
@export var instance_id := ""
@export var object_id := ""
@export var primary_component: NodePath
@export var definition: Resource
var bindings: Dictionary = {}
var errors := PackedStringArray()
var values: Dictionary = {}
var trace: Dictionary = {}
var frame := 0
var pending: Array[Dictionary] = []
var previous: Dictionary = {}
var last_events: Dictionary = {}
var _order: Array[String] = []
var _inputs: Dictionary = {}
var _debug_frames := 0
var _signal_links: Array[Dictionary] = []
var _signal_packets: Array[Dictionary] = []

func _enter_tree() -> void:
	if object_id.is_empty(): object_id = instance_id if not instance_id.is_empty() else Schema.uid("assembly")
	if instance_id.is_empty(): instance_id = object_id

func output_component() -> Node:
	if not primary_component.is_empty(): return get_node_or_null(primary_component)
	for object in bindings.values():
		if object.has_method("get_state"): return object
	return null

func _ready() -> void:
	process_physics_priority = -10
	configure()

func configure() -> PackedStringArray:
	_disconnect_component_signals()
	bindings.clear()
	errors.clear()
	_collect(self)
	for object in bindings.values():
		if object.has_method("validate_component"): errors.append_array(object.validate_component())
	if definition == null or not definition.has_method("validate"):
		errors.append("缺少有效机关图资源")
	else:
		errors.append_array(definition.validate(bindings, true))
		_order = definition.data_order()
		_inputs.clear()
		for edge in definition.edges: _inputs[str(edge.to) + ":" + str(edge["in"])] = str(edge.from) + ":" + str(edge.out)
	if not errors.is_empty():
		for object in bindings.values():
			if is_instance_valid(object) and object.has_method("set_graph_powered"): object.set_graph_powered(false)
	else: _connect_component_signals()
	return errors

func _disconnect_component_signals() -> void:
	for link in _signal_links:
		if is_instance_valid(link.node) and link.node.is_connected(link.signal, link.callback): link.node.disconnect(link.signal, link.callback)
	_signal_links.clear()

func _link_component(object: Node, signal_name: String, callback: Callable) -> void:
	object.connect(signal_name, callback); _signal_links.append({"node": object, "signal": signal_name, "callback": callback})

func _connect_component_signals() -> void:
	for id in bindings:
		var object: Node = bindings[id]
		if not object.has_method("get_state"): continue
		_link_component(object, "state_changed", func(old: String, state: String): _queue_component("state_changed", str(id), {"from_state": old, "to_state": state}))
		_link_component(object, "interacted", func(_object: String, action: String, actor: Node3D): _queue_component("interacted", str(id), {"action": action, "is_player": actor != null and actor.is_in_group("godot_level_editor_player")}))
		_link_component(object, "action_finished", func(action: String, succeeded: bool): _queue_component("action_finished", str(id), {"action": action, "succeeded": succeeded}))
		_link_component(object, "region_entered", func(_actor: Node3D): _queue_component("region_entered", str(id), {}))
		_link_component(object, "region_exited", func(_actor: Node3D): _queue_component("region_exited", str(id), {}))

func _queue_component(kind: String, id: String, context: Dictionary) -> void:
	if _signal_packets.size() >= 256:
		if not errors.has("机关组件事件队列超限"): errors.append("机关组件事件队列超限")
		return
	_signal_packets.append({"kind": kind, "object_id": id, "context": context})

func _matches_component(node: Dictionary, packet: Dictionary) -> bool:
	var p: Dictionary = node.get("params", {})
	if p.get("object_id", "") != packet.object_id: return false
	if node.kind == "door_state": return packet.kind == "state_changed" and p.state == packet.context.to_state
	if node.kind == "door_animation": return packet.kind == "action_finished" and packet.context.succeeded
	if node.kind in ["state_entered", "state_exited"]:
		return packet.kind == "state_changed" and p.state == packet.context.get("to_state" if node.kind == "state_entered" else "from_state")
	if node.kind != packet.kind: return false
	if node.kind == "state_changed": return (str(p.from_state).is_empty() or p.from_state == packet.context.from_state) and (str(p.to_state).is_empty() or p.to_state == packet.context.to_state)
	if node.kind == "action_finished": return (str(p.action).is_empty() or p.action == packet.context.action) and p.succeeded == packet.context.succeeded
	return true

func _collect(parent: Node) -> void:
	for child in parent.get_children():
		if child.has_meta("mechanism_kind"):
			var id := str(child.get("object_id"))
			if id.is_empty() or bindings.has(id): errors.append("对象 ID 缺失或重复：" + id)
			bindings[id] = child
		# Nested assemblies have their own ID scope.
		elif child.get_script() != get_script(): _collect(child)

func _physics_process(_delta: float) -> void:
	if not Engine.is_editor_hint(): step()

func _input_value(id: String, port: String, fallback: Variant = false) -> Variant:
	return values.get(_inputs.get(id + ":" + port, ""), fallback)

func step() -> void:
	if not errors.is_empty(): return
	frame += 1
	values.clear()
	trace.clear()
	var events: Array[Dictionary] = []
	var packets := _signal_packets.duplicate(true)
	_signal_packets.clear()
	for packet in packets:
		for id in _order:
			var node: Dictionary = definition.find_node(id)
			if _matches_component(node, packet):
				var port := "entered" if node.kind == "door_state" else ("completed" if node.kind == "door_animation" else "fired")
				_emit_event(id, port, events, "组件事件：" + str(packet.kind))
	var due: Array[Dictionary] = []
	var later: Array[Dictionary] = []
	for item in pending:
		if int(item.due) <= frame: due.append(item)
		else: later.append(item)
	pending = later
	for item in due: _emit_event(str(item.from), "fired", events, "延迟到期")
	# Each tick resets target commands. Removing a wire cannot leave a latched door open.
	for object in bindings.values():
		if is_instance_valid(object) and object.has_method("set_graph_powered"): object.set_graph_powered(false)
	for id in _order:
		var node: Dictionary = definition.find_node(id)
		var params: Dictionary = node.get("params", {})
		var object: Node = bindings.get(str(params.get("object_id", "")))
		var result: Variant = false
		match str(node.kind):
			"single_door", "double_door", "door_leaf", "door_animation": result = str(params.object_id)
			"door_state": result = is_instance_valid(object) and object.get_state() == str(params.state)
			"button", "toggle_switch", "pressure_plate", "sliding_door", "hinged_door", "lift_platform", "terminal": result = is_instance_valid(object) and object.is_powered()
			"state_is": result = is_instance_valid(object) and object.get_state() == str(params.state)
			"lever", "plate": result = is_instance_valid(object) and object.is_powered()
			"bool": result = params.value
			"number": result = float(params.value)
			"object": result = str(params.object_id)
			"read_power":
				var ref: Node = bindings.get(str(_input_value(id, "target", "")))
				result = is_instance_valid(ref) and ref.is_powered()
			"and": result = bool(_input_value(id, "a")) and bool(_input_value(id, "b"))
			"or": result = bool(_input_value(id, "a")) or bool(_input_value(id, "b"))
			"not": result = not bool(_input_value(id, "value"))
			"greater": result = float(_input_value(id, "a", 0.0)) > float(_input_value(id, "b", 0.0))
			"delay": result = pending.any(func(item: Dictionary): return str(item.from) == id)
			"door":
				result = bool(_input_value(id, "powered"))
				object.set_graph_powered(result)
			"rising":
				result = bool(_input_value(id, "value"))
				if result and not previous.get(id, false): _emit_event(id, "fired", events, "布尔 false → true")
				previous[id] = result
		values[id + ":value"] = result
		if str(node.kind) in ["interacted", "state_changed", "state_entered", "state_exited", "action_finished", "region_entered", "region_exited"]: result = last_events.get(id, {}).get("frame", -1) == frame
		trace[id] = {"value": result, "reason": "物理帧求值", "frame": frame}
		if is_instance_valid(object) and object.has_method("motion_info"): trace[id].merge(object.motion_info())
	var processed := 0
	while not events.is_empty() and processed < 64:
		var event: Dictionary = events.pop_front()
		processed += 1
		var node: Dictionary = definition.find_node(str(event.to))
		var params: Dictionary = node.get("params", {})
		trace[str(event.to)] = {"value": true, "reason": event.reason, "frame": frame}
		last_events[str(event.to)] = {"reason": event.reason, "frame": frame}
		if node.kind == "delay":
			pending.append({"from": str(node.id), "due": frame + maxi(1, ceili(float(params.seconds) * 60.0))})
		elif node.kind == "set_lever":
			var lever: Node = bindings.get(str(params.object_id))
			lever.set_powered(bool(params.value))
		elif node.kind == "branch":
			_emit_event(str(node.id), "yes" if _input_value(str(node.id), "condition") else "no", events, "机关条件判断")
		elif node.kind in ["request_state", "perform_action", "set_interaction", "set_property", "door_animation"]:
			var object: Node = bindings.get(str(params.object_id))
			var result := {"ok": false, "reason": "组件不存在"}
			if is_instance_valid(object):
				match str(node.kind):
					"request_state": result = object.request_state(str(params.state))
					"perform_action", "door_animation": result = object.perform_action(str(params.action))
					"set_interaction": result = object.set_property_value("interaction_enabled", params.enabled)
					"set_property": result = object.set_property_value(str(params.property), params.bool_value if params.property in ["locked", "interaction_enabled"] else params.number_value)
			trace[str(node.id)] = {"value": result.ok, "reason": str(result.reason), "frame": frame}
			if is_instance_valid(object) and object.has_method("motion_info"): trace[str(node.id)].merge(object.motion_info())
			_emit_event(str(node.id), "success" if result.ok else "failed", events, str(result.reason))
	if not events.is_empty() or pending.size() > 256:
		errors.append("机关事件处理预算超限（每帧 64，待处理 256）")
		for object in bindings.values():
			if object.has_method("set_graph_powered"): object.set_graph_powered(false)
	for id in trace:
		if last_events.has(id): trace[id]["last_event"] = last_events[id].duplicate()
	_debug_frames += 1
	if _debug_frames >= 6:
		_debug_frames = 0
		_send_debug()

func _emit_event(id: String, port: String, queue: Array[Dictionary], reason: String) -> void:
	last_events[id] = {"reason": reason, "frame": frame}
	for edge in definition.edges:
		if str(edge.from) == id and str(edge.out) == port:
			queue.append({"to": str(edge.to), "reason": reason})

func _send_debug() -> void:
	if Engine.is_editor_hint() or not EngineDebugger.is_active(): return
	EngineDebugger.send_message("godot_level_editor_mechanism:state", [{"instance": str(get_path()), "instance_id": instance_id, "scene": scene_file_path, "definition": definition.resource_path if definition != null else "", "definition_id": definition.definition_id if definition != null else "", "frame": frame, "trace": trace.duplicate(true), "errors": errors, "pending": pending.size()}])

func _exit_tree() -> void:
	_disconnect_component_signals()
	if not Engine.is_editor_hint() and EngineDebugger.is_active(): EngineDebugger.send_message("godot_level_editor_mechanism:remove", [str(get_path())])

func tl_capture() -> Dictionary:
	var objects := {}
	for id in bindings:
		if bindings[id].has_method("tl_capture"): objects[id] = bindings[id].tl_capture().duplicate(true)
	return {"frame": frame, "pending": pending.duplicate(true), "component_events": _signal_packets.duplicate(true), "previous": previous.duplicate(true), "last_events": last_events.duplicate(true), "values": values.duplicate(true), "trace": trace.duplicate(true), "objects": objects, "errors": errors.duplicate()}

func tl_restore(state: Dictionary) -> void:
	frame = int(state.get("frame", 0))
	_signal_packets.assign(state.get("component_events", []).duplicate(true))
	pending.assign(state.get("pending", []))
	pending = pending.duplicate(true)
	previous = state.get("previous", {}).duplicate(true)
	last_events = state.get("last_events", {}).duplicate(true)
	values = state.get("values", {}).duplicate(true)
	trace = state.get("trace", {}).duplicate(true)
	errors = state.get("errors", PackedStringArray()).duplicate()
	for id in state.get("objects", {}):
		if bindings.has(id) and bindings[id].has_method("tl_restore"): bindings[id].tl_restore(state.objects[id])
	_send_debug()
