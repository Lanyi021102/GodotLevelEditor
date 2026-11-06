extends Node
## 时间线内核（Autoload: Timeline）
##
## 设计依据：docs/GDD.md §4.1 / §10.3
##   - 固定 60 Hz：每个物理帧在所有实体移动完成之后录制一次世界状态
##   - 环形缓冲：默认保留最近 90 秒（buffer_seconds）
##   - 回退 = 把快照写回所有实体 + 冻结世界（不是重算），因此与物理求解器无关
##   - 通过则截断游标之后的帧，形成一条新分支
##
## 可回退实体只需实现两个方法（鸭子类型，见 scripts/core/rewindable.gd）：
##   tl_capture() -> Dictionary
##   tl_restore(state: Dictionary) -> void
##   tl_absent() -> void            # 可选：该帧还不存在（例如尚未分裂出的分身）

signal frame_captured(frame: int)
signal rewound(frame: int, time: float)
signal resumed(frame: int)
signal entity_registered(entity: Object, index: int)

## 约定：可回退实体的 tl_capture() 里用这个键存放世界位置，轨迹线据此绘制
const POSITION_KEY := "transform"

const TICK_RATE := 60

@export var buffer_seconds := 90.0

## 世界是否处于冻结（拖拽/预览）状态
var frozen := false
## 最新帧的绝对索引（-1 表示还没录到任何帧）
var head := -1
## 当前播放头（绝对索引），录制中它等于 head
var cursor := -1
## 缓冲里最旧帧的绝对索引
var first := 0

var _entities: Array = []
var _capacity := 0
var _states: Array = []

## 诊断：单帧录制耗时（微秒），用于性能预算（docs/GDD.md §10.3）
var capture_usec_last := 0
var capture_usec_peak := 0
var capture_usec_total := 0
var capture_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 必须晚于所有实体移动：保证录到的是「本帧结束」的状态
	process_physics_priority = 1000
	_capacity = maxi(int(buffer_seconds * TICK_RATE), TICK_RATE)
	_states.resize(_capacity)


func _physics_process(_delta: float) -> void:
	if frozen:
		return
	_capture()


# --------------------------------------------------------------------------
# 实体注册（槽位一经分配永不复用，保证历史帧的索引稳定）
# --------------------------------------------------------------------------
func register(entity: Object) -> void:
	if entity == null or _entities.has(entity):
		return
	_entities.append(entity)
	entity_registered.emit(entity, _entities.size() - 1)


func unregister(entity: Object) -> void:
	var i := _entities.find(entity)
	if i >= 0:
		_entities[i] = null


func entity_count() -> int:
	return _entities.size()


# --------------------------------------------------------------------------
# 录制
# --------------------------------------------------------------------------
func _capture() -> void:
	var _t0 := Time.get_ticks_usec()
	var index := head + 1
	var slot := index % _capacity
	var frame: Array = []
	frame.resize(_entities.size())
	for i in _entities.size():
		var e: Object = _entities[i]
		frame[i] = e.tl_capture() if is_instance_valid(e) else null
		if is_instance_valid(e) and e is Node and "spawn_frame" in e.get_parent():
			if e.get_parent().spawn_frame > index: frame[i] = null
	_states[slot] = frame
	head = index
	if head - first >= _capacity:
		first = head - _capacity + 1
	cursor = head
	capture_usec_last = Time.get_ticks_usec() - _t0
	capture_usec_peak = maxi(capture_usec_peak, capture_usec_last)
	capture_usec_total += capture_usec_last
	capture_count += 1
	frame_captured.emit(head)


# --------------------------------------------------------------------------
# 回退 / 推进
# --------------------------------------------------------------------------
func rewind_to_time(t: float) -> int:
	return rewind_to_frame(int(round(t * float(TICK_RATE))))


func rewind_to_frame(frame: int) -> int:
	if head < 0:
		return -1
	var f := clampi(frame, first, head)
	_apply(f)
	cursor = f
	_set_frozen(true)
	rewound.emit(f, time_of(f))
	return f


## 冻结状态下的逐帧微调（拖拽时间线用）
func scrub(frames: int) -> int:
	if not frozen:
		_set_frozen(true)
	return rewind_to_frame(clampi(cursor + frames, first, head))


## 从游标处继续推进：丢弃游标之后的帧，形成新分支
func resume() -> void:
	if head < 0:
		return
	if frozen:
		head = cursor
		_set_frozen(false)
	resumed.emit(cursor)


