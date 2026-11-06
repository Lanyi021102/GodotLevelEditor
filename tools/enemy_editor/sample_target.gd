extends CharacterBody3D
func _ready() -> void:
	add_to_group("stealth_target")
func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	velocity = Vector3(input.x * 4, -1, input.y * 4)
	move_and_slide()
	global_position.x = clampf(global_position.x, -12, 12)
	global_position.z = clampf(global_position.z, -12, 12)
func is_crouching() -> bool:
	return false
func tl_capture() -> Dictionary:
	return {"transform": global_transform, "velocity": velocity}
func tl_restore(data: Dictionary) -> void:
	global_transform = data.transform
	velocity = data.velocity
