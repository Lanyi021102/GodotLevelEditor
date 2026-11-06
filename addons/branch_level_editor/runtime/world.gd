@tool
extends Node3D
signal component_available(object_id: String, component: Node)
signal room_entered(from_room: String, to_room: String, actor: Node3D)
signal goal_completed(goal_id: String)
signal objective_changed(text: String)
signal progress_requested(progress: Dictionary)
const GRAPH := preload("res://addons/branch_level_editor/runtime/level_graph.gd")
const RUNNER := preload("res://addons/branch_level_editor/runtime/event_runner.gd")
const ROOM := preload("res://addons/branch_level_editor/runtime/room.gd")
const PORT := preload("res://addons/branch_level_editor/runtime/connection.gd")
const REGION := preload("res://addons/branch_level_editor/runtime/region.gd")
const PLACE := preload("res://addons/branch_level_editor/runtime/placement.gd")
@export var world_id := "branch_world_v1"
@export var start_room_id := "atrium"
@export var topology: BranchLevelGraph
@export var events: BranchLevelGraph
var actions: RefCounted
var runner: RefCounted
var runtime_topology: BranchLevelGraph
var runtime_valid := false
var _debug_clock := 0.0
var _debug_signature := ""
var _checkpoint_due := false
var _restored_overlaps: Dictionary = {}

func rooms() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_children():
		if node.get_script() == ROOM:
			result.append(node)
	return result

func objects() -> Dictionary:
	var result := {}
	for room in rooms():
		for child in room.get_children():
			var id: Variant = child.get("object_id")
			if id is String and not id.is_empty():
				result[room.room_id + "/" + id] = child
	for child in get_children():
		var id: Variant = child.get("object_id")
		if id is String and not id.is_empty(): result["$world/" + id] = child
	return result

func _room_trigger(id: String, actor: Node3D) -> void:
	if runner != null and not _restored_overlaps.has("room:" + id + "|" + str(actor.get_path())):
		var label := id
		for room in rooms():
			if room.room_id == id: label = room.display_name
		runner.queue_trigger("room_enter", {"room": id, "room_label": label, "actor": str(actor.get_path())})

func publish_event(key: String, actor: Node3D = null) -> void:
	if runner != null: runner.queue_trigger("event_received", {"key": key, "actor": str(actor.get_path()) if actor != null else ""})

func object_by_id(id: String) -> Node:
	return objects().get(id)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	process_physics_priority = 500
	var errors := validate()
	if not errors.is_empty():
		push_error("关卡世界拒绝运行：" + "; ".join(errors))
		return
	runtime_topology = topology.duplicate(true)
	runner = RUNNER.new()
	actions = preload("res://addons/branch_level_editor/runtime/level_actions.gd").new()
	actions.world = self
	runner.configure(events, object_by_id, actions.perform, actions.condition)
	for room in rooms():
		room.player_entered.connect(_room_trigger)
		room.player_exited.connect(func(id: String, actor: Node3D): _restored_overlaps.erase("room:" + id + "|" + str(actor.get_path())))
	for id in objects():
		var object: Node = object_by_id(id)
		if object.get_script() == REGION:
			object.player_entered.connect(func(actor: Node3D):
				if not _restored_overlaps.has("region:" + id + "|" + str(actor.get_path())):
					runner.queue_trigger("region_enter", {"object": id, "actor": str(actor.get_path())}))
			object.player_exited.connect(func(actor: Node3D): _restored_overlaps.erase("region:" + id + "|" + str(actor.get_path())))
	runner.executed.connect(_executed)
	runner.objective_requested.connect(func(text: String): objective_changed.emit(text))
	# Emit checkpoint after this frame's complete event batch, so all latches are included.
	runner.checkpoint_requested.connect(_request_progress)
	for edge in runtime_topology.edges:
		var a := runtime_topology.node_by_id(edge.from)
		var b := runtime_topology.node_by_id(edge.to)
		var pa: Node = object_by_id(a.params.object)
		var pb: Node = object_by_id(b.params.object)
		pa.crossed.connect(func(actor: Node3D): room_entered.emit(str(a.params.object).get_slice("/", 0), str(b.params.object).get_slice("/", 0), actor))
		pb.crossed.connect(func(actor: Node3D): room_entered.emit(str(b.params.object).get_slice("/", 0), str(a.params.object).get_slice("/", 0), actor))
	for child in get_children():
		if child.get_script() == PLACE and child.component_kind == "door" and child.component_scene == null and child.runtime_component != null:
			for source in child.source_ids:
				var anchor: Node = object_by_id("$world/" + source)
				if anchor != null: child.runtime_component.add_power_source(anchor)
	runtime_valid = true
	_apply_gates()
	var components := runtime_components()
	for id in components: component_available.emit(id, components[id])

func _request_progress() -> void:
	_checkpoint_due = true

func _emit_progress() -> void:
	if runtime_valid:
		progress_requested.emit(capture_progress())

