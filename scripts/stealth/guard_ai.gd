class_name GuardAI
extends CharacterBody3D
## 巡逻守卫（docs/GDD.md §6）
##
## 状态机：巡逻 PATROL → 怀疑 SUSPICIOUS → 警戒 ALERT（暴露）→ 搜索 SEARCH。
##   - 视锥里看到目标 → 警觉值按 alert_rate 累积；脱离视野按 alert_decay 衰减
##   - 警觉满 = 暴露：扣 expose_penalty 能量 + 进入 expose_duration 秒警戒，
##     并通知 help_radius 内的同伴一起去最后已知位置
##   - 听到噪音 → 前往查看（噪音来源可能是分身——这就是诱饵机制）
##
## 守卫也是可回退实体：位置/朝向/警觉值/状态/计时器全部进时间线快照，
## 所以"回退抹掉被发现"是天然成立的。

signal spotted(target: Node3D, position: Vector3)

enum State { PATROL, SUSPICIOUS, ALERT, SEARCH }

const GuardTemplate := preload("res://addons/enemy_editor/runtime/guard_template.gd")
const DEFAULT_DEFINITION := "res://resources/enemies/guard_default.tres"
const STATE_IDS := ["patrol", "suspicious", "alert", "search"]

const STATE_NAMES := ["巡逻", "怀疑", "警戒", "搜索"]
const CLIP_IDLE := "Idle"
const CLIP_WALK := "Walking_A"
const CLIP_RUN := "Running_A"

@export_group("敌人蓝图")
## 留空时使用首个模板并沿用原有参数。显式赋值后以定义为准。
@export var enemy_definition: EnemyDefinition
## 编辑器分配的场景实例标识；复制场景对象时由插件重新分配。
@export var enemy_instance_id := ""
## 可选：子 Marker3D 为巡逻点；与 patrol_points 二选一，路点节点优先。
@export_node_path("Node3D") var patrol_route: NodePath

@export_group("巡逻")
## 巡逻路点（世界坐标，按顺序循环）
@export var patrol_points: Array[Vector3] = []
@export var patrol_speed := 2.0
@export var investigate_speed := 3.2
@export var chase_speed := 4.8
@export var waypoint_wait := 1.5

@export_group("感知（GDD §6.1 参数表）")
@export var alert_rate := 100.0
@export var alert_decay := 40.0
## 听到噪音后的初始警觉值
@export var noise_alert := 25.0
@export var expose_penalty := 25.0
@export var expose_duration := 8.0
@export var search_time := 6.0
@export var help_radius := 12.0

@export_group("表现")
@export var tint := Color(0.90, 0.32, 0.26)
@export var turn_speed := 8.0
@export var gravity := 24.0
@export var accel := 18.0

var _machine := EnemyMachine.new()
var state: int:
	get: return STATE_IDS.find(_machine.state_id)
	set(value):
		if value >= 0 and value < STATE_IDS.size(): _machine.state_id = STATE_IDS[value]
var alert_level := 0.0
var look_dir := Vector3(0.0, 0.0, -1.0)
var last_known := Vector3.ZERO
var has_last_known := false

var _model: CharacterModel
var _cone: VisionCone
var _patrol_index := 0
var _state_timer: float:
	get: return _machine.timer
	set(value): _machine.timer = value
var _debug_clock := 0.0
var _dispatching_enemy_event := false
var _waypoint_timer := 0.0
var _target: Node3D = null
var _saw_last_frame := false
var _anim_state := ""


func _ready() -> void:
	_configure_enemy()
	if _machine.definition != null and _machine.definition.appearance != null:
		var previous := get_node("ModelRoot")
		remove_child(previous)
		previous.queue_free()
		var visual := preload("res://addons/enemy_editor/npc_visual.gd").new()
		visual.name = "ModelRoot"
		visual.appearance = _machine.definition.appearance
		add_child(visual)
	var route := get_node_or_null(patrol_route) if not patrol_route.is_empty() else null
	if route != null:
		patrol_points.clear()
		for point in route.get_children():
			if point is Marker3D: patrol_points.append(point.global_position)
	# 和玩家同层：角色之间不互相碰撞，只跟世界（第 1 层）碰撞
	collision_layer = 2
	collision_mask = 1
	add_to_group("guard")
	add_to_group("hearing")
	_model = $ModelRoot
	_cone = $VisionCone
	if _model != null:
		_model.set_tint(tint, 1.0)
	if not patrol_points.is_empty():
		last_known = patrol_points[0]
		has_last_known = true


func _physics_process(delta: float) -> void:
	_perceive(delta)
	_think(delta)
	_move(delta)
	_animate()
	_debug_clock += delta
	if _debug_clock >= 0.1:
		_debug_clock = 0.0
		_report_enemy_state(false)


