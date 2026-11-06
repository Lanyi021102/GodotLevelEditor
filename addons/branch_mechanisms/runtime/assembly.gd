@tool
extends Node3D
const Schema := preload("res://addons/branch_mechanisms/graph/schema.gd")
@export var instance_id := ""
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

func _ready() -> void:
	process_physics_priority = -10
	configure()

func configure() -> PackedStringArray:
	bindings.clear()
	errors.clear()
	_collect(self)
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
	return errors

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
		trace[id] = {"value": result, "reason": "物理帧求值", "frame": frame}
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
	EngineDebugger.send_message("branch_mechanism:state", [{"instance": str(get_path()), "instance_id": instance_id, "scene": scene_file_path, "definition": definition.resource_path if definition != null else "", "definition_id": definition.definition_id if definition != null else "", "frame": frame, "trace": trace.duplicate(true), "errors": errors, "pending": pending.size()}])

func _exit_tree() -> void:
	if not Engine.is_editor_hint() and EngineDebugger.is_active(): EngineDebugger.send_message("branch_mechanism:remove", [str(get_path())])

func tl_capture() -> Dictionary:
	var objects := {}
	for id in bindings:
		if bindings[id].has_method("tl_capture"): objects[id] = bindings[id].tl_capture().duplicate(true)
	return {"frame": frame, "pending": pending.duplicate(true), "previous": previous.duplicate(true), "last_events": last_events.duplicate(true), "values": values.duplicate(true), "trace": trace.duplicate(true), "objects": objects, "errors": errors.duplicate()}

func tl_restore(state: Dictionary) -> void:
	frame = int(state.get("frame", 0))
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
