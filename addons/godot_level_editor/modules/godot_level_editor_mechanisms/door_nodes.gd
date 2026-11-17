@tool
extends RefCounted
const CURVE := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/door_curve.gd")
const DOOR := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/runtime/rotating_door.gd")
const NAMES := {"close": "关闭 · 0°", "moving": "旋转中 · 0° ↔ 90°", "open": "开启 · 90°"}

static func label(parent: Node, text: String, name_ := "") -> Label:
	var result := Label.new(); result.text = text; result.name = name_ if not name_.is_empty() else "Info"
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE; result.add_theme_color_override("font_color", Color("244568"))
	result.add_theme_font_size_override("font_size", 13)
	parent.add_child(result); return result

static func build(panel: Control, card: GraphNode, entry: Dictionary, door: Node) -> void:
	if not is_instance_valid(door) or not door.has_method("door_dimensions"): return
	card.custom_minimum_size.x = 290 if entry.kind == "door_animation" else 240
	var body := VBoxContainer.new(); body.name = "DoorBody"; body.mouse_filter = Control.MOUSE_FILTER_IGNORE; card.add_child(body)
	match str(entry.kind):
		"single_door", "double_door":
			card.title = "门框 · " + ("2×3 单开门" if door.door_type == 0 else "4×3 双开门")
			label(body, "外框  %s × 3 m" % (2 if door.door_type == 0 else 4))
			label(body, "固定立柱 + 顶梁")
			label(body, "门扇安装在内侧铰链")
		"door_leaf":
			label(body, "%d 片门扇 · 侧边铰链" % door.leaf_count())
			label(body, "左扇  0° → +90°" + ("\n右扇  0° → −90°" if door.leaf_count() == 2 else ""))
			label(body, "当前  0.0°", "Pose")
		"door_animation":
			label(body, "close  ⇄  moving  ⇄  open")
			label(body, "%.2f 秒 / %s" % [door.motion_seconds, {"toggle": "交互切换开关", "open": "打开", "close": "关闭"}.get(entry.params.action, entry.params.action)])
			var curve: Control = CURVE.new(); curve.name = "RotationCurve"; curve.curve = door.motion_curve
			curve.curve_edited.connect(func(value: Curve): panel.set_component_property(door, "motion_curve", value))
			body.add_child(curve)
			label(body, "当前 close · 0.0°", "Pose")
			label(body, "拖动曲线点 · 关门反向播放").add_theme_font_size_override("font_size", 11)
		"door_state":
			card.title = str(entry.params.state)
			label(body, str(NAMES.get(entry.params.state, entry.params.state))).add_theme_font_size_override("font_size", 18)
			label(body, "● 当前状态", "Pose")
			label(body, "进入此状态时输出一次事件")

static func update(card: GraphNode, entry: Dictionary, info: Dictionary) -> void:
	var body := card.get_node_or_null("DoorBody")
	if body == null: return
	var pose := body.get_node_or_null("Pose")
	if pose != null:
		if entry.kind == "door_state": pose.text = "● 当前状态" if info.get("state") == entry.params.state else "○ 未激活"
		else: pose.text = "%s · %.1f°" % [str(info.get("state", "close")), float(info.get("angle", 0))]
	var curve: Control = body.get_node_or_null("RotationCurve")
	if curve != null: curve.progress = float(info.get("progress", 0)); curve.queue_redraw()

static func details(panel: Control, door: Node) -> void:
	var parent: VBoxContainer = panel.details
	label(parent, "门规格与动画")
	var initial := OptionButton.new()
	for state in door.requestable_states():
		initial.add_item(state + " · " + NAMES[state]); initial.set_item_metadata(initial.item_count - 1, state)
		if state == door.initial_state: initial.select(initial.item_count - 1)
	initial.item_selected.connect(func(index: int): panel.set_component_property(door, "initial_state", initial.get_item_metadata(index))); parent.add_child(initial)
	for key in ["interaction_enabled", "locked", "one_shot"]:
		var field := CheckBox.new(); field.text = {"interaction_enabled": "允许玩家交互", "locked": "锁定", "one_shot": "仅交互一次"}[key]; field.button_pressed = door.get(key)
		field.toggled.connect(func(value: bool): panel.set_component_property(door, key, value)); parent.add_child(field)
	label(parent, "旋转时长（秒）")
	var duration := SpinBox.new(); duration.min_value = 0.05; duration.max_value = 30; duration.step = 0.05; duration.value = door.motion_seconds
	duration.value_changed.connect(func(value: float): panel.set_component_property(door, "motion_seconds", value)); parent.add_child(duration)
	var curve: Control = CURVE.new(); curve.curve = door.motion_curve
	curve.curve_edited.connect(func(value: Curve): panel.set_component_property(door, "motion_curve", value)); parent.add_child(curve)
	var actions := HBoxContainer.new(); parent.add_child(actions)
	for linear in [false, true]:
		var button := Button.new(); button.text = "缓入缓出" if not linear else "匀速"
		button.pressed.connect(func(): panel.set_component_property(door, "motion_curve", DOOR.default_curve(linear))); actions.add_child(button)
	var control := HBoxContainer.new(); parent.add_child(control)
	for action in ["close", "open"]:
		var button := Button.new(); button.text = "预览关闭" if action == "close" else "预览打开"
		button.pressed.connect(func():
			if is_instance_valid(panel._preview) and panel._preview.bindings.has(door.object_id):
				panel._preview.bindings[door.object_id].perform_action(action); panel._preview_running = true)
		control.add_child(button)
