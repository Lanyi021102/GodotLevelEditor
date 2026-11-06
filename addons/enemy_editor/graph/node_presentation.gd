@tool
extends RefCounted
## Enemy-only adapter for the mechanism blueprint's pure presentation helpers.
## FSM entries are persistent states, even when their behavior performs an action.
const Shared := preload("res://addons/branch_mechanisms/graph/node_presentation.gd")
const CATEGORIES := Shared.CATEGORIES
const TEXT := Shared.TEXT
const MUTED := Shared.MUTED
const ACTIVE := Shared.ACTIVE
# Port/connection colors retain their existing transition semantics, independently
# of the teal state-category header. Port type and enabled indices are unchanged.
const INPUT_COLOR := Color("e7b770")
const OUTPUT_COLOR := Color("75cdd3")
const CATEGORY := "state"
const LEGEND_LABELS := {"condition": "判断", "trigger": "触发事件", "state": "状态", "action": "动作", "data": "数据/引用", "flow": "延迟/流程"}

static func apply_state(node: GraphNode) -> void:
	var color: Color = CATEGORIES[CATEGORY].color
	var body := Color("202833").lerp(color, 0.16)
	var panel := Shared._box(body, color.lightened(0.18), false)
	var selected := Shared._box(body, Color("e0ebff"), false, 3)
	var active := Shared._box(body, ACTIVE, false, 2)
	var active_selected := Shared._box(body, ACTIVE, false, 3)
	var titlebar := Shared._box(color, color.lightened(0.18), true)
	var titlebar_selected := Shared._box(color, Color("e0ebff"), true, 3)
	node.set_meta("node_category", CATEGORY)
	node.set_meta("category_panel", panel)
	node.set_meta("category_selected_panel", selected)
	node.set_meta("active_panel", active)
	node.set_meta("active_selected_panel", active_selected)
	node.set_meta("category_titlebar_selected", titlebar_selected)
	node.set_meta("active_titlebar_selected", Shared._box(color, ACTIVE, true, 3))
	node.set_meta("runtime_active", false)
	node.add_theme_stylebox_override("panel", panel)
	node.add_theme_stylebox_override("panel_selected", selected)
	node.add_theme_stylebox_override("titlebar", titlebar)
	node.add_theme_stylebox_override("titlebar_selected", titlebar_selected)
	node.tooltip_text = "持续敌人状态；行为和计时由定义执行。\n左侧输入状态进入，右侧输出条件转换。\n节点分类色表示职责，端口和连线色表示状态转换的连接语义。"
	for child in node.get_titlebar_hbox().get_children():
		if child is Label:
			child.add_theme_color_override("font_color", TEXT)
			child.add_theme_font_size_override("font_size", 16)

static func add_ports(node: GraphNode) -> void:
	# Slot 0 is a heading with no ports. Slot 1 is the ONLY enabled slot,
	# therefore GraphEdit input/output indices both remain 0 (not 1).
	var directions := Shared.direction_row(true, true)
	for label in directions.get_children(): label.add_theme_font_size_override("font_size", 14)
	node.add_child(directions)
	var row := Shared.port_row("状态进入", "条件转换", "输入 state_enter [状态转换]：进入此状态；输出 state_exit [状态转换]：按事件、全部条件、优先级及稳定顺序选择下一状态。")
	row.name = "TransitionPorts"
	for label in row.get_children(): label.add_theme_font_size_override("font_size", 16)
	row.get_node("InputLabel").tooltip_text = "输入端口 state_enter；类型：状态转换；连接索引：0。"
	row.get_node("OutputLabel").tooltip_text = "输出端口 state_exit；类型：状态转换；连接索引：0。条件与优先级在转换页编辑。"
	node.add_child(row)
	node.set_slot(1, true, 0, INPUT_COLOR, true, 0, OUTPUT_COLOR)

static func add_legend(parent: Node) -> void:
	var legend := HFlowContainer.new()
	legend.name = "CategoryLegend"
	legend.add_theme_constant_override("h_separation", 16)
	parent.add_child(legend)
	for key in CATEGORIES:
		var item := Label.new()
		item.name = key
		item.text = "● " + str(LEGEND_LABELS[key])
		item.add_theme_color_override("font_color", CATEGORIES[key].color)
		item.tooltip_text = "持续状态的变化不等于一次触发事件。" if key == "state" else str(CATEGORIES[key].hint)
		legend.add_child(item)
	var hint := Label.new()
	hint.text = "节点分类色 ≠ 端口/连线类型色 · 本图节点均为持续状态"
	hint.tooltip_text = "噪音、求援属于转换事件；计时与条件属于转换规则，不新增其他类别节点。"
	legend.add_child(hint)

static func show_runtime(node: GraphNode, active: bool, mode: String, value: String, hint: String) -> void:
	# Reuse the shared border/value treatment; also keep active borders visible
	# on selected nodes, without changing any category fill or node modulation.
	Shared.show_runtime(node, active)
	node.add_theme_stylebox_override("panel_selected", node.get_meta("active_selected_panel") if active else node.get_meta("category_selected_panel"))
	node.add_theme_stylebox_override("titlebar_selected", node.get_meta("active_titlebar_selected") if active else node.get_meta("category_titlebar_selected"))
	node.self_modulate = Color.WHITE
	node.modulate = Color.WHITE
	var label := node.get_node("RuntimeValue") as Label
	label.add_theme_font_size_override("font_size", 16)
	label.text = ("● " + mode if active else value)
	label.add_theme_color_override("font_color", ACTIVE if active else MUTED)
	label.tooltip_text = hint
	var values := node.get_node("RuntimeMetrics") as Label
	values.add_theme_font_size_override("font_size", 16)
	values.text = value if active else ""
	values.visible = active
	values.tooltip_text = hint

static func title(label: String, initial: bool, active: bool, mode: String) -> String:
	return "状态 · " + ("▶ " if initial else "") + label + (" · " + mode if active else "")
