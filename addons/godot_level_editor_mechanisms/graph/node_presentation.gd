@tool
extends RefCounted
## Presentation only: classification never changes graph kinds, ports or execution.
const CATEGORIES := {
	"condition": {"label": "判断", "color": Color("976b36"), "hint": "条件判断与布尔运算"},
	"trigger": {"label": "触发", "color": Color("2b6535"), "hint": "产生一次触发事件"},
	"state": {"label": "状态", "color": Color("2b7278"), "hint": "持续读取机关状态"},
	"action": {"label": "动作", "color": Color("244568"), "hint": "控制机关执行动作"},
	"data": {"label": "数据", "color": Color("747c86"), "hint": "常量与对象引用"},
	"flow": {"label": "延迟", "color": Color("a56637"), "hint": "事件延迟与流程推进"},
}
const KIND_CATEGORIES := {
	"button": "state", "toggle_switch": "state", "pressure_plate": "state", "sliding_door": "state", "hinged_door": "state", "lift_platform": "state", "terminal": "state", "state_is": "condition",
	"interacted": "trigger", "state_changed": "trigger", "state_entered": "trigger", "state_exited": "trigger", "action_finished": "trigger", "region_entered": "trigger", "region_exited": "trigger",
	"request_state": "action", "perform_action": "action", "set_interaction": "action", "set_property": "action", "branch": "condition",
	"and": "condition", "or": "condition", "not": "condition", "greater": "condition",
	"rising": "trigger",
	"lever": "state", "plate": "state", "read_power": "state",
	"door": "action", "set_lever": "action",
	"bool": "data", "number": "data", "object": "data",
	"delay": "flow",
}
const TEXT := Color("18334d")
const TITLE_TEXT := Color.WHITE
const MUTED := Color("506779")
const ACTIVE := Color("438d76")

static func category(kind: String) -> Dictionary:
	return CATEGORIES[KIND_CATEGORIES.get(kind, "data")]

static func apply(node: GraphNode, kind: String) -> void:
	var info := category(kind)
	var color: Color = info.color
	node.tooltip_text = str(info.hint) + "\n左侧端口输入，右侧端口输出；端口颜色表示数据类型。"
	node.set_meta("node_category", KIND_CATEGORIES.get(kind, "data"))
	var body_color := Color("ffffff")
	var panel := _box(body_color, Color("dce3ed"), false)
	var active_panel := _box(body_color, ACTIVE, false, 2)
	node.set_meta("category_panel", panel)
	node.set_meta("active_panel", active_panel)
	node.set_meta("runtime_active", false)
	node.add_theme_stylebox_override("panel", panel)
	node.add_theme_stylebox_override("panel_selected", _box(body_color, Color("2563eb"), false, 2))
	node.add_theme_stylebox_override("titlebar", _box(color, color.lightened(0.18), true))
	node.add_theme_stylebox_override("titlebar_selected", _box(color, Color("2563eb"), true, 2))
	for child in node.get_titlebar_hbox().get_children():
		if child is Label: child.add_theme_color_override("font_color", TITLE_TEXT)

static func direction_row(has_input: bool, has_output: bool) -> HBoxContainer:
	var row := _row("PortDirections")
	var left := _label("InputDirection", "输入 →" if has_input else "", MUTED)
	var right := _label("OutputDirection", "→ 输出" if has_output else "", MUTED)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left)
	row.add_child(right)
	row.tooltip_text = "输入位于左侧，输出位于右侧。"
	row.hide()
	return row

static func port_row(input_text: String, output_text: String, hint: String) -> HBoxContainer:
	var row := _row("")
	row.tooltip_text = hint
	var left := _label("InputLabel", input_text, TEXT)
	var right := _label("OutputLabel", output_text, TEXT)
	left.tooltip_text = hint
	right.tooltip_text = hint
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left)
	row.add_child(right)
	return row

static func show_runtime(node: GraphNode, active: bool) -> void:
	# Preserve the category header in all runtime/selection states.
	if bool(node.get_meta("runtime_active", false)) != active:
		node.add_theme_stylebox_override("panel", node.get_meta("active_panel") if active else node.get_meta("category_panel"))
		node.set_meta("runtime_active", active)
	var label := node.get_node_or_null("RuntimeValue")
	if label != null: label.add_theme_color_override("font_color", ACTIVE if active else MUTED)

static func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	if not label.is_empty(): row.name = label
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 24)
	return row

static func _label(label: String, text: String, color: Color) -> Label:
	var result := Label.new()
	result.name = label
	result.text = text
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_color_override("font_color", color)
	return result

static func _box(fill: Color, border: Color, header: bool, width := 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(width)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	result.corner_radius_top_left = 5 if header else 0
	result.corner_radius_top_right = 5 if header else 0
	result.corner_radius_bottom_left = 0 if header else 5
	result.corner_radius_bottom_right = 0 if header else 5
	return result
