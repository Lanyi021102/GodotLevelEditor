extends Node

const SEQUENCE := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sequence.gd")
const SAMPLER := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sampler.gd")
const NODE_NAME := "GLEPerformancePlayer"
const INPUT_GROUP := "godot_level_editor_performance_player"

var _sampler: RefCounted
var _ticket := {}
var _time := 0.0
var _locked := false

static func play(world: Node3D, id: String, task_id := "") -> Dictionary:
	var data := SEQUENCE.lookup(world, id)
	if data == null: return {"ok": false, "reason": "找不到演出"}
	if data.clips.is_empty(): return {"ok": false, "reason": "演出没有片段"}
	var errors: PackedStringArray = data.validate(world, task_id, true)
	if not errors.is_empty(): return {"ok": false, "reason": "；".join(errors)}
	var player := world.get_node_or_null(NODE_NAME)
	if player == null:
		player = load("res://addons/godot_level_editor/modules/godot_level_editor_performance/player.gd").new()
		player.name = NODE_NAME
		world.add_child(player)
	return player._begin(data, world)

static func is_playing_in(world: Node) -> bool:
	var player := world.get_node_or_null(NODE_NAME) if is_instance_valid(world) else null
	return player != null and player._sampler != null

static func cancel_in(world: Node) -> void:
	if not is_instance_valid(world): return
	var player := world.get_node_or_null(NODE_NAME)
	if player != null: player._finish(false)

func _ready() -> void:
	add_to_group(INPUT_GROUP)
	set_physics_process(false)

func _begin(data: Resource, world: Node3D) -> Dictionary:
	if _sampler != null: return {"ok": false, "reason": "当前已有演出正在播放"}
	var original := get_viewport().get_camera_3d()
	var camera: Camera3D
	if data.clips.any(func(clip: Dictionary): return clip.kind == "camera"):
		camera = Camera3D.new()
		add_child(camera)
		if original != null: original.make_current()
	_sampler = SAMPLER.new()
	_sampler.bind(data, world, world, camera)
	_sampler.base_camera = original
	_sampler.suspend_actors()
	_time = 0.0
	_ticket = {"status": "playing", "cancel": _finish.bind(false)}
	_locked = data.locks_input()
	_sampler.sample(_time)
	set_physics_process(true)
	return {"ok": true, "reason": "正在播放演出", "ticket": _ticket}

func blocks_player_input() -> bool:
	return _locked

func _physics_process(delta: float) -> void:
	_time = minf(_time + delta, _sampler.sequence.duration())
	if not _sampler.sample(_time): _finish(false)
	elif _time >= _sampler.sequence.duration(): _finish(true)

func _finish(success: bool) -> void:
	if _sampler == null: return
	set_physics_process(false)
	_locked = false
	if is_instance_valid(_sampler.base_camera): _sampler.base_camera.make_current()
	if is_instance_valid(_sampler.camera):
		_sampler.camera.clear_current(false)
		_sampler.camera.queue_free()
	_sampler.release_actors(success)
	_sampler = null
	_ticket.status = "completed" if success else "failed"
	_ticket.erase("cancel")

func _exit_tree() -> void:
	if _sampler != null:
		_locked = false
		if is_instance_valid(_sampler.base_camera): _sampler.base_camera.make_current()
		_ticket.status = "failed"
		_ticket.erase("cancel")
