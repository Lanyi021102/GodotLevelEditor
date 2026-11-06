extends CharacterBody3D
## 玩家角色：相机相对移动 + 跳跃 + 动画状态机（待机 / 走 / 跑 / 空中 / 落地）。
## 角色模型由 CharacterModel 提供，当前使用正常比例骨骼角色。

@export_group("移动")
@export var walk_speed := 4.2
@export var run_speed := 8.0
@export var acceleration := 26.0
@export var deceleration := 32.0
@export var air_acceleration := 7.0
@export var gravity := 24.0
@export var jump_height := 1.7
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var turn_speed := 14.0

@export_group("潜行（docs/GDD.md §6）")
## 蹲行速度（蹲行无声）
@export var crouch_speed := 2.0
## 奔跑噪音半径（GDD §6.1）
@export var hearing_run := 8.0
## 落地噪音半径
@export var hearing_land := 5.0

@export_group("模型")
## 模型相关参数（模型、缩放、灰白材质）在 ModelRoot 节点的 CharacterModel 组件上
## 模型自带的朝向和 Godot 的 -Z 前方不一致时，用它修正（0 或 180 通常就够了）
@export var model_yaw_offset_degrees := 0.0
## 出生朝向：0 = 面向 +Z（南），180 = 面向 -Z（北，背对默认相机）
@export var start_facing_degrees := 180.0
@export var white_albedo := Color(0.86, 0.86, 0.875)

@export_group("分身重放")
## 轨迹跟随的到达容差（米）
@export var replay_loop := false
@export var replay_arrive_epsilon := 0.4
## 被挡住时最多原地等多久（秒），超时就跳过这个采样点，避免永久卡死
@export var replay_block_timeout := 4.0
## 追赶轨迹时的速度上限（跑速的倍数）
@export var replay_catchup_scale := 1.6

@export_group("动画")
@export var idle_clip := "Idle"
@export var walk_clip := "Walking_A"
@export var run_clip := "Running_A"
@export var jump_start_clip := "Jump_Start"
@export var jump_air_clip := "Jump_Idle"
@export var jump_land_clip := "Jump_Land"
@export var blend_time := 0.15

const CLONE_COLORS: Array[Color] = [
	Color(0.36, 0.86, 0.86),
	Color(0.96, 0.63, 0.28),
	Color(0.73, 0.53, 0.96),
]

enum Mode { INPUT, REPLAY }

var camera_rig: Node3D
var spawn_transform: Transform3D

## 当前模式：INPUT = 玩家操控；REPLAY = 分身循环重放录像
var mode: int = Mode.INPUT
## 这具身体在第几帧出现（回退到更早的时刻就不该存在）
var spawn_frame := 0
## 认领的录像段（Array[Dictionary]，元素是 tl_capture() 的快照）
var replay_segment: Array = []
## 录像段对应的起始帧（HUD 上画分身占用区间用）
var replay_start_frame := 0
var display_name := "本体"
var trail_color := Color(0.97, 0.97, 1.0, 0.6)

var _replay_event_index := -1
var _interaction_events: Array = []
var _replay_time := 0.0
var _replay_wait := 0.0
var _replay_loops := 0
var _white_material: StandardMaterial3D

@onready var _model_root: CharacterModel = $ModelRoot

var _anim: AnimationPlayer
var _state := ""
var _lock := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _air_time := 0.0
var _was_on_floor := true
## 是否正蹲着（潜行：更慢、更省、完全无声，守卫也更难看到）
var crouching := false
var _noise_timer := 0.0


func _ready() -> void:
	# 角色放在第 2 层、只和第 1 层（世界）碰撞：
	# 这样本体与分身不会互相顶住（它们在分裂点重叠生成），但仍然会被门/箱子挡住。
	collision_layer = 2
	collision_mask = 1
	add_to_group("stealth_target")
	spawn_transform = global_transform
	spawn_frame = maxi(Timeline.head, 0)
	_setup_model()
	_set_rewindable_meta()


# --------------------------------------------------------------------------
# 模型（实际装载逻辑在 scripts/actors/character_model.gd，玩家/分身/守卫共用）
# --------------------------------------------------------------------------
func _setup_model() -> void:
	if _model_root.anim == null:
		push_error("模型没有装载成功：%s" % _model_root.model_scene)
		return
	_anim = _model_root.anim
	_model_root.set_tint(white_albedo, 1.0)
	_state = "idle"
	_play(idle_clip, 0.0)
	_model_root.rotation.y = deg_to_rad(start_facing_degrees) + deg_to_rad(model_yaw_offset_degrees)


## 给分身染色（半透明），和本体区分开
func set_body_tint(color: Color, alpha := 1.0) -> void:
	_model_root.set_tint(color, alpha)


