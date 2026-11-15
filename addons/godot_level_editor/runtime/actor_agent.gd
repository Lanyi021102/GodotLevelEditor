extends Node
## Optional player-side adapter; the coordinator can delegate these same methods instead.
signal killed(reason: String)
@export_node_path("Node3D") var actor_path := NodePath("..")
@export var unlocked_items := PackedStringArray()
@export var inventory: Dictionary = {}
@export var equipment: Dictionary = {}
@export var state_flags: Dictionary = {}
signal inventory_changed(key: String, amount: int)
signal equipment_changed(slot: String, key: String)
signal state_changed(key: String, value: bool)
var dead := false
var actor: Node3D
var _baseline := {}
func _ready() -> void:
	add_to_group("godot_level_editor_level_actor_agent")
	actor = get_node_or_null(actor_path) as Node3D
	if actor != null:
		_baseline = {"visible": actor.visible, "physics": actor.is_physics_processing(), "layer": actor.collision_layer if actor is CollisionObject3D else 0}
func level_kill(reason: String = "关卡事件") -> bool:
	if actor == null or dead: return false
	_baseline = {"visible": actor.visible, "physics": actor.is_physics_processing(), "layer": actor.collision_layer if actor is CollisionObject3D else 0}
	dead = true
	actor.set_physics_process(false)
	if actor is CharacterBody3D: actor.velocity = Vector3.ZERO
	actor.visible = false
	if actor is CollisionObject3D: actor.set_deferred("collision_layer", 0)
	killed.emit(reason)
	return true
func level_inventory_count(key: String) -> int:
	return maxi(0, int(inventory.get(key, 1 if unlocked_items.has(key) else 0)))
func level_has_item(key: String) -> bool: return level_inventory_count(key) > 0
func level_change_item(key: String, amount: int) -> bool:
	if key.is_empty() or level_inventory_count(key) + amount < 0: return false
	inventory[key] = level_inventory_count(key) + amount
	if inventory[key] == 0:
		for slot in equipment.keys():
			if equipment[slot] == key: equipment.erase(slot); equipment_changed.emit(slot, "")
	inventory_changed.emit(key, inventory[key])
	return true
func level_has_equipped(slot: String, key: String) -> bool:
	return equipment.values().has(key) if slot.is_empty() else equipment.get(slot, "") == key
func level_equip_item(slot: String, key: String) -> bool:
	if slot.is_empty() or (not key.is_empty() and not level_has_item(key)): return false
	equipment[slot] = key
	equipment_changed.emit(slot, key)
	return true
func level_set_state(key: String, value: bool) -> bool:
	if key.is_empty(): return false
	var changed: bool = not state_flags.has(key) or state_flags[key] != value
	state_flags[key] = value
	if changed: state_changed.emit(key, value)
	return true
func level_test_state(state: String) -> bool:
	if actor == null: return false
	if state_flags.has(state): return bool(state_flags[state])
	match state:
		"alive": return not dead
		"clone": return actor.has_method("is_clone") and actor.call("is_clone")
		"crouching": return not dead and actor.has_method("is_crouching") and actor.call("is_crouching")
		"moving": return not dead and actor.is_physics_processing() and actor is CharacterBody3D and Vector2(actor.velocity.x, actor.velocity.z).length() > 0.1
		"on_floor": return not dead and actor is CharacterBody3D and actor.is_on_floor()
	return false
func tl_capture() -> Dictionary:
	var baseline := _baseline.duplicate()
	if actor != null and not dead:
		baseline = {"visible": actor.visible, "physics": actor.is_physics_processing(), "layer": actor.collision_layer if actor is CollisionObject3D else 0}
	return {"dead": dead, "baseline": baseline, "inventory": inventory.duplicate(true), "equipment": equipment.duplicate(true), "state_flags": state_flags.duplicate(true)}
func tl_restore(state: Dictionary) -> void:
	_baseline = state.get("baseline", _baseline).duplicate()
	dead = bool(state.get("dead", false))
	inventory = state.get("inventory", inventory).duplicate(true)
	equipment = state.get("equipment", equipment).duplicate(true)
	state_flags = state.get("state_flags", state_flags).duplicate(true)
	if actor == null: return
	actor.visible = not dead and bool(_baseline.get("visible", true))
	actor.set_physics_process(not dead and bool(_baseline.get("physics", true)))
	if actor is CollisionObject3D: actor.set_deferred("collision_layer", 0 if dead else int(_baseline.get("layer", 2)))