# --------------------------------------------------------------------------
# 感知
# --------------------------------------------------------------------------
func _perceive(delta: float) -> void:
	if _cone == null:
		return
	_cone.look_dir = look_dir
	var sight := _cone.scan(alert_level)
	_saw_last_frame = sight["seen"]
	if _saw_last_frame:
		_target = sight["target"]
		if _target != null:
			last_known = _target.global_position
			has_last_known = true
		alert_level = minf(alert_level + alert_rate * delta, 100.0)
	else:
		_target = null
		alert_level = maxf(alert_level - alert_decay * delta, 0.0)
	_evaluate_enemy("perception")


## 暴露：扣能量 + 进入警戒 + 喊人（GDD §6.2）
func _expose() -> void:
	spotted.emit(_target, last_known)
	for node in get_tree().get_nodes_in_group("guard"):
		if node == self or not (node is GuardAI):
			continue
		var other := node as GuardAI
		if other.global_position.distance_to(global_position) <= help_radius:
			other.receive_help(last_known)


## 收到同伴求援
func receive_help(position: Vector3) -> void:
	if not _accepts_enemy_event("help"):
		return
	last_known = position
	has_last_known = true
	alert_level = maxf(alert_level, noise_alert * 2.0)
	_evaluate_enemy("help")


## 听到噪音（由 Noise 自动调用）
func heard_noise(position: Vector3, radius: float, _source: Object) -> bool:
	var flat := Vector3(position.x - global_position.x, 0.0, position.z - global_position.z)
	if flat.length() > radius:
		return false
	if _accepts_enemy_event("noise"):
		last_known = position
		has_last_known = true
		alert_level = maxf(alert_level, noise_alert)
		_evaluate_enemy("noise")
	return true


# --------------------------------------------------------------------------
# 状态机与移动
# --------------------------------------------------------------------------
func _think(delta: float) -> void:
	_machine.advance(delta)
	_evaluate_enemy("tick")

func _move_target() -> Vector3:
	match str(_machine.current().get("behavior", "idle")):
		"patrol":
			return patrol_points[_patrol_index % patrol_points.size()] if not patrol_points.is_empty() else global_position
		"chase":
			if _target != null and is_instance_valid(_target): return _target.global_position
			return last_known if has_last_known else global_position
		"investigate":
			return last_known if has_last_known else global_position
	return global_position

func _move(delta: float) -> void:
	var target := _move_target()
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var distance := to.length()
	var arrived := distance < 0.45
	var speed := 0.0
	if not arrived:
		speed = float(_machine.current().get("speed", 0.0))

	# 巡逻点停留
	if _machine.current().get("behavior") == "patrol" and not patrol_points.is_empty() and arrived:
		_waypoint_timer -= delta
		if _waypoint_timer <= 0.0:
			_patrol_index = (_patrol_index + 1) % patrol_points.size()
			_waypoint_timer = waypoint_wait

	var desired := Vector3.ZERO
	if speed > 0.0 and distance > 0.01:
		desired = to.normalized() * speed
	velocity.x = move_toward(velocity.x, desired.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta)
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= gravity * delta
	move_and_slide()

	# 朝向：走动时朝移动方向；搜索/怀疑且已到位时原地转身张望
	var face := desired
	if face.length_squared() < 0.01 and distance < 0.45:
		if float(_machine.current().get("scan_degrees", 0.0)) > 0.0:
			look_dir = look_dir.rotated(Vector3.UP, deg_to_rad(float(_machine.current().scan_degrees)) * delta)
			face = look_dir
		else:
			face = look_dir
	if face.length_squared() > 0.01:
		var want := Vector3(face.x, 0.0, face.z).normalized()
		look_dir = look_dir.lerp(want, minf(1.0, turn_speed * delta))
		if look_dir.length_squared() > 0.0001:
			look_dir = look_dir.normalized()
	if _model != null:
		_model.rotation.y = atan2(look_dir.x, look_dir.z)


func _animate() -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var next := "idle"
	if planar > 0.2:
		next = "run" if planar > 3.4 else "walk"
	if next == _anim_state or _model == null:
		return
	_anim_state = next
	match next:
		"idle":
			_model.play(CLIP_IDLE)
		"walk":
			_model.play(CLIP_WALK)
		_:
			_model.play(CLIP_RUN)


# --------------------------------------------------------------------------
# 供 HUD / 测试
# --------------------------------------------------------------------------
func state_name() -> String:
	return str(_machine.current().get("label", "?"))


## 被盯上的最后已知位置（HUD / 测试用）
func spotted_target_pos() -> Vector3:
	return last_known


## 当前状态剩余时间
func state_timer() -> float:
	return _state_timer


func is_alerted() -> bool:
	return state == State.ALERT


func sees_target() -> bool:
	return _saw_last_frame