## 把名字与轨迹配色同步到 Rewindable 组件（HUD 与轨迹线读的是它）
func _set_rewindable_meta() -> void:
	var rw := get_node_or_null("Rewindable")
	if rw == null:
		return
	rw.set("trail_color", trail_color)
	rw.set("display_name", display_name)


# --------------------------------------------------------------------------
# 主循环
# --------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_interaction_events.clear()
	if mode == Mode.REPLAY:
		_physics_replay(delta)
		return
	var on_floor := is_on_floor()

	_coyote = coyote_time if on_floor else maxf(_coyote - delta, 0.0)
	_air_time = 0.0 if on_floor else _air_time + delta
	_jump_buffer = jump_buffer_time if Input.is_action_just_pressed("jump") else maxf(_jump_buffer - delta, 0.0)

	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	var dir := Vector3(input_dir.x, 0.0, input_dir.y)
	if camera_rig:
		dir = Basis(Vector3.UP, camera_rig.get_yaw_radians()) * dir
	if dir.length() > 1.0:
		dir = dir.normalized()

	var sprinting := Input.is_action_pressed("sprint")
	crouching = false
	if crouching:
		sprinting = false

	var speed := crouch_speed if crouching else (run_speed if sprinting else walk_speed)
	var accel := (deceleration if dir.length_squared() < 0.001 else acceleration) if on_floor else air_acceleration
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_v.z, accel * delta)

	if on_floor:
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= gravity * delta
	if _jump_buffer > 0.0:
		if _coyote > 0.0:
			velocity.y = sqrt(2.0 * gravity * jump_height)
			_jump_buffer = 0.0
			_coyote = 0.0
			_was_on_floor = false

	if dir.length_squared() > 0.001:
		var want_yaw := atan2(dir.x, dir.z) + deg_to_rad(model_yaw_offset_degrees)
		_model_root.rotation.y = lerp_angle(_model_root.rotation.y, want_yaw, minf(1.0, turn_speed * delta))

	move_and_slide()
	if Input.is_action_just_pressed("interact"):
		interact_nearest()

	if on_floor and not _was_on_floor:
		NoiseBus.emit_pulse(global_position, hearing_land, self)   # 落地有声
	_emit_movement_noise(sprinting, delta)
	_update_animation(on_floor, delta)
	_was_on_floor = on_floor


