extends SceneTree
## Run against the saved fixture from --terrain-test in the same isolated project.
const FIXTURE := "res://content/scenes/levels/terrain_probe.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if change_scene_to_file(FIXTURE) != OK:
		quit(1)
		return
	await scene_changed
	var world := current_scene
	for i in 16:
		await physics_frame
	var terrain := world.get_node("Terrain")
	var actor := get_first_node_in_group("godot_level_editor_player") as CharacterBody3D
	if actor == null or terrain.surface == null:
		push_error("Terrain fixture did not start its real F6 player or terrain")
		quit(1)
		return
	var direct := actor.get_world_3d().direct_space_state
	var hit := direct.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4, 15, 20), Vector3(-4, -20, 20), 1))
	var bed: bool = not hit.is_empty() and hit.position.y < -0.8 and hit.collider.get_parent() == terrain
	print("[PASS] " if bed else "[FAIL] ", "saved riverbed is the actual runtime collision, below the template floor")
	var from := actor.global_position
	actor.camera_rig.capture_mouse()
	Input.action_press("move_forward")
	var on_surface := 0
	for i in 900:
		await physics_frame
		if actor.is_on_floor():
			on_surface += 1
	Input.action_release("move_forward")
	var to := actor.global_position
	var walked := from.z > 0.0 and to.z < -13.0 and on_surface > 720
	print("[PASS] " if walked else "[FAIL] ", "real player walks on generated collision ", from, " → ", to, " grounded frames ", on_surface)
	quit(0 if bed and walked else 1)
