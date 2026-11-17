class_name KineticPlate
extends PressurePlate
## Motion-powered relay: only occupants above the speed threshold supply power.
@export var minimum_speed := 0.75
func occupant_count() -> int:
	var count := 0
	for body in get_overlapping_bodies():
		if body is CharacterBody3D and body.is_in_group("stealth_target") and body.visible and body.is_physics_processing():
			var speed := Vector2(body.velocity.x, body.velocity.z).length()
			if speed >= minimum_speed:
				count += 1
	return count
