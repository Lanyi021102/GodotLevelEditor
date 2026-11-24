@tool
extends Node3D
## Shared first-batch component contract. Runtime state never modifies the definition.
signal interacted(object_id: String, action: String, actor: Node3D)
signal state_changed(previous: String, current: String)
signal action_finished(action: String, success: bool)
signal region_entered(actor: Node3D)
signal region_exited(actor: Node3D)
signal power_changed(powered: bool)
const KINDS := ["button", "toggle_switch", "pressure_plate", "sliding_door", "hinged_door", "lift_platform", "terminal"]
const TITLES := {"button": "按钮", "toggle_switch": "拉杆", "pressure_plate": "压力板", "sliding_door": "滑动门", "hinged_door": "旋转门", "lift_platform": "升降台", "terminal": "交互终端"}
const STATES := {
	"button": ["idle", "pressed"], "toggle_switch": ["off", "on"], "pressure_plate": ["released", "pressed"],
	"sliding_door": ["closed", "opening", "open", "closing"], "hinged_door": ["closed", "opening", "open", "closing"],
	"lift_platform": ["at_start", "moving", "at_end", "stopped"], "terminal": ["offline", "ready", "activated"]}
const ACTIONS := {
	"button": ["press", "release"], "toggle_switch": ["toggle", "turn_on", "turn_off"], "pressure_plate": [],
	"sliding_door": ["open", "close", "toggle"], "hinged_door": ["open", "close", "toggle"],
	"lift_platform": ["move_to_end", "move_to_start", "toggle", "stop"], "terminal": ["activate", "enable", "disable", "reset"]}
@export_enum("button", "toggle_switch", "pressure_plate", "sliding_door", "hinged_door", "lift_platform", "terminal") var component_type := "button"
@export var object_id := "component"
@export var display_name := ""
@export var initial_state := ""
@export var interaction_enabled := true
@export var locked := false
@export var one_shot := false
@export_range(0.2, 6.0, 0.05) var interaction_radius := 2.0
@export_range(0.0, 60.0, 0.05) var reset_after := 0.5
@export_range(0.0, 15.0, 0.05) var release_delay := 0.25
@export_range(1, 16) var required_occupants := 1
@export_flags_3d_physics var sensor_mask := 6
@export var accept_physics_bodies := true
@export_range(0.05, 30.0, 0.05) var motion_seconds := 1.2
@export var travel_offset := Vector3(0, 3, 0)
@export_range(-170.0, 170.0, 1.0) var open_angle := -95.0
@export var color_idle := Color("d8e0e8")
@export var color_active := Color("64cbb5")
@export var custom_states := PackedStringArray()
## Each rule has from/action/to string fields; * in from accepts any state.
@export var transition_rules: Array[Dictionary] = []
var current_state := ""
var progress := 0.0
var _target := 0.0
var _moving := false
var _action := ""
var _reset_timer := 0.0
var _release_timer := 0.0
var _used := false
var _preview_occupants := -1
var _inside: Dictionary = {}
var _sensor_grace := 0
var _generated: Node3D
var _motion: Node3D
var _sensor: Area3D
var _label: Label3D
var _active_material: StandardMaterial3D
var _signature := ""

func _init() -> void:
	set_meta("mechanism_kind", "stateful")

func state_names() -> Array:
	var result: Array = STATES.get(component_type, []).duplicate()
	for value in custom_states:
		if not result.has(value): result.append(value)
	return result

func requestable_states() -> Array:
	return state_names().filter(func(value: String): return value not in ["opening", "closing", "moving", "stopped"] and component_type != "pressure_plate")

func action_names() -> Array:
	var result: Array = ACTIONS.get(component_type, []).duplicate()
	for rule in transition_rules:
		var action := str(rule.get("action", ""))
		if not action.is_empty() and not result.has(action): result.append(action)
	return result

func get_state() -> String: return current_state
func is_open() -> bool: return current_state == "open"
func is_powered() -> bool: return current_state in ["pressed", "on", "open", "at_end", "activated"]

