extends Node
## Optional player-side adapter; the coordinator can delegate these same methods instead.
signal killed(reason: String)
@export_node_path("CharacterBody3D") var actor_path := NodePath("..")
@export var unlocked_items := PackedStringArray()
var dead := false
var actor: Node3D
var _baseline := {}
func _ready() -> void:
	add_to_group("branch_level_actor_agent")
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
func level_has_item(key: String) -> bool: return unlocked_items.has(key)
func level_test_state(state: String) -> bool:
	if actor == null: return false
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
	return {"dead": dead, "baseline": baseline}
func tl_restore(state: Dictionary) -> void:
	_baseline = state.get("baseline", _baseline).duplicate()
	dead = bool(state.get("dead", false))
	if actor == null: return
	actor.visible = not dead and bool(_baseline.get("visible", true))
	actor.set_physics_process(not dead and bool(_baseline.get("physics", true)))
	if actor is CollisionObject3D: actor.set_deferred("collision_layer", 0 if dead else int(_baseline.get("layer", 2)))
