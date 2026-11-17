extends "res://addons/godot_level_editor/scripts/core/game_session.gd"
## 工具链连续世界入口。美术与关卡布局由场景资源提供。
@export var persist_progress := true
@export_node_path("Node3D") var world_path := NodePath("World")
@onready var world: Node3D = get_node(world_path)
var _world_states: Dictionary = {}
var _current_room := ""

func _ready() -> void:
	super._ready()
	get_window().title = "GodotLevelEditor · 白盒编辑器"
	world.objective_changed.connect(hud.set_objective)
	world.goal_completed.connect(_on_goal_completed)
	world.progress_requested.connect(_on_progress_requested)
	_initialize_world.call_deferred()

func _initialize_world() -> void:
	await get_tree().physics_frame
	for marker in world.find_children("*", "Marker3D", true, false):
		if marker.get_script() == preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/spawn_marker.gd") and marker.role == "player":
			player.global_transform = marker.global_transform
			player.spawn_transform = marker.global_transform
			camera_rig.snap_to_target()
			break
	_register_component("world", world)
	for id in world.runtime_components():
		_register_component(id, world.runtime_components()[id])
	world.component_available.connect(_register_component)
	for room in world.rooms():
		room.player_entered.connect(func(id: String, actor: Node3D):
			if actor == player: _set_location(id))
	if persist_progress:
		get_node("/root/GLESaveSystem").load_game()
	_set_location(world.start_room_id)
	hud.set_objective("白盒试玩：探索空间并测试交互。")
	_refresh_progress()
	var tasks := get_node_or_null("Narrative/Tasks")
	if tasks != null and tasks.valid:
		tasks.task_completed.connect(func(_id: String):
			if persist_progress: get_node("/root/GLESaveSystem").save_game.call_deferred())

func _register_component(_id: String, component: Node) -> void:
	if not is_instance_valid(component) or not component.has_method("tl_capture") or _world_states.has(component):
		return
	_world_states[component] = component.tl_capture().duplicate(true)

func _set_location(id: String) -> void:
	_current_room = id
	for room in world.rooms():
		if room.room_id == id:
			hud.set_location(room.display_name)
			return
	hud.set_location(id)

func _reset_room() -> void:
	super._reset_room()
	for component in _world_states:
		if is_instance_valid(component) and component.has_method("tl_restore"):
			component.tl_restore(_world_states[component].duplicate(true))
	hud.hide_banner()
	_set_location(world.start_room_id)
	_refresh_progress()

func _on_goal_completed(_id: String) -> void:
	_refresh_progress()
	hud.flash_message("房间目标已完成，世界进度已更新。")

func _refresh_progress() -> void:
	var completed := 0
	if world.runner != null:
		for node in world.runner.definition.nodes:
			if node.kind == "goal" and world.runner.persistent.get(node.id, false): completed += 1
	hud.set_rooms_info("已完成目标  %d" % completed)

func _on_progress_requested(_progress: Dictionary) -> void:
	if persist_progress: get_node("/root/GLESaveSystem").save_game()

func save_payload() -> Dictionary:
	var progress: Dictionary = world.capture_progress() if world.runtime_valid else {}
	var tasks := get_node_or_null("Narrative/Tasks")
	if tasks != null and tasks.valid: progress["narrative"] = tasks.capture_progress()
	return progress

func apply_progress(progress: Dictionary) -> void:
	if not progress.is_empty(): world.restore_progress(progress)
	var tasks := get_node_or_null("Narrative/Tasks")
	if tasks != null and tasks.valid and progress.has("narrative"): tasks.restore_progress(progress.narrative)
	_refresh_progress()
