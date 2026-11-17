extends RefCounted
const MECHANISMS := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_nodes.gd")
## Whitelisted actor queries; never evaluates arbitrary expressions or property paths.
var world: Node
var objectives: Dictionary = {}
var legacy: RefCounted

func actor(id: String = "") -> Node:
	if not id.is_empty(): return world.object_by_id(id)
	return world.get_tree().get_first_node_in_group("godot_level_editor_player")

func agent(id: String = "") -> Node:
	var node := actor(id)
	if node == null: return null
	if node.has_method("level_has_item"): return node
	if node.has_method("output_component"):
		var component: Node = node.output_component()
		if component != null:
			if component.has_method("level_has_item"): return component
			for child in component.get_children():
				if child.has_method("level_has_item"): return child
	for child in node.get_children():
		if child.has_method("level_has_item"): return child
	return null

func condition(n: Dictionary) -> bool:
	if n.kind == "room_active":
		if not is_instance_valid(world): return false
		for room in world.rooms():
			if room.room_id == str(n.params.get("room", "")): return room.is_active() == bool(n.params.get("expected", true))
		return false
	if n.kind in ["mechanism_state", "wait_mechanism_state"]: return MECHANISMS.condition(world, n)
	var p: Dictionary = n.params
	if n.kind == "objective_state": return objectives.get(p.key, {}).get("state", "") == p.status
	var target := agent(str(p.get("actor", "")))
	if n.kind in ["has_item", "has_equipped", "actor_state", "state_changed"]:
		if target == null: return false
		match str(n.kind):
			"has_item": return target.has_method("level_inventory_count") and target.level_inventory_count(p.key) >= int(p.get("amount", 1))
			"has_equipped": return target.has_method("level_has_equipped") and target.level_has_equipped(p.slot, p.key)
			_: return target.has_method("level_test_state") and target.level_test_state(p.key) == p.expected
	return legacy.condition(n) if legacy != null else false

func perform(n: Dictionary, context: Dictionary) -> Dictionary:
	if MECHANISMS.is_action(str(n.kind)): return MECHANISMS.perform(world, n)
	var target := agent(str(n.params.get("actor", "")))
	var ok := false
	match str(n.kind):
		"change_item": ok = target != null and target.has_method("level_change_item") and target.level_change_item(n.params.key, int(n.params.amount))
		"equip_item": ok = target != null and target.has_method("level_equip_item") and target.level_equip_item(n.params.slot, n.params.key)
		"set_actor_state": ok = target != null and target.has_method("level_set_state") and target.level_set_state(n.params.key, n.params.enabled)
		_: return legacy.perform(n, context) if legacy != null else {"ok": false, "reason": "未接入组件"}
	return {"ok": ok, "reason": "角色数据已更新" if ok else "角色接口缺失、物件不足或参数无效"}