func validate_component() -> PackedStringArray:
	var errors := PackedStringArray()
	if component_type not in KINDS: errors.append("未知机关组件类型")
	if object_id.is_empty(): errors.append("机关组件缺少稳定 ID")
	if not initial_state.is_empty() and initial_state not in requestable_states() and not (component_type == "pressure_plate" and initial_state == "released"): errors.append("初始状态必须是可停留的有效状态")
	if motion_seconds <= 0 or not is_finite(motion_seconds): errors.append("动作时长必须为有限正数")
	if not travel_offset.is_finite() or (component_type == "lift_platform" and travel_offset.is_zero_approx()): errors.append("升降台目标偏移必须有效且非零")
	if interaction_radius <= 0 or not is_finite(interaction_radius) or reset_after < 0 or not is_finite(reset_after) or release_delay < 0 or not is_finite(release_delay) or required_occupants < 1: errors.append("交互距离、计时或占位数量无效")
	if not is_finite(open_angle) or (component_type == "hinged_door" and is_zero_approx(open_angle)): errors.append("旋转门开门角度必须有限且非零")
	var custom := {}
	for value in custom_states:
		if not value.is_valid_identifier() or custom.has(value) or STATES.get(component_type, []).has(value): errors.append("自定义状态 ID 必须有效、唯一且不与内置状态重复：" + value)
		custom[value] = true
	var seen := {}
	for rule in transition_rules:
		var from := str(rule.get("from", "")); var to := str(rule.get("to", "")); var action := str(rule.get("action", ""))
		if (from != "*" and from not in state_names()) or to not in requestable_states() or not action.is_valid_identifier(): errors.append("状态转换需要有效 from/action/to，目标不能是动画过渡状态")
		var key := from + "/" + action
		if seen.has(key): errors.append("状态转换重复：" + key)
		seen[key] = true
	return errors

func _ready() -> void:
	set_meta("mechanism_kind", component_type)
	if not Engine.is_editor_hint() and component_type != "pressure_plate": add_to_group("godot_level_editor_interactable")
	rebuild_design(); reset_state(); _sensor_grace = 0

func _design_signature() -> String:
	return var_to_str([component_type, display_name, initial_state, color_idle, color_active, travel_offset, open_angle, sensor_mask, custom_states, transition_rules])

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _signature != _design_signature(): rebuild_design(); reset_state()

func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint(): advance(delta)

func reset_state() -> void:
	current_state = initial_state if not initial_state.is_empty() else str(STATES.get(component_type, ["idle"])[0])
	progress = 1.0 if current_state in ["open", "at_end"] else 0.0
	_target = progress; _moving = false; _action = ""; _used = false
	_reset_timer = reset_after if current_state == "pressed" else 0.0
	_release_timer = 0.0; _inside.clear(); _sensor_grace = 2
	_apply_pose()

func can_interact(actor: Node3D = null) -> bool:
	if not interaction_enabled or locked or not is_visible_in_tree() or (one_shot and _used): return false
	if actor == null: return Engine.is_editor_hint()
	return can_process() and actor.is_in_group("godot_level_editor_player") and actor.is_visible_in_tree() and actor.global_position.distance_to(interaction_position()) <= interaction_radius

func interaction_position() -> Vector3:
	return global_transform * (travel_offset * progress) if component_type == "lift_platform" else global_position

func interact(actor: Node3D = null) -> bool:
	if not can_interact(actor): return false
	var action: String = {"button": "press", "toggle_switch": "toggle", "terminal": "activate"}.get(component_type, "toggle")
	for rule in transition_rules:
		if rule.get("action") == "interact" and rule.get("from") in ["*", current_state]: action = "interact"; break
	var result := perform_action(action)
	if not result.ok: return false
	_used = true
	interacted.emit(object_id, action, actor)
	return true

func request_state(state: String) -> Dictionary:
	if state not in requestable_states(): return {"ok": false, "reason": "目标状态不可请求：" + state}
	if state == current_state and not _moving: return {"ok": true, "reason": "已处于目标状态"}
	for rule in transition_rules:
		if rule.get("to") == state and rule.get("from") in ["*", current_state]: return perform_action(str(rule.action))
	var action: String = {"pressed": "press", "idle": "release", "on": "turn_on", "off": "turn_off", "open": "open", "closed": "close", "at_end": "move_to_end", "at_start": "move_to_start", "activated": "activate", "ready": "enable", "offline": "disable"}.get(state, "")
	if not ACTIONS.get(component_type, []).has(action): return {"ok": false, "reason": "当前状态没有到该状态的转换规则"}
	return perform_action(action)

