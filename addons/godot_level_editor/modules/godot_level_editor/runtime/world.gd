@tool
extends Node3D
signal component_available(object_id: String, component: Node)
signal room_entered(from_room: String, to_room: String, actor: Node3D)
signal goal_completed(goal_id: String)
signal objective_changed(text: String)
signal progress_requested(progress: Dictionary)
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const RUNNER := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/event_runner.gd")
const ROOM := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/room.gd")
const PORT := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/connection.gd")
const REGION := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/region.gd")
const PLACE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/placement.gd")
const GROUPS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
const SKY_RUNTIME := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/runtime.gd")
@export var sky_preset: Resource:
	set(value):
		sky_preset = value
		if is_inside_tree(): refresh_sky.call_deferred()
var sky_runtime: Node3D

func refresh_sky() -> void:
	if not is_inside_tree(): return
	if sky_preset == null and not is_instance_valid(sky_runtime): return
	if not is_instance_valid(sky_runtime):
		sky_runtime = SKY_RUNTIME.new()
		sky_runtime.name = "SkyRuntime"
		add_child(sky_runtime)
	var errors: PackedStringArray = sky_runtime.apply(sky_preset)
	if not errors.is_empty(): push_warning("; ".join(errors))

func preview_sky(preset: Resource) -> PackedStringArray:
	if not is_instance_valid(sky_runtime):
		sky_runtime = SKY_RUNTIME.new()
		sky_runtime.name = "SkyRuntime"
		add_child(sky_runtime)
	return sky_runtime.apply(preset)
@export var world_id := "godot_level_editor_world_v1"
@export var level_id := ""
@export var start_room_id := "atrium"
@export var topology: GodotLevelEditorLevelGraph
@export var events: GodotLevelEditorLevelGraph
@export var level_logic: GodotLevelEditorLevelGraph
var logic_director: Node
var actions: RefCounted
var runner: RefCounted
var runtime_topology: GodotLevelEditorLevelGraph
var runtime_valid := false
var _debug_clock := 0.0
var _debug_signature := ""
var _checkpoint_due := false
var _restored_overlaps: Dictionary = {}

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_POST_SAVE and Engine.is_editor_hint():
		load("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_registry.gd").saved_world(self)

func rooms() -> Array[Node]:
	var result: Array[Node] = []
	for node in GROUPS.contents(self):
		if node.get_script() == ROOM:
			result.append(node)
	return result

func objects() -> Dictionary:
	return _object_index().objects

func _object_index() -> Dictionary:
	var result := {}
	var ambiguous := {}
	var errors := PackedStringArray()
	for room in rooms():
		for child in GROUPS.contents(room):
			_index_object(room.room_id, child, result, ambiguous, errors)
	for child in GROUPS.contents(self):
		_index_object("$world", child, result, ambiguous, errors)
	return {"objects": result, "errors": errors}

func _index_object(scope: String, object: Node, result: Dictionary, ambiguous: Dictionary, errors: PackedStringArray) -> void:
	var id: Variant = object.get("object_id")
	if not id is String or id.is_empty(): return
	var reference: String = scope + "/" + id
	if not id.is_valid_identifier():
		errors.append("对象 ID 无效：" + reference)
		return
	if result.has(reference) or ambiguous.has(reference):
		if not ambiguous.has(reference): errors.append("对象 ID 重复：" + reference)
		# A duplicate reference has no unambiguous target; never let a copy take it over.
		result.erase(reference)
		ambiguous[reference] = true
	else: result[reference] = object

func _room_trigger(id: String, actor: Node3D) -> void:
	if runner != null and not _restored_overlaps.has("room:" + id + "|" + str(actor.get_path())):
		var label := id
		for room in rooms():
			if room.room_id == id: label = room.display_name
		runner.queue_trigger("room_enter", {"room": id, "room_label": label, "actor": str(actor.get_path())})

func publish_event(key: String, actor: Node3D = null) -> void:
	if runner != null: runner.queue_trigger("event_received", {"key": key, "actor": str(actor.get_path()) if actor != null else ""})
	if is_instance_valid(logic_director): logic_director.publish_event(key)

func object_by_id(id: String) -> Node:
	return objects().get(id)

func _ready() -> void:
	if sky_preset != null: refresh_sky.call_deferred()
	if Engine.is_editor_hint():
		return
	_start_standalone_play.call_deferred()
	process_physics_priority = 500
	var errors := validate()
	if not errors.is_empty():
		push_error("关卡世界拒绝运行：" + "; ".join(errors))
		return
	runtime_topology = topology.duplicate(true)
	runner = RUNNER.new()
	actions = preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_actions.gd").new()
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
	for child in GROUPS.contents(self):
		if child.get_script() == PLACE and child.component_kind == "door" and child.component_scene == null and child.runtime_component != null:
			for source in child.source_ids:
				var anchor: Node = object_by_id("$world/" + source)
				if anchor != null: child.runtime_component.add_power_source(anchor)
	runtime_valid = true
	if level_logic != null: _start_level_logic_services.call_deferred()
	_apply_gates()
	var components := runtime_components()
	for id in components: component_available.emit(id, components[id])

func _start_standalone_play() -> void:
	# F6 runs the world itself; worlds inside an existing game session already have a player.
	if get_tree().current_scene != self or get_tree().get_first_node_in_group("main") != null:
		return
	var session: Node3D = load("res://addons/godot_level_editor/scenes/level_editor/play_session.tscn").instantiate()
	add_child(session)

