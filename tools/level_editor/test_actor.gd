extends CharacterBody3D
var travel := Vector3.ZERO
var clone_actor := false
var oscillate := false
var oscillation_center := Vector3.ZERO
var direction := 1.0
func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	add_to_group("stealth_target")
	var cs := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.6
	cs.shape = capsule
	cs.position.y = 0.8
	add_child(cs)
func _physics_process(_delta: float) -> void:
	velocity = travel
	if oscillate:
		if global_position.x > oscillation_center.x + 0.65: direction = -1
		if global_position.x < oscillation_center.x - 0.65: direction = 1
		velocity.x = direction * 2
	velocity.y = -1
	move_and_slide()
func is_clone() -> bool: return clone_actor
