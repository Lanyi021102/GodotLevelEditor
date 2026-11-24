@tool
extends Node3D
## Fixed outer sizes, real hinged leaves, and one curve shared by both directions.
signal interacted(object_id: String, action: String, actor: Node3D)
signal state_changed(previous: String, current: String)
signal action_finished(action: String, success: bool)
signal region_entered(actor: Node3D)
signal region_exited(actor: Node3D)
signal power_changed(powered: bool)
@export var object_id := "door"
@export var display_name := ""
@export_enum("单开门 2×3 m", "双开门 4×3 m") var door_type := 0
@export_enum("close", "open") var initial_state := "close"
@export var interaction_enabled := true
@export var locked := false
@export var one_shot := false
@export_range(0.2, 6.0, 0.05) var interaction_radius := 2.5
@export_range(0.05, 30.0, 0.05) var motion_seconds := 1.2
@export var motion_curve: Curve = default_curve()
@export var frame_color := Color("52697f")
@export var leaf_color := Color("d8e0e8")
@export var use_metric_grid := true
var component_type: String:
	get: return "single_door" if door_type == 0 else "double_door"
var current_state := "close"
var progress := 0.0
var _target := 0.0
var _action := ""
var _used := false
var _generated: Node3D
var _leaves: Array[AnimatableBody3D] = []
var _signature := ""

static func default_curve(linear := false) -> Curve:
	var result := Curve.new()
	var mode := Curve.TANGENT_LINEAR if linear else Curve.TANGENT_FREE
	result.add_point(Vector2.ZERO, 0, 0, mode, mode)
	result.add_point(Vector2.ONE, 0, 0, mode, mode)
	return result

func _init() -> void: set_meta("mechanism_kind", "rotating_door")
func state_names() -> Array: return ["close", "moving", "open"]
func requestable_states() -> Array: return ["close", "open"]
func action_names() -> Array: return ["open", "close", "toggle"]
func get_state() -> String: return current_state
func is_open() -> bool: return current_state == "open"
func is_powered() -> bool: return is_open()
func door_dimensions() -> Vector2: return Vector2(2 if door_type == 0 else 4, 3)
func leaf_count() -> int: return 1 if door_type == 0 else 2
func angle_degrees() -> float: return 90.0 * clampf(motion_curve.sample(progress) if motion_curve != null else progress, 0, 1)
func motion_info() -> Dictionary:
	return {"state": current_state, "progress": progress, "angle": angle_degrees(), "target": _target, "seconds": motion_seconds, "leaves": leaf_count()}

func validate_component() -> PackedStringArray:
	var errors := PackedStringArray()
	if object_id.is_empty() or door_type not in [0, 1]: errors.append("门需要有效 ID 与单开/双开规格")
	if initial_state not in requestable_states(): errors.append("门的初始状态只能是 close 或 open")
	if not is_finite(motion_seconds) or motion_seconds <= 0 or not is_finite(interaction_radius) or interaction_radius <= 0: errors.append("门动画时长与交互距离必须为有限正数")
	if motion_curve == null or motion_curve.point_count < 2:
		errors.append("门的旋转动画需要 0° 到 90° 的曲线")
	else:
		if not motion_curve.get_point_position(0).is_equal_approx(Vector2.ZERO) or not motion_curve.get_point_position(motion_curve.point_count - 1).is_equal_approx(Vector2.ONE): errors.append("旋转曲线起终点必须是 (0,0) 与 (1,1)")
		for index in motion_curve.point_count:
			if not motion_curve.get_point_position(index).is_finite() or not is_finite(motion_curve.get_point_left_tangent(index)) or not is_finite(motion_curve.get_point_right_tangent(index)): errors.append("旋转曲线包含非有限值")
	return errors

func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("godot_level_editor_interactable")
		var prompt := preload("res://addons/godot_level_editor/scripts/ui/interaction_label.gd").new()
		prompt.configure(self, display_name if not display_name.is_empty() else "单开门" if door_type == 0 else "双开门", "[F]", true)
		prompt.position.y = 2.5
		add_child(prompt)
	rebuild_design(); reset_state()

func _design_signature() -> String:
	var points: Array = []
	if motion_curve != null:
		for index in motion_curve.point_count: points.append([motion_curve.get_point_position(index), motion_curve.get_point_left_tangent(index), motion_curve.get_point_right_tangent(index), motion_curve.get_point_left_mode(index), motion_curve.get_point_right_mode(index)])
	return var_to_str([door_type, initial_state, frame_color, leaf_color, use_metric_grid, points])

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _signature != _design_signature(): rebuild_design(); reset_state()
func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint(): advance(delta)

func reset_state() -> void:
	current_state = initial_state; progress = 1.0 if initial_state == "open" else 0.0
	_target = progress; _action = ""; _used = false; _apply_pose()

func can_interact(actor: Node3D = null) -> bool:
	if not interaction_enabled or locked or not is_visible_in_tree() or one_shot and _used: return false
	if actor == null: return Engine.is_editor_hint()
	return can_process() and actor.is_in_group("godot_level_editor_player") and actor.is_visible_in_tree() and actor.global_position.distance_to(global_position) <= interaction_radius

func interact(actor: Node3D = null) -> bool:
	if not can_interact(actor): return false
	# Input is routed through the visible graph: interaction -> rotation animation.
	_used = true; interacted.emit(object_id, "toggle", actor)
	return true

func request_state(state: String) -> Dictionary:
	if state not in requestable_states(): return {"ok": false, "reason": "门只能请求 close 或 open；moving 由动画产生"}
	return perform_action("open" if state == "open" else "close")

