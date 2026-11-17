@tool
extends RefCounted
const LABELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_parameters.gd").NAMES

static func draw(panel: Control, component: Node) -> void:
	if component.has_method("door_dimensions"):
		preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/door_nodes.gd").details(panel, component)
		return
	var parent: VBoxContainer = panel.details
	parent.add_child(HSeparator.new())
	var caption := Label.new(); caption.text = "组件状态配置"; parent.add_child(caption)
	var states := Label.new(); states.text = "状态：" + ", ".join(component.state_names()); states.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(states)
	if component.component_type == "pressure_plate":
		var hint := Label.new(); hint.text = "压力板状态由真实占位驱动；检测层、人数和释放延迟在原生检查器中调整。"; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(hint); return
	var initial := OptionButton.new(); initial.add_item("使用内置初始状态"); initial.set_item_metadata(0, "")
	for state in component.requestable_states():
		initial.add_item(str(LABELS.get(state, state)) + " · " + str(state)); initial.set_item_metadata(initial.item_count - 1, state)
		if state == component.initial_state: initial.select(initial.item_count - 1)
	initial.item_selected.connect(func(index: int): panel.set_component_property(component, "initial_state", initial.get_item_metadata(index)))
	parent.add_child(initial)
	for key in ["interaction_enabled", "locked", "one_shot"]:
		var field := CheckBox.new(); field.text = {"interaction_enabled": "允许玩家交互", "locked": "锁定", "one_shot": "玩家只能使用一次"}[key]; field.button_pressed = component.get(key)
		field.toggled.connect(func(value: bool): panel.set_component_property(component, key, value)); parent.add_child(field)
	var custom := LineEdit.new(); custom.text = ", ".join(component.custom_states); custom.placeholder_text = "新增状态 ID，用逗号分隔，如 repaired, broken"
	custom.text_submitted.connect(func(value: String):
		var values := PackedStringArray()
		for item in value.split(",", false): values.append(item.strip_edges())
		panel.set_component_property(component, "custom_states", values))
	parent.add_child(custom)
	var rule_title := Label.new(); rule_title.text = "转换规则：原状态 → 动作 → 新状态"; parent.add_child(rule_title)
	for index in component.transition_rules.size():
		var rule: Dictionary = component.transition_rules[index]
		var row := HBoxContainer.new(); parent.add_child(row)
		var text := Label.new(); text.text = "%s → %s → %s" % [rule.get("from", ""), rule.get("action", ""), rule.get("to", "")]; text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(text)
		var remove := Button.new(); remove.text = "删除"; row.add_child(remove)
		remove.pressed.connect(func():
			var rules: Array[Dictionary] = component.transition_rules.duplicate(true); rules.remove_at(index)
			panel.set_component_property(component, "transition_rules", rules))
	var from := OptionButton.new(); from.add_item("任意原状态"); from.set_item_metadata(0, "*")
	for value in component.state_names(): from.add_item(str(value)); from.set_item_metadata(from.item_count - 1, value)
	parent.add_child(from)
	var action := LineEdit.new(); action.placeholder_text = "动作 ID，例如 interact / repair"; parent.add_child(action)
	var to := OptionButton.new()
	for value in component.requestable_states(): to.add_item(str(value)); to.set_item_metadata(to.item_count - 1, value)
	parent.add_child(to)
	var add := Button.new(); add.text = "添加转换规则"; add.disabled = to.item_count == 0; parent.add_child(add)
	add.pressed.connect(func():
		if not action.text.strip_edges().is_valid_identifier(): panel.status.text = "动作 ID 需为英文标识，如 repair。"; return
		var rules: Array[Dictionary] = component.transition_rules.duplicate(true)
		rules.append({"from": str(from.get_item_metadata(from.selected)), "action": action.text.strip_edges(), "to": str(to.get_item_metadata(to.selected))})
		panel.set_component_property(component, "transition_rules", rules))