# --------------------------------------------------------------------------
# 时间线接口
# --------------------------------------------------------------------------
func tl_capture() -> Dictionary:
	return {
		"transform": global_transform,
		"velocity": velocity,
		"look_dir": look_dir,
		"state": state,
		"enemy_machine": _machine.capture(),
		"saw_target": _saw_last_frame,
		"target_path": _target.get_path() if is_instance_valid(_target) else NodePath(),
		"alert": alert_level,
		"timer": _state_timer,
		"patrol_index": _patrol_index,
		"waypoint_timer": _waypoint_timer,
		"last_known": last_known,
		"has_last_known": has_last_known,
		"anim_state": _anim_state,
		"anim": _model.current_clip() if _model != null else "",
		"anim_pos": _model.anim.current_animation_position if (_model != null and _model.anim != null and _model.current_clip() != "") else 0.0,
	}


func tl_restore(state_data: Dictionary) -> void:
	global_transform = state_data["transform"]
	velocity = state_data["velocity"]
	look_dir = state_data["look_dir"]
	if state_data.has("enemy_machine"):
		if not _machine.restore(state_data["enemy_machine"]):
			push_error("敌人快照与当前定义不匹配")
	else:
		state = int(state_data["state"])
		_machine.last_transition = ""
		_machine.last_reason = ""
	alert_level = float(state_data["alert"])
	_state_timer = float(state_data["timer"])
	_patrol_index = int(state_data["patrol_index"])
	_waypoint_timer = float(state_data["waypoint_timer"])
	last_known = state_data["last_known"]
	has_last_known = bool(state_data["has_last_known"])
	_anim_state = String(state_data["anim_state"])
	var target_path: NodePath = state_data.get("target_path", NodePath())
	_target = get_node_or_null(target_path) as Node3D if not target_path.is_empty() else null
	_saw_last_frame = bool(state_data.get("saw_target", false))
	_report_enemy_state(true)
	if _model != null:
		_model.rotation.y = atan2(look_dir.x, look_dir.z)
		if String(state_data["anim"]) != "":
			_model.play(String(state_data["anim"]), 0.0)
			if _model.anim != null:
				_model.anim.seek(float(state_data["anim_pos"]), true)


func _configure_enemy() -> void:
	var source := enemy_definition
	if source == null:
		source = load(DEFAULT_DEFINITION) as EnemyDefinition
		if source == null: source = GuardTemplate.create()
		source = source.duplicate(true)
		for id in STATE_IDS:
			var entry := source.state_by_id(id)
			entry.speed = patrol_speed if id == "patrol" else (chase_speed if id == "alert" else investigate_speed)
			entry.duration = expose_duration if id == "alert" else (0.0 if id == "patrol" else search_time)
		for key in EnemyDefinition.PARAM_DEFAULTS: source.parameters[key] = get(key)
	if not _machine.configure(source):
		push_error("敌人定义无效，已停止该守卫：" + "; ".join(source.validate()))
		set_physics_process(false)
		return
	if enemy_definition != null:
		for key in EnemyDefinition.PARAM_DEFAULTS: set(key, _machine.definition.parameters[key])

func _enemy_facts() -> Dictionary:
	return {"seen": _saw_last_frame, "has_last_known": has_last_known, "alert": alert_level}

func _accepts_enemy_event(event: String) -> bool:
	if _dispatching_enemy_event or _machine.definition == null: return false
	for edge in _machine.definition.transitions:
		if edge.from == _machine.state_id and edge.event == event: return true
	return false

func _evaluate_enemy(event: String) -> void:
	if _dispatching_enemy_event: return
	_dispatching_enemy_event = true
	var edge := _machine.evaluate(event, _enemy_facts())
	if not edge.is_empty():
		if edge.effect == "expose": _expose()
		_report_enemy_state(false)
	_dispatching_enemy_event = false

func enemy_runtime_state() -> Dictionary:
	var data := _machine.capture()
	data["instance"] = str(get_path())
	data["instance_id"] = enemy_instance_id
	data["definition"] = enemy_definition.resource_path if enemy_definition != null else DEFAULT_DEFINITION
	data["behavior"] = _machine.current().get("behavior", "idle")
	data["speed"] = _machine.current().get("speed", 0.0)
	data["alert"] = alert_level
	data["seen"] = _saw_last_frame
	data["position"] = global_position
	return data

func _report_enemy_state(rewound: bool) -> void:
	if not EngineDebugger.is_active() or not is_inside_tree(): return
	var data := enemy_runtime_state()
	data["rewound"] = rewound
	EngineDebugger.send_message("godot_level_editor_enemy:state", [data])

func _exit_tree() -> void:
	if EngineDebugger.is_active(): EngineDebugger.send_message("godot_level_editor_enemy:remove", [str(get_path())])