func clear() -> void:
	head = -1
	cursor = -1
	first = 0
	for i in _states.size():
		_states[i] = null
	_set_frozen(false)


## Slot indices may change only when no history exists. This bounds per-frame
## storage after repeated room restarts without invalidating historical snapshots.
func compact_entities() -> void:
	if head >= 0:
		return
	var alive: Array = []
	for entity in _entities:
		if is_instance_valid(entity):
			alive.append(entity)
	_entities = alive


func _apply(frame: int) -> void:
	var stored: Variant = _states[frame % _capacity]
	if stored == null:
		return
	var frame_states: Array = stored
	for i in _entities.size():
		var e: Object = _entities[i]
		if not is_instance_valid(e):
			continue
		if i >= frame_states.size():
			# 该时刻这个实体还没出现（例如之后才分裂出的分身）
			if e.has_method("tl_absent"):
				e.tl_absent()
			continue
		var state: Variant = frame_states[i]
		if state != null:
			e.tl_restore(state)
		elif e.has_method("tl_absent"):
			e.tl_absent()



func _set_frozen(value: bool) -> void:
	frozen = value
	get_tree().paused = value


# --------------------------------------------------------------------------
# 查询
# --------------------------------------------------------------------------
func time_of(frame: int) -> float:
	return float(frame) / float(TICK_RATE)


func duration() -> float:
	return time_of(head) if head >= 0 else 0.0


func cursor_time() -> float:
	return time_of(cursor)


## 缓冲覆盖的时间区间（秒）
func buffered_span() -> Vector2:
	if head < 0:
		return Vector2.ZERO
	return Vector2(time_of(first), time_of(head))


## Legacy query for old tools. Energy tracking has been removed.
func get_cost_at(_frame: int) -> float:
	return 0.0


func get_entity_index(entity: Object) -> int:
	return _entities.find(entity)


func get_entity_at(index: int) -> Object:
	if index < 0 or index >= _entities.size():
		return null
	return _entities[index]


## 取某实体在某一帧的世界位置（没有则返回 null）
func get_position_at(entity_index: int, frame: int) -> Variant:
	var frame_states: Variant = get_frame_state(frame)
	if frame_states == null or entity_index < 0 or entity_index >= frame_states.size():
		return null
	var state: Variant = frame_states[entity_index]
	if state == null or not (state is Dictionary) or not state.has(POSITION_KEY):
		return null
	return (state[POSITION_KEY] as Transform3D).origin


## 轨迹采样：从缓冲最旧帧一路采到游标（所以回退后线会跟着变短）
## max_points 控制点数上限，超出就自动加大采样步长。
func get_positions(entity_index: int, max_points := 400) -> PackedVector3Array:
	var out := PackedVector3Array()
	if head < 0 or entity_index < 0:
		return out
	var count := cursor - first + 1
	if count <= 0:
		return out
	var step := maxi(1, int(ceil(float(count) / float(maxi(max_points, 2)))))
	var f := first
	while f <= cursor:
		var p: Variant = get_position_at(entity_index, f)
		if p != null:
			out.append(p)
		f += step
	var last: Variant = get_position_at(entity_index, cursor)
	if last != null and (out.is_empty() or out[out.size() - 1].distance_to(last) > 0.0001):
		out.append(last)
	return out


## 取出某实体 [from_frame, to_frame] 的状态快照（分裂时把这段时间的录像交给分身）
func capture_segment(entity_index: int, from_frame: int, to_frame: int) -> Array:
	var out: Array = []
	if head < 0 or entity_index < 0:
		return out
	for f in range(maxi(from_frame, first), mini(to_frame, head) + 1):
		var p: Variant = get_position_at(entity_index, f)
		var frame_states: Variant = get_frame_state(f)
		if frame_states == null or entity_index >= frame_states.size():
			continue
		var st: Variant = frame_states[entity_index]
		if st == null or not (st is Dictionary):
			continue
		if p == null:
			continue
		out.append(st)
	return out


## 只把 head 收回游标（形成新分支），但不解冻——分裂过程中要一直保持冻结
func truncate_to_cursor() -> void:
	if head < 0:
		return
	head = cursor


func get_frame_state(frame: int) -> Variant:
	if head < 0:
		return null
	var f := clampi(frame, first, head)
	return _states[f % _capacity]


## 平均单帧录制耗时（微秒）
func capture_usec_average() -> float:
	return float(capture_usec_total) / float(capture_count) if capture_count > 0 else 0.0


func is_valid_frame(frame: int) -> bool:
	return head >= 0 and frame >= first and frame <= head