func _executed(id: String, _reason: String) -> void:
	if runner.definition.node_by_id(id).get("kind") == "goal":
		goal_completed.emit(id)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not runtime_valid:
		return
	runner.tick()
	_apply_gates()
	if _checkpoint_due and runner.pending.is_empty():
		_checkpoint_due = false
		_emit_progress.call_deferred()
	_debug_clock += delta
	if EngineDebugger.is_active() and _debug_clock >= 0.15:
		_debug_clock = 0
		_send_debug()

func _send_debug(restored: bool = false) -> void:
	if not EngineDebugger.is_active(): return
	var packet := debug_state()
	packet["restored"] = restored
	var signature := str(packet)
	if signature != _debug_signature:
		_debug_signature = signature
		EngineDebugger.send_message("branch_level:state", [packet])

func _apply_gates() -> void:
	for edge in runtime_topology.edges:
		var enabled: bool = runner.link_enabled(edge.id)
		for id in [edge.from, edge.to]:
			var n := runtime_topology.node_by_id(id)
			object_by_id(n.params.object).set_unlocked(enabled)

func capture_progress() -> Dictionary:
	return {"schema_version": 1, "world_id": world_id, "graph_id": runner.definition.graph_id if runner != null else "", "states": runner.persistent.duplicate(true) if runner != null else {}}

func restore_progress(data: Dictionary) -> bool:
	if not runtime_valid or data.get("schema_version") != 1 or data.get("world_id") != world_id or data.get("graph_id") != runner.definition.graph_id or not data.get("states") is Dictionary:
		return false
	if not runner.restore_progress(data.states):
		return false
	_checkpoint_due = false
	runner.refresh_values()
	_apply_gates()
	_send_debug(true)
	return true

func tl_capture() -> Dictionary:
	var state: Dictionary = runner.capture() if runner != null else {}
	state["checkpoint_due"] = _checkpoint_due
	return state

func tl_restore(data: Dictionary) -> void:
	if runner != null:
		runner.restore(data)
		_restore_overlap_baseline()
		_checkpoint_due = bool(data.get("checkpoint_due", false))
		_apply_gates()
		_send_debug(true)

func runtime_components() -> Dictionary:
	var result := {}
	for id in objects():
		var anchor: Node = object_by_id(id)
		if anchor.get_script() == PLACE and anchor.runtime_component != null:
			result[id] = anchor.runtime_component
	if is_inside_tree():
		for agent in get_tree().get_nodes_in_group("branch_level_actor_agent"):
			if is_ancestor_of(agent): result["$actor/" + str(get_path_to(agent))] = agent
	return result

