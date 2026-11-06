extends "res://scripts/core/game_session.gd"
## 工具链连续世界入口。美术与关卡布局由场景资源提供。
@export var persist_progress := true
@onready var world: Node3D = $World
const ADAPTER := preload("res://scripts/actors/player_rewindable.gd")
var _world_states: Dictionary = {}
var _current_room := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	super._ready()
	get_window().title = "Branch"
	world.objective_changed.connect(hud.set_objective)
	world.goal_completed.connect(_on_goal_completed)
	world.progress_requested.connect(_on_progress_requested)
	_initialize_world.call_deferred()

func _initialize_world() -> void:
	await get_tree().physics_frame
	_register_component("world", world)
	for id in world.runtime_components():
		_register_component(id, world.runtime_components()[id])
	world.component_available.connect(_register_component)
	for room in world.rooms():
		room.player_entered.connect(func(id: String, actor: Node3D):
			if actor == player: _set_location(id))
	if persist_progress:
		SaveSystem.load_game()
	_set_location(world.start_room_id)
	hud.set_objective("探索房间，通过回溯与固定分身安排协作。")
	_refresh_progress()

func _register_component(_id: String, component: Node) -> void:
	if not is_instance_valid(component) or not component.has_method("tl_capture") or _world_states.has(component):
		return
	if not component.has_node("Rewindable"):
		var adapter := ADAPTER.new()
		adapter.name = "Rewindable"
		adapter.trail_enabled = false
		component.add_child(adapter)
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
	Timeline.resume()

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
	if persist_progress: SaveSystem.save_game()

func save_payload() -> Dictionary:
	return world.capture_progress() if world.runtime_valid else {}

func apply_progress(progress: Dictionary) -> void:
	if not progress.is_empty(): world.restore_progress(progress)
	_refresh_progress()
