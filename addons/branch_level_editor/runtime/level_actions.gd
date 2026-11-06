extends RefCounted
## Whitelisted bridges to existing components; no arbitrary method/property execution.
var world: Node
func _player(context: Dictionary = {}) -> Node3D:
	var path := str(context.get("actor", ""))
	if not path.is_empty():
		var candidate := world.get_node_or_null(NodePath(path))
		if candidate is Node3D and _controlled(candidate): return candidate
	for body in world.get_tree().get_nodes_in_group("branch_player"):
		if body is Node3D and _controlled(body): return body
	return null
func _controlled(actor: Node3D) -> bool:
	return actor.is_in_group("branch_player") and not (actor.has_method("is_clone") and actor.call("is_clone"))
func _agent(actor: Node3D) -> Node:
	if actor == null: return null
	if actor.has_method("level_kill"): return actor
	for child in actor.get_children():
		if child.has_method("level_kill") and child.has_method("level_test_state"): return child
	return null
func condition(node: Dictionary) -> bool:
	var actor := _player()
	if actor == null: return false
	var agent := _agent(actor)
	if node.kind == "has_item":
		if agent != null and agent.has_method("level_has_item"): return agent.call("level_has_item", str(node.params.key))
		var abilities := world.get_node_or_null("/root/Abilities")
		return abilities != null and abilities.call("has", str(node.params.key))
	if agent != null: return agent.call("level_test_state", str(node.params.get("state", "alive")))
	match str(node.params.get("state", "alive")):
		"alive": return actor.visible and actor.is_physics_processing()
		"moving": return actor is CharacterBody3D and Vector2(actor.velocity.x, actor.velocity.z).length() > 0.1
		"crouching": return actor.has_method("is_crouching") and actor.call("is_crouching")
		"on_floor": return actor is CharacterBody3D and actor.is_on_floor()
		"clone": return actor.has_method("is_clone") and actor.call("is_clone")
	return false
func perform(node: Dictionary, context: Dictionary) -> Dictionary:
	if node.kind == "kill_player":
		var agent := _agent(_player(context))
		if agent == null: return {"ok": false, "reason": "玩家尚未接入关卡操作接口，本次未执行击杀"}
		var ok: bool = agent.call("level_kill", str(node.params.get("reason", "关卡事件")))
		return {"ok": ok, "reason": "玩家已死亡" if ok else "玩家已死亡或拒绝本次击杀"}
	var object: Node = world.object_by_id(str(node.params.get("object", "")))
	if object == null: return {"ok": false, "reason": "目标物件不存在"}
	if node.kind == "set_visibility":
		object.visible = bool(node.params.get("enabled", true))
		return {"ok": true, "reason": "物件已显示" if object.visible else "物件已隐藏"}
	var component: Node = object.call("output_component") if object.has_method("output_component") else object
	if component == null: return {"ok": false, "reason": "目标组件尚未提供"}
	if node.kind == "set_switch":
		if not component.has_method("set_powered"): return {"ok": false, "reason": "目标不是可设置的开关；压力板由实际占位驱动"}
		component.call("set_powered", bool(node.params.get("enabled", true)))
		return {"ok": true, "reason": "开关已打开" if node.params.get("enabled", true) else "开关已关闭"}
	if node.kind == "enemy_patrol":
		if component.has_method("level_start_patrol"):
			return {"ok": bool(component.call("level_start_patrol")), "reason": "已请求敌人开始巡逻"}
		if not component is GuardAI: return {"ok": false, "reason": "敌人未提供巡逻接口"}
		if component.enemy_definition != null and component.enemy_definition.state_by_id("patrol").is_empty(): return {"ok": false, "reason": "敌人未定义巡逻，请先配置敌人状态图"}
		var snapshot: Dictionary = component.tl_capture()
		if snapshot.has("enemy_machine"):
			snapshot.enemy_machine.state_id = "patrol"
			snapshot.enemy_machine.timer = 0.0
			snapshot.enemy_machine.last_transition = "level_event"
			snapshot.enemy_machine.last_reason = "关卡事件：开始巡逻"
		snapshot["state"] = 0
		snapshot["timer"] = 0.0
		snapshot["alert"] = 0.0
		snapshot["has_last_known"] = false
		snapshot["target_path"] = NodePath()
		snapshot["saw_target"] = false
		snapshot["anim_state"] = ""
		component.tl_restore(snapshot)
		component.set_physics_process(true)
		return {"ok": true, "reason": "敌人已进入巡逻；继续使用原感知与状态机"}
	return {"ok": false, "reason": "未知操作"}