func debug_state() -> Dictionary:
	var values: Dictionary = runner.values.duplicate()
	var reasons: Dictionary = runner.last_reason.duplicate()
	for n in runtime_topology.nodes:
		values[n.id] = object_by_id(n.params.object).unlocked
		reasons[n.id] = "空间接口可通行" if values[n.id] else "空间接口锁定"
	return {"instance": str(get_path()), "scene": scene_file_path, "world_id": world_id, "graph_id": runner.definition.graph_id, "topology_id": runtime_topology.graph_id, "event_revision": runner.definition.semantic_hash(), "topology_revision": runtime_topology.semantic_hash(), "values": values, "persistent": runner.persistent.duplicate(), "local": runner.local_state.duplicate(), "reasons": reasons, "counts": runner.counts.duplicate(), "queued": runner.pending.size() + runner.incoming.size()}

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if topology == null or events == null:
		return PackedStringArray(["需要房间连接图与目标事件图"])
	errors.append_array(topology.validate())
	errors.append_array(events.validate())
	if topology.graph_kind != "topology" or events.graph_kind != "events":
		errors.append("两张图的类型不正确")
	if not errors.is_empty():
		return errors
	var room_ids := {}
	var refs := {}
	for child in get_children():
		var id: Variant = child.get("object_id")
		if id is String and not id.is_empty():
			refs["$world/" + id] = child
			if child.get_script() == preload("res://addons/branch_level_editor/runtime/whitebox_block.gd"): errors.append_array(child.validate())
	for room in rooms():
		errors.append_array(room.validate())
		if room_ids.has(room.room_id) or not str(room.room_id).is_valid_identifier():
			errors.append("房间 ID 无效或重复：" + str(room.room_id))
		room_ids[room.room_id] = true
		if not room.bounds_size.is_finite() or room.bounds_size.x <= 0 or room.bounds_size.z <= 0:
			errors.append(str(room.room_id) + "：房间范围无效")
		if not room.scale.is_equal_approx(Vector3.ONE) or absf(room.rotation.x) > 0.001 or absf(room.rotation.z) > 0.001:
			errors.append(str(room.room_id) + "：房间只支持平移与水平旋转")
		for obj in room.get_children():
			var local_id: Variant = obj.get("object_id")
			if not local_id is String:
				continue
			var id: String = room.room_id + "/" + local_id
			if not local_id.is_valid_identifier() or refs.has(id):
				errors.append("对象 ID 无效或重复：" + id)
			refs[id] = obj
			if not obj.transform.is_finite() or (obj.get_script() != preload("res://addons/branch_level_editor/runtime/whitebox_block.gd") and not obj.scale.is_equal_approx(Vector3.ONE)):
				errors.append(id + "：对象必须使用有限坐标、单位缩放；请编辑尺寸参数")
			if obj.get_script() == PLACE and obj.component_kind == "door":
				for source in obj.source_ids:
					if room.object_by_id(source) == null:
						errors.append(id + "：缺少兼容机关来源 " + source)
	if not room_ids.has(start_room_id):
		errors.append("起始房间不存在")
	var bound_ports := {}
	for n in topology.nodes:
		var obj: Node = refs.get(n.params.object)
		if obj == null or obj.get_script() != PORT:
			errors.append(n.id + "：空间对象引用无效")
		if bound_ports.has(n.params.object):
			errors.append(n.id + "：接驳点重复绑定")
		bound_ports[n.params.object] = true
	var links := {}
	for e in topology.edges:
		links[e.id] = true
		var a: Node3D = refs.get(topology.node_by_id(e.from).params.object)
		var b: Node3D = refs.get(topology.node_by_id(e.to).params.object)
		if a == null or b == null:
			continue
		var at: Transform3D = _relative_transform(a)
		var bt: Transform3D = _relative_transform(b)
		if at.origin.distance_to(bt.origin) > 0.15 or at.basis.z.normalized().dot(bt.basis.z.normalized()) > -0.98 or not is_equal_approx(float(a.get("width")), float(b.get("width"))):
			errors.append(e.id + "：接驳点位置、朝向或宽度未对齐；连线不会生成走廊")
	var controllers := {}
	for n in events.nodes:
		if n.kind in ["goal", "region_enter", "source", "object", "set_switch", "enemy_patrol", "set_visibility"]:
			var obj: Node = refs.get(n.params.object)
			if obj == null or (n.kind in ["goal", "region_enter"] and obj.get_script() != REGION) or (n.kind == "source" and obj.get_script() != PLACE):
				errors.append(n.id + "：场景绑定无效")
		if n.kind == "room_enter" and not room_ids.has(n.params.room): errors.append(n.id + "：房间引用失效")
		if n.kind in ["set_switch", "enemy_patrol"]:
			var target: Node = refs.get(n.params.object)
			if target != null and (not target.has_method("output_component")): errors.append(n.id + "：请绑定组件实例")
		if n.kind == "unlock":
			if not links.has(n.params.link) or controllers.has(n.params.link):
				errors.append(n.id + "：空间连线不存在或有多个控制器")
			controllers[n.params.link] = true
	# Reachability ignoring locks catches islands; dynamic lock behavior is tested at runtime.
	var reached := {start_room_id: true}
	for _i in rooms().size():
		for e in topology.edges:
			var a: String = str(topology.node_by_id(e.from).params.object).get_slice("/", 0)
			var b: String = str(topology.node_by_id(e.to).params.object).get_slice("/", 0)
			if reached.has(a): reached[b] = true
			if reached.has(b): reached[a] = true
	for id in room_ids:
		if not reached.has(id): errors.append("孤立房间：" + str(id))
	return errors

func warnings() -> PackedStringArray:
	var result := PackedStringArray()
	for id in objects():
		var anchor: Node = object_by_id(id)
		if anchor.get_script() == PLACE and anchor.component_kind == "placeholder" and anchor.component_scene == null:
			result.append(id + "：占位接口 — " + anchor.placeholder_contract)
	return result

func _relative_transform(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent is Node3D:
			result = parent.transform * result
		parent = parent.get_parent()
	return result

func _exit_tree() -> void:
	if not Engine.is_editor_hint() and EngineDebugger.is_active():
		EngineDebugger.send_message("branch_level:remove", [str(get_path())])

func _restore_overlap_baseline() -> void:
	# Physics overlaps lag behind snapshot transforms/collision changes. Restoring an
	# actor inside a trigger is not a new entrance; wait for a real exit and reentry.
	_restored_overlaps.clear()
	for actor in get_tree().get_nodes_in_group("branch_player"):
		if not actor is Node3D or (actor.has_method("is_clone") and actor.call("is_clone")): continue
		var point: Vector3 = actor.global_position + Vector3.UP * 0.1
		for room in rooms():
			var bounds := AABB(Vector3(-room.bounds_size.x * 0.5, 0, -room.bounds_size.z * 0.5), room.bounds_size).grow(0.3)
			if bounds.has_point(room.to_local(point)): _restored_overlaps["room:" + room.room_id + "|" + str(actor.get_path())] = true
		for id in objects():
			var object: Node = object_by_id(id)
			if object.get_script() == REGION:
				var bounds := AABB(Vector3(-object.extent.x * 0.5, 0, -object.extent.z * 0.5), object.extent).grow(0.3)
				if bounds.has_point(object.to_local(point)): _restored_overlaps["region:" + id + "|" + str(actor.get_path())] = true