func perform_action(action: String) -> Dictionary:
	if not Engine.is_editor_hint() and (not is_visible_in_tree() or not can_process()): return {"ok": false, "reason": "机关当前未启用"}
	if action not in action_names(): return {"ok": false, "reason": "机关不支持动作：" + action}
	for rule in transition_rules:
		if rule.get("action") == action and rule.get("from") in ["*", current_state]:
			if locked: return {"ok": false, "reason": "机关已锁定"}
			var target := str(rule.to)
			if component_type in ["sliding_door", "hinged_door"] and target in ["open", "closed"]: return _start_motion(target == "open", action)
			if component_type == "lift_platform" and target in ["at_start", "at_end"]: return _start_motion(target == "at_end", action)
			_change_state(target); action_finished.emit(action, true)
			return {"ok": true, "reason": "状态转换完成"}
	if action not in ACTIONS.get(component_type, []): return {"ok": false, "reason": "当前状态没有该自定义动作的可用转换：" + action}
	if component_type in ["sliding_door", "hinged_door", "lift_platform"]:
		if action == "stop":
			if _moving: action_finished.emit(_action, false)
			_moving = false; _action = ""; _change_state("stopped")
			action_finished.emit("stop", true)
			return {"ok": true, "reason": "已停止"}
		var forward := action in ["open", "move_to_end"] or (action == "toggle" and (_target < 0.5 if _moving else progress < 0.5))
		return _start_motion(forward, action)
	if locked: return {"ok": false, "reason": "机关已锁定"}
	match component_type:
		"button":
			if action == "press" and (current_state == "pressed" or (one_shot and _used)): return {"ok": false, "reason": "按钮已按下或已使用"}
			_change_state("pressed" if action == "press" else "idle"); _reset_timer = reset_after if action == "press" else 0.0
		"toggle_switch": _change_state("off" if action == "turn_off" or (action == "toggle" and current_state == "on") else "on")
		"terminal":
			if action == "activate" and current_state != "ready": return {"ok": false, "reason": "终端尚未就绪或已经激活"}
			_change_state({"activate": "activated", "enable": "ready", "disable": "offline", "reset": "ready"}[action])
		_: return {"ok": false, "reason": "该状态只能由实际占位驱动"}
	action_finished.emit(action, true)
	return {"ok": true, "reason": "动作完成"}

func _start_motion(forward: bool, action: String) -> Dictionary:
	if locked and forward: return {"ok": false, "reason": "机关已锁定"}
	var target := 1.0 if forward else 0.0
	if is_equal_approx(progress, target) and not _moving: return {"ok": true, "reason": "已经到达目标位置"}
	if _moving and is_equal_approx(_target, target): return {"ok": true, "reason": "正在前往目标"}
	if _moving: action_finished.emit(_action, false)
	_target = target; _moving = true; _action = action
	_change_state("moving" if component_type == "lift_platform" else "opening" if forward else "closing")
	return {"ok": true, "reason": "指令已接受，等待实际到位"}

func set_property_value(key: String, value: Variant) -> Dictionary:
	if key in ["locked", "interaction_enabled"] and value is bool: set(key, value)
	elif key in ["motion_seconds", "reset_after"] and (value is float or value is int) and is_finite(float(value)) and (float(value) > 0 if key == "motion_seconds" else float(value) >= 0): set(key, float(value))
	else: return {"ok": false, "reason": "属性或参数无效"}
	_apply_pose()
	return {"ok": true, "reason": "机关属性已更新"}

func set_powered(value: bool) -> void:
	var state: String = {"button": "pressed" if value else "idle", "toggle_switch": "on" if value else "off", "terminal": "activated" if value else "ready", "sliding_door": "open" if value else "closed", "hinged_door": "open" if value else "closed", "lift_platform": "at_end" if value else "at_start"}.get(component_type, "")
	if not state.is_empty(): request_state(state)

func set_preview_powered(value: bool) -> void:
	if Engine.is_editor_hint() and component_type == "pressure_plate":
		_preview_occupants = required_occupants if value else 0