## Running and landing still supply perception cues; there is no resource cost.
func _emit_movement_noise(sprinting: bool, delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if planar < 0.15:
		return
	var running := (sprinting and planar > walk_speed * 1.05) or planar > run_speed * 0.9
	if crouching:
		return
	_noise_timer -= delta
	if running and _noise_timer <= 0.0:
		NoiseBus.emit_pulse(global_position, hearing_run, self)
		_noise_timer = 0.4


# --------------------------------------------------------------------------
# 分身：固定录像，默认播放一次后停在终点
# Follow committed recordings with world collision checks.
# --------------------------------------------------------------------------
func _physics_replay(delta: float) -> void:
	var on_floor := is_on_floor()
	_air_time = 0.0 if on_floor else _air_time + delta

	if replay_segment.is_empty():
		# 没有录像可放（在游标处直接分裂）→ 原地待机，相当于一个"活道具"
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if on_floor:
			velocity.y = minf(velocity.y, 0.0)
		else:
			velocity.y -= gravity * delta
		move_and_slide()
		_update_animation(on_floor, delta)
		_was_on_floor = on_floor
		return

	var last_index := replay_segment.size() - 1
	if not replay_loop and _replay_time > float(last_index) / float(Timeline.TICK_RATE):
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = minf(velocity.y, 0.0) if on_floor else velocity.y - gravity * delta
		move_and_slide()
		_update_animation(on_floor, delta)
		return
	var index := clampi(int(floor(_replay_time * float(Timeline.TICK_RATE))), 0, last_index)
	var step: Dictionary = replay_segment[index]
	if index > _replay_event_index:
		for event_index in range(_replay_event_index + 1, index + 1):
			for action in replay_segment[event_index].get("interactions", []):
				var endpoint := _resolve_interaction(action)
				if endpoint != null and endpoint.has_method("interact"):
					endpoint.interact(self)
		_replay_event_index = index
	crouching = bool(step.get("crouching", false))
	var target: Vector3 = (step["transform"] as Transform3D).origin
	var recorded_v: Vector3 = step["velocity"]
	var recorded_speed := _segment_speed(index)

	var before := global_position
	var flat := Vector3(target.x - before.x, 0.0, target.z - before.z)
	var dist := flat.length()
	var want_speed := clampf(dist / maxf(delta, 0.0001), 0.0, run_speed * replay_catchup_scale)
	if dist > 0.01:
		velocity.x = flat.normalized().x * want_speed
		velocity.z = flat.normalized().z * want_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	# 垂直方向直接照抄录像（跳跃弧线因此完全一致）
	velocity.y = recorded_v.y

	move_and_slide()

	if recorded_speed >= 0.15:
		var running := recorded_speed > walk_speed * 1.05
		# 分身跑动一样出声 —— 这就是"拿分身当诱饵"的机制基础
		_noise_timer -= delta
		if running and not bool(step.get("crouching", false)) and _noise_timer <= 0.0:
			NoiseBus.emit_pulse(global_position, hearing_run, self)
			_noise_timer = 0.4

	_model_root.rotation.y = lerp_angle(_model_root.rotation.y, float(step["model_yaw"]),
		minf(1.0, turn_speed * delta))
	_play(String(step["anim"]))
	_model_root.set_speed_scale(float(step["anim_speed"]))

	var actual := Vector3(global_position.x - before.x, 0.0, global_position.z - before.z).length()
	var expected := want_speed * delta
	if dist > replay_arrive_epsilon and actual < expected * 0.4:
		# 被挡住了：原地等，不推进重放时间
		_replay_wait += delta
		if _replay_wait < replay_block_timeout:
			_play(idle_clip)
			_was_on_floor = on_floor
			return
		_replay_wait = 0.0
	else:
		_replay_wait = 0.0

	_replay_time += delta
	if replay_loop and _replay_time >= float(last_index) / float(Timeline.TICK_RATE):
		_loop_restart()
	_was_on_floor = on_floor


## 录像里这一采样点的移动速度（米/秒）
func _segment_speed(index: int) -> float:
	var i0 := maxi(index - 1, 0)
	var i1 := mini(index + 1, replay_segment.size() - 1)
	var a: Vector3 = (replay_segment[i0]["transform"] as Transform3D).origin
	var b: Vector3 = (replay_segment[i1]["transform"] as Transform3D).origin
	var frames := float(maxi(i1 - i0, 1))
	return Vector3(b.x - a.x, 0.0, b.z - a.z).length() / (frames / float(Timeline.TICK_RATE))


## 录像放完一轮：瞬移回起点重新演（时间循环分身的经典表现）
func _loop_restart() -> void:
	_replay_loops += 1
	_replay_time = 0.0
	_replay_event_index = -1
	_replay_wait = 0.0
	var first: Dictionary = replay_segment[0]
	global_transform = first["transform"]
	velocity = first["velocity"]
	_model_root.rotation.y = float(first["model_yaw"])
	_play(String(first["anim"]), 0.0)


## 变成循环分身
## 注意：不要动 spawn_frame —— 那表示"这具身体从第几帧开始存在"，
## 老身体从第 0 帧就在了，只是身份从"本体"变成了"分身"。
func begin_replay(clone_index: int, segment: Array, segment_start_frame: int) -> void:
	mode = Mode.REPLAY
	replay_segment = segment.duplicate(true)
	replay_start_frame = segment_start_frame
	_replay_time = 0.0
	_replay_event_index = -1
	_replay_wait = 0.0
	_replay_loops = 0
	var color: Color = CLONE_COLORS[(clone_index - 1) % CLONE_COLORS.size()]
	display_name = "分身%d" % clone_index
	trail_color = Color(color.r, color.g, color.b, 0.65)
	set_body_tint(color, 0.55)
	_set_rewindable_meta()
	_state = ""
	_play(idle_clip, 0.0)


## 变回玩家操控的本体（回退到分裂之前时用）
func set_role_input() -> void:
	mode = Mode.INPUT
	replay_segment = []
	_replay_time = 0.0
	_replay_event_index = -1
	_replay_wait = 0.0
	display_name = "本体"
	trail_color = Color(0.97, 0.97, 1.0, 0.6)
	set_body_tint(white_albedo, 1.0)
	_set_rewindable_meta()
	_state = ""


func is_crouching() -> bool:
	return crouching


func is_clone() -> bool:
	return mode == Mode.REPLAY


func loop_count() -> int:
	return _replay_loops


func replay_progress() -> float:
	if replay_segment.is_empty():
		return 0.0
	return clampf(_replay_time / (float(replay_segment.size() - 1) / float(Timeline.TICK_RATE)), 0.0, 1.0)


func is_waiting() -> bool:
	return _replay_wait > 0.0


func _update_animation(on_floor: bool, delta: float) -> void:
	if _anim == null:
		return
	if _lock > 0.0:
		_lock = maxf(_lock - delta, 0.0)
		return

	var planar := Vector2(velocity.x, velocity.z).length()
	var next := "idle"
	# 刚离开地面的一两帧不算“空中”，避免出生/走下小台阶时闪跳
	if not on_floor and _air_time > 0.08:
		next = "air"
	elif crouching and planar > 0.15:
		next = "crouch"
	elif planar > 0.15:
		next = "run" if planar > walk_speed * 1.15 else "walk"
	if on_floor and not _was_on_floor:
		next = "land"

	if next != _state:
		_state = next
		match _state:
			"idle":
				_model_root.set_speed_scale(1.0)
				_play(idle_clip)
			"walk":
				_play(walk_clip)
			"crouch":
				_play(_model_root.crouch_clip)
			"run":
				_play(run_clip)
			"air":
				_play(jump_start_clip if velocity.y > 0.5 else jump_air_clip)
			"land":
				_play(jump_land_clip)
				_lock = 0.12

	if _state == "walk":
		_model_root.set_speed_scale(clampf(planar / maxf(walk_speed, 0.1), 0.5, 1.8))
	elif _state == "run":
		_model_root.set_speed_scale(clampf(planar / maxf(run_speed, 0.1), 0.6, 1.6))


func _play(clip: String, blend := blend_time) -> void:
	_model_root.play(clip, blend)


# --------------------------------------------------------------------------
# 外部调用
# --------------------------------------------------------------------------
func reset_to_spawn() -> void:
	velocity = Vector3.ZERO
	global_transform = spawn_transform
	_model_root.rotation.y = deg_to_rad(start_facing_degrees) + deg_to_rad(model_yaw_offset_degrees)
	_state = ""
	_lock = 0.0
	_air_time = 0.0
	if _anim:
		_play(idle_clip, 0.0)


# --------------------------------------------------------------------------
# 时间线接口（由 Rewindable 组件调用，见 scripts/core/timeline.gd）
# --------------------------------------------------------------------------
func tl_capture() -> Dictionary:
	return {
		"transform": global_transform,
		"interactions": _interaction_events.duplicate(),
		"replay_event_index": _replay_event_index,
		"velocity": velocity,
		"model_yaw": _model_root.rotation.y,
		"state": _state,
		"lock": _lock,
		"coyote": _coyote,
		"jump_buffer": _jump_buffer,
		"air_time": _air_time,
		"was_on_floor": _was_on_floor,
		"anim": _anim.current_animation if _anim != null else "",
		"anim_pos": _anim.current_animation_position if _anim != null else 0.0,
		"anim_speed": _anim.speed_scale if _anim != null else 1.0,
		"mode": mode,
		"replay_time": _replay_time,
		"replay_loops": _replay_loops,
		"crouching": crouching,
		"noise_timer": _noise_timer,
		"replay_wait": _replay_wait,
	}


func tl_restore(state: Dictionary) -> void:
	_replay_event_index = int(state.get("replay_event_index", -1))
	global_transform = state["transform"]
	velocity = state["velocity"]
	crouching = bool(state.get("crouching", false))
	_noise_timer = float(state.get("noise_timer", 0.0))
	_replay_wait = float(state.get("replay_wait", 0.0))
	_model_root.rotation.y = state["model_yaw"]
	_state = state["state"]
	_lock = state["lock"]
	_coyote = state["coyote"]
	_jump_buffer = state["jump_buffer"]
	_air_time = state["air_time"]
	_was_on_floor = state["was_on_floor"]
	if state.has("mode"):
		mode = int(state["mode"])
		_replay_time = float(state.get("replay_time", 0.0))
		_replay_loops = int(state.get("replay_loops", 0))
	if _anim != null and String(state["anim"]) != "":
		_anim.play(String(state["anim"]), 0.0)
		_anim.seek(float(state["anim_pos"]), true)
		_anim.speed_scale = float(state["anim_speed"])

## One physical input event is recorded with this snapshot; clones resolve the same endpoint.
func interact_nearest() -> bool:
	var nearest: Node3D
	var distance := INF
	for endpoint in get_tree().get_nodes_in_group("branch_interactable"):
		if endpoint.has_method("can_interact") and endpoint.can_interact(self):
			var d := global_position.distance_squared_to(endpoint.global_position)
			if d < distance:
				distance = d
				nearest = endpoint
	if nearest == null or not nearest.interact(self): return false
	var assembly := nearest.get_parent()
	_interaction_events.append({"assembly": String(assembly.get("instance_id")) if "instance_id" in assembly else "", "object": String(nearest.get("object_id")), "path": String(nearest.get_path())})
	return true

func _resolve_interaction(action: Dictionary) -> Node3D:
	for endpoint in get_tree().get_nodes_in_group("branch_interactable"):
		if String(endpoint.get("object_id")) != action.object: continue
		var assembly := endpoint.get_parent()
		if not String(action.assembly).is_empty():
			if "instance_id" in assembly and String(assembly.get("instance_id")) == action.assembly: return endpoint
		elif String(endpoint.get_path()) == action.path: return endpoint
	return null
