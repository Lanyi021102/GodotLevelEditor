extends Node3D
## Shared 3C session. Clone recordings are immutable across branches.
const PLAYER_SCENE := preload("res://scenes/humanoid_player.tscn")
@export var actor_scene: PackedScene = PLAYER_SCENE
@export var split_cooldown := 0.0
@export var scrub_speed := 2.0
@onready var camera_rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD
@onready var trails: Node3D = $Trails
var player: CharacterBody3D
var _bodies: Array[CharacterBody3D] = []
var _initial_spawn := Transform3D()
var _clone_serial := 0
var _scrub_direction := 0
var _hold_time := 0.0
var _scrub_accumulator := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	add_to_group("main")
	player = $Player
	player.camera_rig = camera_rig
	player.set_role_input()
	player.get_node("ModelRoot").use_textured_body()
	_initial_spawn = player.global_transform
	_bodies = [player]
	camera_rig.target = player
	camera_rig.arm.add_excluded_object(player.get_rid())
	hud.pause_requested.connect(toggle_observation)
	Timeline.rewound.connect(func(frame: int, _time: float): _update_presence(frame))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("resume_time"):
		Timeline.resume()
	elif event.is_action_pressed("split_clone"):
		try_split()
	else: return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var direction := int(Input.is_action_pressed("fast_forward")) - int(Input.is_action_pressed("rewind"))
	if direction != _scrub_direction:
		_scrub_direction = direction
		_hold_time = 0.0
		_scrub_accumulator = 0.0
		if direction != 0: Timeline.scrub(direction * Timeline.TICK_RATE)
	elif direction != 0:
		_hold_time += delta
		if _hold_time > 0.3:
			_scrub_accumulator += delta * scrub_speed * Timeline.TICK_RATE
			var steps := int(_scrub_accumulator)
			if steps > 0:
				Timeline.scrub(direction * steps)
				_scrub_accumulator -= steps
	if not Timeline.frozen and player.global_position.y < -8:
		_reset_room()

func _physics_process(_delta: float) -> void:
	if not Timeline.frozen:
		_update_presence(Timeline.head + 1)

func toggle_observation() -> void:
	if Timeline.frozen: Timeline.resume()
	elif Timeline.head >= 0: Timeline.rewind_to_frame(Timeline.head)

func try_split() -> bool:
	if not Timeline.frozen or Timeline.cursor >= Timeline.head: return false
	var slot := Timeline.get_entity_index(player.get_node("Rewindable"))
	var segment := Timeline.capture_segment(slot, Timeline.cursor, Timeline.head)
	if segment.size() < 2: return false
	var clone: CharacterBody3D = actor_scene.instantiate()
	# Copy edited motion parameters as well as scene defaults.
	for property in ["walk_speed", "run_speed", "acceleration", "deceleration", "air_acceleration", "gravity", "jump_height", "turn_speed", "coyote_time", "jump_buffer_time"]:
		clone.set(property, player.get(property))
	add_child(clone)
	clone.tl_restore(segment[0])
	clone.spawn_frame = Timeline.cursor
	_clone_serial += 1
	clone.begin_replay(_clone_serial, segment, Timeline.cursor)
	_bodies.append(clone)
	camera_rig.arm.add_excluded_object(clone.get_rid())
	Timeline.truncate_to_cursor()
	# Remain paused. T explicitly starts the new branch.
	return true

func _clone_count() -> int:
	return _bodies.size() - 1

func _update_presence(frame: int) -> void:
	for body in _bodies:
		if body == player: continue
		var exists: bool = body.spawn_frame <= frame
		if exists and not body.visible:
			body.tl_restore(body.replay_segment[0])
			body.mode = body.Mode.REPLAY
			body._replay_time = 0.0
			body._replay_event_index = -1
		body.visible = exists
		body.set_physics_process(exists)
		body.set_collision_layer_value(2, exists)

func _reset_room() -> void:
	Timeline.clear()
	for body in _bodies:
		if body != player:
			Timeline.unregister(body.get_node("Rewindable"))
			body.queue_free()
	_bodies = [player]
	Timeline.compact_entities()
	player.spawn_frame = 0
	player.reset_to_spawn()
	_clone_serial = 0
