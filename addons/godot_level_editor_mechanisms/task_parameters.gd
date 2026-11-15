@tool
extends RefCounted
const ACCESS := preload("res://addons/godot_level_editor_mechanisms/state_access.gd")
const NAMES := {"idle": "待机", "pressed": "已按下", "released": "未踩下", "off": "关闭", "on": "开启", "closed": "已关闭", "opening": "正在打开", "open": "已打开", "closing": "正在关闭", "at_start": "位于起点", "moving": "正在移动", "at_end": "位于终点", "stopped": "已停止", "offline": "离线", "ready": "就绪", "activated": "已激活", "press": "按下", "release": "释放", "toggle": "切换", "turn_on": "开启", "turn_off": "关闭", "move_to_end": "移动到终点", "move_to_start": "移动到起点", "activate": "激活", "enable": "启用", "disable": "停用", "reset": "复位", "stop": "停止", "locked": "上锁", "interaction_enabled": "允许交互", "motion_seconds": "动作时长（秒）", "reset_after": "按钮复位时长（秒）"}

static func draw(panel: Control, node: Dictionary) -> void:
	for child in panel.parameters.get_children(): panel.parameters.remove_child(child); child.queue_free()
	panel._fields.clear()
	panel._text_field("label", "显示名称", str(node.get("label", "")))
	var targets := ACCESS.descriptions(panel.world)
	var options: Array = [""]
	for target in targets: options.append(target.reference)
	var p: Dictionary = node.params
	if not str(p.mechanism).is_empty() and not options.has(p.mechanism): options.append(p.mechanism)
	panel._option_field("mechanism", "当前关卡中的机关 / 组件", options, str(p.mechanism))
	var picker: OptionButton = panel._fields.mechanism
	for i in picker.item_count:
		var reference := str(picker.get_item_metadata(i))
		for target in targets:
			if target.reference == reference: picker.set_item_text(i, str(target.title)); picker.set_item_tooltip(i, reference)
	var dependent := VBoxContainer.new(); panel.parameters.add_child(dependent)
	var update := func(): _dependent(panel, node, targets, str(picker.get_item_metadata(picker.selected)), dependent)
	picker.item_selected.connect(func(_index: int): update.call())
	update.call()
	for key in ["once", "player_only", "succeeded", "enabled", "bool_value"]:
		if p.has(key): panel._bool_field(key, {"once": "本次运行只触发一次", "player_only": "只接受玩家", "succeeded": "监听动作成功（取消勾选监听失败）", "enabled": "允许玩家交互", "bool_value": "属性值：是"}[key], p[key])
	for key in ["timeout", "number_value"]:
		if not p.has(key): continue
		var label := Label.new(); label.text = "超时秒数（0 为不限）" if key == "timeout" else "属性数值"; panel.parameters.add_child(label)
		var field := SpinBox.new(); field.min_value = 0; field.max_value = 86400; field.step = 0.1; field.value = p[key]; panel.parameters.add_child(field); panel._fields[key] = field
	if p.has("scope"): panel._text_field("scope", "分支组名（可选）", str(p.scope))
	var hint := Label.new(); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "指令的“继续”表示已接受；需要等到实际到位时，连接“等待机关到达状态”。" if node.kind in ["mechanism_action", "mechanism_request_state"] else "等待启动时会先检查当前状态，已经到达则立即继续。" if node.kind == "wait_mechanism_state" else "同名素材的不同关卡实例分别绑定；状态名从组件读取。"
	panel.parameters.add_child(hint)
	panel._button(panel.parameters, "应用参数", panel._apply_parameters)

static func _dependent(panel: Control, node: Dictionary, targets: Array, reference: String, parent: VBoxContainer) -> void:
	var previous := {}
	for key in ["state", "from_state", "to_state", "action", "property"]:
		if panel._fields.has(key):
			var field: OptionButton = panel._fields[key]
			if field.selected >= 0: previous[key] = field.get_item_metadata(field.selected)
			panel._fields.erase(key)
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()
	var target := {}
	for entry in targets:
		if entry.reference == reference: target = entry; break
	for key in ["state", "from_state", "to_state", "action", "property"]:
		if not node.params.has(key): continue
		var values: Array = []
		if key == "property": values = ["locked", "interaction_enabled", "motion_seconds", "reset_after"]
		elif key == "action": values = target.get("actions", []).duplicate()
		else: values = target.get("requestable" if node.kind == "mechanism_request_state" else "states", []).duplicate()
		var any: bool = key in ["from_state", "to_state"] or (key == "action" and node.kind == "mechanism_action_finished")
		values.push_front("")
		var current := str(previous.get(key, node.params[key]))
		if reference != str(node.params.mechanism) and not values.has(current): current = ""
		if not values.has(current): values.append(current)
		var label := Label.new(); label.text = {"state": "目标状态", "from_state": "原状态", "to_state": "新状态", "action": "动作", "property": "可设置属性"}[key]; parent.add_child(label)
		var field := OptionButton.new(); field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for value in values:
			field.add_item(("任意" if any else "请选择") if str(value).is_empty() else str(NAMES.get(value, value)) + " · " + str(value))
			field.set_item_metadata(field.item_count - 1, value)
			if str(value) == current: field.select(field.item_count - 1)
		parent.add_child(field); panel._fields[key] = field
