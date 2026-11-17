@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd"
## One task resource owns the dialogue-library reference; scenes only reference the task.
@export var dialogue_library: Resource
@export_file("*.csv") var dialogue_csv := "" # Legacy migration only.
@export_file("*.xlsx") var dialogue_xlsx := "res://content/tables/dialogues.xlsx"
const LIBRARY := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd")

func table_file() -> String:
	return dialogue_xlsx

func load_dialogue() -> Dictionary:
	return LIBRARY.read_xlsx(table_file())

const BASE_KINDS := ["event_received", "emit_event", "event_hold", "event_complete", "start", "room_enter", "npc_interact", "dialog_completed", "show_dialog", "task_start", "task_complete", "objective"]
const LOCAL_TASK_KINDS := ["task_start", "task_complete", "task_fail", "npc_interact", "dialog_completed"]
const REUSED_KINDS := ["region_enter", "branch", "has_item", "player_state", "source", "object", "read_state", "all", "constant", "number", "greater", "latch", "checkpoint", "set_switch", "set_visibility", "enemy_patrol"]
static func supported_kinds() -> Array:
	return BASE_KINDS + REUSED_KINDS + TASK_NODES.DEFINITIONS.keys()

func allowed_kinds() -> Array:
	return supported_kinds()


func validate() -> PackedStringArray:
	if not is_level_logic():
		var binding_errors := PackedStringArray()
		for node in nodes:
			if not LOCAL_TASK_KINDS.has(node.get("kind", "")) or not node.get("params") is Dictionary: continue
			var task := str(node.params.get("task", ""))
			if not task.is_valid_identifier() and not task.is_valid_int():
				binding_errors.append(display_label(node) + "（" + str(node.get("id", "")) + "）：缺少所属任务。请从“事件与任务”中点击对应任务的“编辑”打开任务图。")
		if not binding_errors.is_empty(): return binding_errors
	var errors := super.validate()
	if not errors.is_empty(): return errors
	var csv := load_dialogue()
	errors.append_array(csv.errors)
	if not errors.is_empty(): return errors
	var library: Resource = csv.library
	var task_ids := {}
	for n in nodes:
		if n.kind == "has_item":
			if typeof(n.params.get("actor", "")) != TYPE_STRING or not (n.params.get("amount", 1) is int) or int(n.params.get("amount", 1)) < 1: errors.append("背包检测需要有效角色和正整数数量")
		if n.kind in ["wait_all", "wait_any", "wait_until"]:
			var connected := false
			for e in edges:
				if e.to == n.id and (e.to_port == "condition" if n.kind == "wait_until" else e.to_port in ["a", "b", "c", "d"]): connected = true
			if not connected: errors.append(str(n.id) + "：等待节点缺少条件／汇合输入")
	for n in nodes:
		if n.kind == "task_start":
			if task_ids.has(n.params.task): errors.append("任务开始节点的任务 ID 重复")
			task_ids[n.params.task] = true
	for n in nodes:
		if not allowed_kinds().has(n.kind): errors.append("当前图不支持节点：" + str(n.kind))
		if n.params.has("task") and not str(n.params.task).is_valid_identifier() and not str(n.params.task).is_valid_int(): errors.append("任务 ID 无效")
		if n.kind == "show_dialog" and library.comment_by_id(str(n.params.get("dialog_id", ""))).is_empty(): errors.append("showdialog comment 不存在")
		if n.kind == "dialog_completed":
			var found: bool = not library.comment_by_id(str(n.params.get("dialog_id", ""))).is_empty()
			for group in library.groups:
				for comment in group.comments:
					for line in comment.lines:
						if line.id == n.params.get("dialog_id"): found = true
			if not found: errors.append("完成触发引用的台本 ID 不存在")
	return errors
