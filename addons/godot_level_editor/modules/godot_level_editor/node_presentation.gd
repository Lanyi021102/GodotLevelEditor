@tool
extends RefCounted
## Reuse the mechanism blueprint's visual primitives; level semantics stay local.
const SHARED := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/graph/node_presentation.gd")
const CATEGORIES := SHARED.CATEGORIES
const KIND_CATEGORIES := {
	"task_accept": "action",
	"event_hold": "action", "event_complete": "action",
	"npc_interact": "trigger", "dialog_completed": "trigger", "show_dialog": "action", "task_start": "action", "task_complete": "action",
	"greater": "condition", "all": "condition", "has_item": "condition", "branch": "condition",
	"start": "trigger", "room_enter": "trigger", "region_enter": "trigger", "event_received": "trigger", "goal": "trigger",
	"source": "state", "read_state": "state", "player_state": "state", "latch": "state",
	"set_switch": "action", "enemy_patrol": "action", "kill_player": "action", "set_visibility": "action", "unlock": "action", "objective": "action", "checkpoint": "action",
	"port": "data", "constant": "data", "number": "data", "object": "data",
	"emit_event": "flow",
}
const SHARED_KINDS := {"condition": "and", "trigger": "rising", "state": "read_power", "action": "door", "data": "object", "flow": "delay"}
const HINTS := {
	"condition": "计算条件或根据条件选择执行分支",
	"trigger": "发生一次时输出事件；不表示持续状态",
	"state": "持续读取状态，或记住已发生的事件",
	"action": "执行关卡操作；实际结果与失败原因显示在节点下方",
	"data": "常量、场景物件引用或双向空间接驳引用",
	"flow": "控制等待、并行、汇合、取消与事件投递；事件和持续条件分别连线",
}

static func category_key(kind: String) -> String:
	var spec: Array = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_nodes.gd").DEFINITIONS.get(kind, [])
	return str(spec[2]) if not spec.is_empty() else KIND_CATEGORIES.get(kind, "data")
static func category_label(key: String) -> String:
	return {"data": "数据／引用", "flow": "延迟／流程"}.get(key, CATEGORIES[key].label)

static func apply(node: GraphNode, kind: String) -> void:
	var title := node.title
	var key := category_key(kind)
	SHARED.apply(node, SHARED_KINDS[key])
	node.title = title
	node.tooltip_text = HINTS[key] + "\n左侧输入 → 右侧输出；标题颜色表示职责，端口和连线颜色表示连接类型。"
	node.tooltip_text = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_nodes.gd").english_name(kind) + "\n" + node.tooltip_text
	# Keep the exact category fill when selected; use its border for selection.
	var selected_title: StyleBoxFlat = node.get_theme_stylebox("titlebar_selected").duplicate()
	selected_title.bg_color = CATEGORIES[key].color
	node.add_theme_stylebox_override("titlebar_selected", selected_title)
	node.set_meta("selection_panel", node.get_theme_stylebox("panel_selected"))
	var selected_active: StyleBoxFlat = node.get_meta("active_panel").duplicate()
	selected_active.set_border_width_all(3)
	node.set_meta("selection_active_panel", selected_active)

static func show_runtime(node: GraphNode, active: bool) -> void:
	SHARED.show_runtime(node, active)
	node.add_theme_stylebox_override("panel_selected", node.get_meta("selection_active_panel") if active else node.get_meta("selection_panel"))
	var label: Label = node.get_node("Runtime")
	label.add_theme_color_override("font_color", SHARED.ACTIVE if active else SHARED.MUTED)

static func direction_row(has_input: bool, has_output: bool) -> HBoxContainer:
	return SHARED.direction_row(has_input, has_output)
static func port_row(input_text: String, output_text: String, hint: String) -> HBoxContainer:
	return SHARED.port_row(input_text, output_text, hint)