func _eligible(body: Node3D) -> bool:
	return is_instance_valid(body) and body.is_visible_in_tree() and body.can_process() and (body.is_in_group("godot_level_editor_player") or body.is_in_group("stealth_target") or (accept_physics_bodies and body is RigidBody3D))

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	# Reassert local pose after parent placement/restore; AnimatableBody synchronizes world transforms.
	if _motion is AnimatableBody3D and not _moving: _apply_pose()
	if _sensor_grace > 0: _sensor_grace -= 1
	if is_instance_valid(_sensor) and not Engine.is_editor_hint():
		var present := {}
		for body in _sensor.get_overlapping_bodies():
			if _eligible(body): present[body.get_instance_id()] = body
		if _sensor_grace == 0:
			for id in present:
				if not _inside.has(id): region_entered.emit(present[id])
			for id in _inside:
				if not present.has(id) and is_instance_valid(_inside[id]): region_exited.emit(_inside[id])
		_inside = present
	if component_type == "pressure_plate":
		var count := _preview_occupants if Engine.is_editor_hint() and _preview_occupants >= 0 else _inside.size()
		if count >= required_occupants: _release_timer = release_delay; _change_state("pressed")
		elif current_state == "pressed":
			_release_timer = maxf(0.0, _release_timer - delta)
			if _release_timer <= 0: _change_state("released")
	if component_type == "button" and current_state == "pressed" and reset_after > 0:
		_reset_timer = maxf(0, _reset_timer - delta)
		if _reset_timer <= 0: _change_state("idle")
	if _moving:
		progress = move_toward(progress, _target, delta / maxf(motion_seconds, 0.05))
		_apply_pose()
		if is_equal_approx(progress, _target):
			_moving = false
			var action := _action; _action = ""
			_change_state(("at_end" if _target > 0.5 else "at_start") if component_type == "lift_platform" else ("open" if _target > 0.5 else "closed"))
			action_finished.emit(action, true)

func _change_state(value: String) -> void:
	if value == current_state: return
	var was_powered := is_powered(); var old := current_state
	current_state = value
	if component_type == "button": _reset_timer = reset_after if value == "pressed" else 0.0
	_apply_pose()
	state_changed.emit(old, value)
	if was_powered != is_powered(): power_changed.emit(is_powered())

func tl_capture() -> Dictionary:
	return {"state": current_state, "progress": progress, "target": _target, "moving": _moving, "action": _action, "reset_timer": _reset_timer, "release_timer": _release_timer, "used": _used, "locked": locked, "interaction_enabled": interaction_enabled, "motion_seconds": motion_seconds, "reset_after": reset_after}

func tl_restore(data: Dictionary) -> void:
	current_state = str(data.get("state", current_state)); progress = clampf(float(data.get("progress", 0)), 0, 1)
	_target = clampf(float(data.get("target", progress)), 0, 1); _moving = bool(data.get("moving", false)); _action = str(data.get("action", ""))
	_reset_timer = float(data.get("reset_timer", 0)); _release_timer = float(data.get("release_timer", 0)); _used = bool(data.get("used", false))
	locked = bool(data.get("locked", locked)); interaction_enabled = bool(data.get("interaction_enabled", interaction_enabled))
	motion_seconds = float(data.get("motion_seconds", motion_seconds)); reset_after = float(data.get("reset_after", reset_after))
	_sensor_grace = 2; _apply_pose() # Silent: restoring never replays state, action or interaction events.