func perform_action(action: String) -> Dictionary:
	if action not in action_names(): return {"ok": false, "reason": "门不支持该动作：" + action}
	if not Engine.is_editor_hint() and (not is_visible_in_tree() or not can_process()): return {"ok": false, "reason": "门当前未启用"}
	var target := (1.0 - _target) if action == "toggle" else (1.0 if action == "open" else 0.0)
	if locked and target > 0.5: return {"ok": false, "reason": "门已锁定"}
	if is_equal_approx(target, _target) and current_state == "moving": return {"ok": true, "reason": "门正在前往该状态"}
	if is_equal_approx(target, progress) and current_state != "moving": return {"ok": true, "reason": "门已处于该状态"}
	if not _action.is_empty(): action_finished.emit(_action, false)
	_target = target; _action = action; _change_state("moving")
	return {"ok": true, "reason": "已开始旋转动画，等待门扇到位"}

func set_property_value(key: String, value: Variant) -> Dictionary:
	if key in ["locked", "interaction_enabled"] and value is bool: set(key, value)
	elif key == "motion_seconds" and (value is float or value is int) and is_finite(float(value)) and float(value) > 0: motion_seconds = float(value)
	else: return {"ok": false, "reason": "门不支持该属性或参数无效"}
	return {"ok": true, "reason": "门属性已更新"}

func advance(delta: float) -> void:
	if current_state != "moving": return
	progress = move_toward(progress, _target, maxf(delta, 0) / maxf(motion_seconds, 0.05))
	_apply_pose()
	if is_equal_approx(progress, _target):
		var finished := _action; _action = ""
		_change_state("open" if _target > 0.5 else "close")
		action_finished.emit(finished, true)

func _change_state(state: String) -> void:
	if current_state == state: return
	var old := current_state; var powered := is_powered(); current_state = state
	state_changed.emit(old, state)
	if powered != is_powered(): power_changed.emit(is_powered())

func _apply_pose() -> void:
	for index in _leaves.size(): _leaves[index].rotation.y = deg_to_rad(angle_degrees()) * (1 if index == 0 else -1)

func tl_capture() -> Dictionary:
	return {"state": current_state, "progress": progress, "target": _target, "action": _action, "used": _used, "locked": locked, "interaction_enabled": interaction_enabled, "motion_seconds": motion_seconds}
func tl_restore(data: Dictionary) -> void:
	current_state = str(data.get("state", current_state)); progress = clampf(float(data.get("progress", 0)), 0, 1)
	_target = float(data.get("target", progress)); _action = str(data.get("action", "")); _used = bool(data.get("used", false))
	locked = bool(data.get("locked", locked)); interaction_enabled = bool(data.get("interaction_enabled", interaction_enabled)); motion_seconds = float(data.get("motion_seconds", motion_seconds))
	_apply_pose() # Silent state restoration, never replay graph/task events.

func rebuild_design() -> void:
	if is_instance_valid(_generated): _generated.free()
	_leaves.clear()
	_generated = Node3D.new(); _generated.name = "DoorGeometry"; add_child(_generated)
	var frame := Node3D.new(); frame.name = "DoorFrame"; _generated.add_child(frame)
	var size_ := door_dimensions(); var thickness := 0.14
	_box(frame, "LeftPost", Vector3(thickness, size_.y, 0.24), Vector3(-size_.x / 2 + thickness / 2, size_.y / 2, 0), frame_color)
	_box(frame, "RightPost", Vector3(thickness, size_.y, 0.24), Vector3(size_.x / 2 - thickness / 2, size_.y / 2, 0), frame_color)
	_box(frame, "Lintel", Vector3(size_.x - 2 * thickness, thickness, 0.24), Vector3(0, size_.y - thickness / 2, 0), frame_color)
	var clear_width := size_.x - 2 * thickness
	var leaf_width := clear_width if door_type == 0 else (clear_width - 0.02) / 2
	for index in leaf_count():
		var body := AnimatableBody3D.new(); body.name = "LeftLeaf" if index == 0 else "RightLeaf"
		body.sync_to_physics = not Engine.is_editor_hint()
		body.position.x = (-1 if index == 0 else 1) * clear_width / 2
		_generated.add_child(body); _leaves.append(body)
		var offset := Vector3((1 if index == 0 else -1) * leaf_width / 2, (size_.y - thickness) / 2, 0)
		_box(body, "Leaf", Vector3(leaf_width, size_.y - thickness - 0.02, 0.10), offset, leaf_color, false)
		_box(body, "Handle", Vector3(0.05, 0.24, 0.16), Vector3((1 if index == 0 else -1) * (leaf_width - 0.12), 1.05, 0.10), frame_color, false, false)
	_signature = _design_signature(); _apply_pose()

func _box(parent: Node3D, name_: String, dimensions: Vector3, at: Vector3, color: Color, fixed := true, collision := true) -> void:
	var holder: Node3D = parent
	if fixed:
		holder = StaticBody3D.new(); holder.name = name_; parent.add_child(holder)
	var mesh := MeshInstance3D.new(); mesh.name = name_ + "Mesh"; mesh.mesh = BoxMesh.new(); mesh.mesh.size = dimensions
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = 0.8
	mesh.material_override = preload("res://addons/godot_level_editor/scripts/tools/metric_grid.gd").material(color) if use_metric_grid else material
	mesh.position = at; holder.add_child(mesh)
	if collision:
		var shape := CollisionShape3D.new(); shape.name = name_ + "Collision"; shape.shape = BoxShape3D.new(); shape.shape.size = dimensions; shape.position = at; holder.add_child(shape)
