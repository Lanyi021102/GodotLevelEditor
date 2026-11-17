@tool
extends Node3D
## A persisted, lightweight instance adapter shared by NPCs, Rooms and mechanisms.
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const DIRECTORS := &"godot_level_editor_task_directors"
const HUMAN := "res://addons/godot_level_editor/assets/characters/quaternius_base/adapted_human.tscn"
const CHARACTER := preload("res://addons/godot_level_editor/scripts/actors/character_model.gd")
var entity: Node3D
var visual: Node3D
var _signature: Array = []
var _original_meshes: Dictionary = {}
var _collisions: Dictionary = {}
var _director: WeakRef
var _clock := 0.0
var _original_visible := true
var _original_process := Node.PROCESS_MODE_INHERIT
var _active := true

func _ready() -> void:
	entity = get_parent() as Node3D
	process_mode = Node.PROCESS_MODE_ALWAYS
	_original_visible = entity.visible
	_original_process = entity.process_mode
	if entity.is_node_ready(): refresh()
	else: entity.ready.connect(refresh, CONNECT_ONE_SHOT)

func profile() -> Resource:
	return entity.get_meta(PROFILE.META) if is_instance_valid(entity) and entity.has_meta(PROFILE.META) else null

func _process(delta: float) -> void:
	_clock += delta
	if _clock < 0.1: return
	_clock = 0
	refresh()

func refresh() -> void:
	if not is_inside_tree() or not is_instance_valid(entity) or not entity.is_inside_tree(): return
	var config := profile()
	if config == null: return
	var signature: Array = config.signature()
	signature.append(entity.get("component_scene")); signature.append(entity.get("component_kind")); signature.append(entity.get("object_id"))
	if signature != _signature:
		_signature = signature
		_build_visual(config)
	if Engine.is_editor_hint(): return
	var enabled: bool = config.initially_enabled
	if config.lifetime == "task": enabled = enabled and _task_active(str(config.task_id))
	_set_active(enabled)
	if is_instance_valid(visual): visual.process_mode = Node.PROCESS_MODE_INHERIT if _active and entity.can_process() else Node.PROCESS_MODE_DISABLED

func _task_active(task_id: String) -> bool:
	if task_id.is_empty(): return false
	var world: Node = entity.get_parent()
	while world != null and not world.get("world_id") is String: world = world.get_parent()
	var director: Node = _director.get_ref() if _director != null else null
	if not is_instance_valid(director) or director.get("world") != world:
		director = null
		for candidate in get_tree().get_nodes_in_group(DIRECTORS):
			if candidate.get("world") == world:
				director = candidate; _director = weakref(candidate); break
	if director == null or not director.get("valid"): return false
	var task: Dictionary = director.catalog.task_by_id(task_id)
	if task.is_empty() or str(task.level_id) != str(director.current_level_id): return false
	for signal_name in ["task_started", "task_completed"]:
		if not director.is_connected(signal_name, _task_changed): director.connect(signal_name, _task_changed)
	if not director.is_connected("task_failed", _task_failed): director.connect("task_failed", _task_failed)
	return director.task_states.get(task_id, "") == "active"

func _task_changed(task_id: String) -> void:
	var config := profile()
	if config != null and config.task_id == task_id: refresh.call_deferred()

func _task_failed(task_id: String, _reason: String) -> void:
	_task_changed(task_id)

func _set_active(value: bool) -> void:
	if value and _active: return
	if not value and _active:
		_original_visible = entity.visible; _original_process = entity.process_mode
	_active = value
	entity.visible = _original_visible and value
	entity.process_mode = _original_process if value else Node.PROCESS_MODE_DISABLED
	if is_instance_valid(visual): visual.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if value:
		for node in _collisions:
			if not is_instance_valid(node): continue
			var state: Array = _collisions[node]
			node.collision_layer = state[0]; node.collision_mask = state[1]; node.input_ray_pickable = state[2]
		_collisions.clear()
	else:
		var queue: Array[Node] = [entity]
		while not queue.is_empty():
			var node: Node = queue.pop_back()
			queue.append_array(node.get_children())
			if node is CollisionObject3D:
				if not _collisions.has(node): _collisions[node] = [node.collision_layer, node.collision_mask, node.input_ray_pickable]
				node.collision_layer = 0; node.collision_mask = 0; node.input_ray_pickable = false
	if entity.has_method("set_detection_enabled"): entity.set_detection_enabled(value)

func _build_visual(config: Resource) -> void:
	if config.kind == "room":
		if entity.has_method("refresh_volume"): entity.refresh_volume()
		return
	if is_instance_valid(visual): visual.free()
	visual = null
	for mesh in _original_meshes:
		if is_instance_valid(mesh): mesh.visible = _original_meshes[mesh]
	_original_meshes.clear()
	var source: PackedScene = config.model_scene
	if source == null and config.model_id == "humanoid_base": source = load(HUMAN) as PackedScene
	if source == null and config.model_id == "default" and Engine.is_editor_hint() and entity.get("component_scene") is PackedScene: source = entity.component_scene
	if source == null and config.model_id == "default": return
	# Authored scene content stays intact. Only its generated/authored mesh visibility
	# is overridden, and the derived visual has no owner and is never saved.
	for node in entity.find_children("*", "MeshInstance3D", true, false):
		_original_meshes[node] = node.visible; node.visible = false
	# Derived meshes are direct children of the authored entity. Native viewport
	# picking then selects the entity, rather than its persisted adapter child.
	visual = Node3D.new(); visual.name = "ModelPreview"; entity.add_child(visual)
	if config.model_id == "humanoid_base" and config.model_scene == null:
		var model := CHARACTER.new(); model.auto_setup = false; model.target_height = config.body_height
		visual.add_child(model); model.setup()
		_play_action(model, str(config.default_action))
	elif source != null:
		var model := source.instantiate()
		if model is Node3D:
			_passive_model(model)
			visual.add_child(model)
			_passive_model(model)
			_play_action(model, str(config.default_action))
		else: model.free()
	else:
		var mesh := MeshInstance3D.new()
		if config.model_id == "box":
			var box := BoxMesh.new(); box.size = Vector3.ONE; mesh.mesh = box; mesh.position.y = 0.5
		else:
			var capsule := CapsuleMesh.new(); capsule.radius = config.body_radius; capsule.height = maxf(config.body_height, config.body_radius * 2)
			mesh.mesh = capsule; mesh.position.y = capsule.height * 0.5
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("d98b70") if config.faction == "hostile" else Color("729daa")
		mesh.material_override = material; visual.add_child(mesh)
	if entity.get("prompt") is Label3D:
		entity.prompt.font_size = 24; entity.prompt.pixel_size = 0.006
		entity.prompt.position.y = config.body_height + 0.3

func _passive_model(node: Node) -> void:
	if node is CollisionObject3D: node.collision_layer = 0; node.collision_mask = 0; node.input_ray_pickable = false
	if node is WorldEnvironment: node.environment = null; node.camera_attributes = null; node.compositor = null
	if node is Camera3D: node.current = false
	if node is Light3D: node.visible = false
	if node is AudioStreamPlayer3D: node.autoplay = false; node.stop()
	for child in node.get_children(): _passive_model(child)

func _play_action(model: Node, action: String) -> void:
	for player in model.find_children("*", "AnimationPlayer", true, false):
		for animation in player.get_animation_list():
			if str(animation).to_lower().contains(action.to_lower()) and action != "patrol":
				player.play(animation)
				return