func rebuild_design() -> void:
	if is_instance_valid(_generated): _generated.free()
	set_meta("mechanism_kind", component_type)
	_generated = Node3D.new(); _generated.name = "Generated"; add_child(_generated)
	_motion = null; _sensor = null
	_active_material = StandardMaterial3D.new(); _active_material.roughness = 0.7
	var frame := StandardMaterial3D.new(); frame.albedo_color = Color("52697f"); frame.roughness = 0.8
	var base := StandardMaterial3D.new(); base.albedo_color = color_idle; base.roughness = 0.8
	match component_type:
		"button":
			_box_body("Pedestal", Vector3(0.55, 0.65, 0.55), Vector3(0, 0.325, 0), _generated, frame)
			_motion = Node3D.new(); _generated.add_child(_motion)
			_mesh("Cap", Vector3(0.4, 0.1, 0.4), Vector3(0, 0.72, 0), _motion, _active_material)
		"toggle_switch":
			_box_body("Housing", Vector3(0.5, 0.75, 0.45), Vector3(0, 0.375, 0), _generated, frame)
			_motion = Node3D.new(); _motion.position.y = 0.65; _generated.add_child(_motion)
			_mesh("Handle", Vector3(0.08, 0.65, 0.08), Vector3(0, 0.3, 0.25), _motion, _active_material)
			_mesh("Grip", Vector3(0.4, 0.1, 0.12), Vector3(0, 0.65, 0.25), _motion, _active_material)
		"pressure_plate":
			_motion = Node3D.new(); _generated.add_child(_motion)
			_mesh("Plate", Vector3(2.2, 0.1, 2.2), Vector3(0, 0.05, 0), _motion, _active_material)
		"sliding_door", "hinged_door":
			for x in [-1.3, 1.3]: _box_body("Frame", Vector3(0.18, 2.7, 0.45), Vector3(x, 1.35, 0), _generated, frame)
			_box_body("Lintel", Vector3(2.8, 0.18, 0.45), Vector3(0, 2.75, 0), _generated, frame)
			_motion = AnimatableBody3D.new(); _motion.name = "MovingDoor"; _motion.sync_to_physics = not Engine.is_editor_hint(); _generated.add_child(_motion)
			var leaf_position := Vector3(0, 1.3, 0)
			if component_type == "hinged_door": _motion.position.x = -1.18; leaf_position.x = 1.18
			_mesh("Door", Vector3(2.36, 2.6, 0.22), leaf_position, _motion, _active_material)
			_collision(Vector3(2.36, 2.6, 0.22), leaf_position, _motion)
		"lift_platform":
			_motion = AnimatableBody3D.new(); _motion.name = "MovingPlatform"; _motion.sync_to_physics = not Engine.is_editor_hint(); _generated.add_child(_motion)
			_mesh("Platform", Vector3(3, 0.22, 3), Vector3(0, 0.11, 0), _motion, _active_material)
			_collision(Vector3(3, 0.22, 3), Vector3(0, 0.11, 0), _motion)
			for x in [-1.65, 1.65]: _mesh("Rail", Vector3(0.12, maxf(0.5, travel_offset.length() + 0.5), 0.12), Vector3(x, travel_offset.length() * 0.5, -1.65), _generated, frame)
		"terminal":
			_box_body("Stand", Vector3(0.85, 0.95, 0.65), Vector3(0, 0.475, 0), _generated, frame)
			_box_body("Console", Vector3(1.05, 0.55, 0.55), Vector3(0, 1.1, 0), _generated, base)
			_mesh("Screen", Vector3(0.8, 0.33, 0.03), Vector3(0, 1.13, 0.29), _generated, _active_material)
	_sensor = Area3D.new(); _sensor.name = "Sensor"; _sensor.collision_layer = 0; _sensor.collision_mask = sensor_mask
	_sensor.monitoring = not Engine.is_editor_hint(); _generated.add_child(_sensor)
	_collision(Vector3(2.2, 1.6, 2.2) if component_type == "pressure_plate" else Vector3(3.5, 2.0, 3.5), Vector3(0, 0.8, 0), _sensor)
	_label = preload("res://addons/godot_level_editor/scripts/ui/interaction_label.gd").new(); _label.position.y = 3.1 if component_type in ["sliding_door", "hinged_door"] else 1.65 if component_type != "pressure_plate" else 0.6
	_label.configure(self, display_name, "" if component_type == "pressure_plate" else "[F]")
	_generated.add_child(_label); _signature = _design_signature(); _apply_pose()

func _mesh(title: String, dimensions: Vector3, offset: Vector3, parent: Node3D, material: Material) -> void:
	var mesh := MeshInstance3D.new(); mesh.name = title; mesh.position = offset
	var shape := BoxMesh.new(); shape.size = dimensions; mesh.mesh = shape; mesh.material_override = material; parent.add_child(mesh)

func _collision(dimensions: Vector3, offset: Vector3, parent: Node3D) -> void:
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = dimensions
	collision.shape = shape; collision.position = offset; parent.add_child(collision)

func _box_body(title: String, dimensions: Vector3, offset: Vector3, parent: Node3D, material: Material) -> void:
	var body := StaticBody3D.new(); body.name = title; body.position = offset; parent.add_child(body)
	_mesh("Mesh", dimensions, Vector3.ZERO, body, material); _collision(dimensions, Vector3.ZERO, body)

func _apply_pose() -> void:
	if is_instance_valid(_motion):
		match component_type:
			"button": _motion.position.y = -0.06 if current_state == "pressed" else 0.0
			"toggle_switch": _motion.rotation_degrees.x = -25.0 if current_state == "on" else 25.0
			"pressure_plate": _motion.position.y = -0.04 if current_state == "pressed" else 0.0
			"sliding_door": _motion.position = Vector3(0, 2.8 * progress, 0)
			"hinged_door": _motion.position = Vector3(-1.18, 0, 0); _motion.rotation_degrees.y = open_angle * progress
			"lift_platform": _motion.position = travel_offset * progress
	if _active_material != null:
		_active_material.albedo_color = color_active if is_powered() else color_idle
		_active_material.emission_enabled = is_powered(); _active_material.emission = color_active; _active_material.emission_energy_multiplier = 0.15
	if is_instance_valid(_label):
		if component_type == "lift_platform": _label.position = travel_offset * progress + Vector3(0, 1.65, 0)
		_label.caption = (display_name if not display_name.is_empty() else str(TITLES.get(component_type, "机关"))) + " · " + current_state
		if Engine.is_editor_hint(): _label.text = _label.caption