func _start_level_logic_services() -> void:
	for director in get_tree().get_nodes_in_group("godot_level_editor_task_directors"):
		if director.get("world") == self and director.get("valid"): return
	var director: Node = load("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_director.gd").new()
	director.name = "LevelLogic"
	director.world_path = NodePath("..")
	director.workbook = level_logic.events_xlsx
	director.automatic_starts = false
	add_child(director)

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
		EngineDebugger.send_message("godot_level_editor_level:state", [packet])

func _apply_gates() -> void:
	for edge in runtime_topology.edges:
		var enabled: bool = runner.link_enabled(edge.id)
		for id in [edge.from, edge.to]:
			var n := runtime_topology.node_by_id(id)
			object_by_id(n.params.object).set_unlocked(enabled)

func capture_progress() -> Dictionary:
	var data := {"schema_version": 1, "world_id": world_id, "graph_id": runner.definition.graph_id if runner != null else "", "states": runner.persistent.duplicate(true) if runner != null else {}}
	if is_instance_valid(logic_director): data["level_logic"] = logic_director.capture_progress()
	return data

func restore_progress(data: Dictionary) -> bool:
	if not runtime_valid or data.get("schema_version") != 1 or data.get("world_id") != world_id or data.get("graph_id") != runner.definition.graph_id or not data.get("states") is Dictionary:
		return false
	var previous: Dictionary = runner.capture()
	var previous_persistent: Dictionary = runner.persistent.duplicate(true)
	if not runner.restore_progress(data.states):
		return false
	if data.has("level_logic") and (not is_instance_valid(logic_director) or not logic_director.restore_progress(data.level_logic)):
		runner.persistent = previous_persistent
		runner.restore(previous)
		return false
	_checkpoint_due = false
	runner.refresh_values()
	_apply_gates()
	_send_debug(true)
	return true

func tl_capture() -> Dictionary:
	var state: Dictionary = runner.capture() if runner != null else {}
	state["checkpoint_due"] = _checkpoint_due
	if is_instance_valid(logic_director): state["level_logic"] = logic_director.capture_progress()
	return state

func tl_restore(data: Dictionary) -> void:
	if runner != null:
		runner.restore(data)
		if data.has("level_logic") and is_instance_valid(logic_director): logic_director.restore_progress(data.level_logic)
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
		for agent in get_tree().get_nodes_in_group("godot_level_editor_level_actor_agent"):
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
	var errors: PackedStringArray = _object_index().errors
	if level_logic != null:
		if not level_logic.is_level_logic(): errors.append("关卡图必须使用常驻关卡逻辑资源")
		else:
			errors.append_array(level_logic.validate())
			errors.append_array(level_logic.validate_bindings(self))
	if sky_preset != null:
		if sky_preset.get_script() != SKY_RUNTIME.PRESET:
			errors.append("天空预设类型无效")
		else:
			errors.append_array(sky_preset.validate())
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
	for child in GROUPS.contents(self):
		var id: Variant = child.get("object_id")
		if id is String and not id.is_empty():
			refs["$world/" + id] = child
			if child.get_script() == preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd"): errors.append_array(child.validate())
	for room in rooms():
		errors.append_array(room.validate())
		if room_ids.has(room.room_id) or not str(room.room_id).is_valid_identifier():
			errors.append("房间 ID 无效或重复：" + str(room.room_id))
		room_ids[room.room_id] = true
		if not room.bounds_size.is_finite() or room.bounds_size.x <= 0 or room.bounds_size.z <= 0:
			errors.append(str(room.room_id) + "：房间范围无效")
		if not room.scale.is_equal_approx(Vector3.ONE) or absf(room.rotation.x) > 0.001 or absf(room.rotation.z) > 0.001:
			errors.append(str(room.room_id) + "：房间只支持平移与水平旋转")
		for obj in GROUPS.contents(room):
			var local_id: Variant = obj.get("object_id")
			if not local_id is String:
				continue
			var id: String = room.room_id + "/" + local_id
			if not local_id.is_valid_identifier() or refs.has(id):
				errors.append("对象 ID 无效或重复：" + id)
			refs[id] = obj
			if not obj.transform.is_finite() or (obj.get_script() != preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd") and not obj.scale.is_equal_approx(Vector3.ONE)):
				errors.append(id + "：对象必须使用有限坐标、单位缩放；请编辑尺寸参数")
			if obj.get_script() == PLACE and obj.component_kind == "door":
				for source in obj.source_ids:
					if room.object_by_id(source) == null:
						errors.append(id + "：缺少兼容机关来源 " + source)
	# Detection areas in a sandbox do not define a room traversal graph.
	var has_topology_rooms := rooms().any(func(room: Node): return room.uses_topology)
	if has_topology_rooms and not room_ids.has(start_room_id):
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
		var linked_room := false
		for room in rooms():
			if room.room_id == id: linked_room = room.uses_topology
		if linked_room and not reached.has(id): errors.append("孤立房间：" + str(id))
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
		EngineDebugger.send_message("godot_level_editor_level:remove", [str(get_path())])

func _restore_overlap_baseline() -> void:
	# Physics overlaps lag behind snapshot transforms/collision changes. Restoring an
	# actor inside a trigger is not a new entrance; wait for a real exit and reentry.
	_restored_overlaps.clear()
	for actor in get_tree().get_nodes_in_group("godot_level_editor_player"):
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
