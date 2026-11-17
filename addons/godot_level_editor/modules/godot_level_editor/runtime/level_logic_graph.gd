@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd"
## Permanent level logic shares the typed task schema and asynchronous evaluator.
@export_file("*.xlsx") var events_xlsx := "res://content/tables/events.xlsx"
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const NPC := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/npc.gd")
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const KINDS := [
	"start", "room_enter", "room_exit", "room_active", "region_enter", "region_exit", "object_interacted", "state_changed", "npc_interact", "dialog_completed", "event_received", "emit_event", "show_dialog", "task_accept",
	"branch", "has_item", "has_equipped", "player_state", "actor_state", "source", "object", "read_state", "all", "any", "not", "constant", "number", "greater", "compare", "latch",
	"get_variable", "get_number", "set_variable", "change_item", "equip_item", "set_actor_state", "set_switch", "set_visibility", "enemy_patrol", "kill_player",
	"delay", "timer", "wait_until", "wait_event", "parallel", "wait_all", "wait_any", "counter", "gate", "cancel_branch", "objective", "checkpoint",
]

func is_level_logic() -> bool: return true
func allowed_kinds() -> Array:
	return KINDS + preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_nodes.gd").DEFINITIONS.keys()

static func permanent_npcs(world: Node) -> Dictionary:
	var result := {}
	if not is_instance_valid(world): return result
	for reference in world.objects():
		var node: Node = world.object_by_id(reference)
		if node.get_script() != NPC: continue
		var ancestor := node
		var permanent := true
		while ancestor != null and ancestor != world:
			var profile: Resource = ancestor.get_meta(PROFILE.META) if ancestor.has_meta(PROFILE.META) else null
			if profile != null and profile.lifetime != "level": permanent = false; break
			ancestor = ancestor.get_parent()
		if permanent and ancestor == world: result[reference] = node
	return result

func validate_bindings(world: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	var npcs := permanent_npcs(world)
	var objects: Dictionary = world.objects()
	for n in nodes:
		if not n.get("kind") is String or not n.get("params") is Dictionary: continue
		errors.append_array(preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_nodes.gd").validate_bindings(world, n))
		if n.kind == "npc_interact" and not npcs.has(n.params.get("npc", "")): errors.append(str(n.id) + "：NPC 必须是当前关卡已放置的常驻 NPC")
		if n.params.has("object") and not objects.has(n.params.object): errors.append(str(n.id) + "：关卡对象引用失效")
		if n.params.has("room") and not world.rooms().any(func(room: Node): return room.room_id == n.params.get("room", "")): errors.append(str(n.id) + "：关卡 Room 引用失效")
		if n.kind == "task_accept" and not str(world.level_id).is_empty():
			var result := CATALOG.load_book(events_xlsx)
			var task: Dictionary = result.catalog.task_by_id(str(n.params.get("task", ""))) if result.catalog != null else {}
			if not task.is_empty() and str(task.level_id) != str(world.level_id): errors.append(str(n.id) + "：只能接取属于当前关卡的任务")
	return errors

func validate() -> PackedStringArray:
	var errors := super.validate()
	if not errors.is_empty(): return errors
	for n in nodes:
		if n.kind in ["npc_interact", "dialog_completed"] and n.params.has("task"): errors.append(str(n.id) + "：常驻触发不能绑定任务状态")
	if not nodes.any(func(n: Dictionary): return n.kind == "task_accept"): return errors
	var result := CATALOG.load_book(events_xlsx)
	errors.append_array(result.errors)
	if not errors.is_empty(): return errors
	for n in nodes:
		if n.kind != "task_accept": continue
		var task: Dictionary = result.catalog.task_by_id(str(n.params.task))
		if task.is_empty(): errors.append(str(n.id) + "：接受任务引用失效")
		elif result.catalog.event_tasks(str(task.event_id))[0].task_id != task.task_id: errors.append(str(n.id) + "：请选择事件的第一项任务，后续任务自动接续")
	return errors
