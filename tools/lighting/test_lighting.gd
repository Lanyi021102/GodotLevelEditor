extends Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func wait(count: int) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame

func in_focus(camera: Camera3D, attributes: CameraAttributesPractical, point: Vector3) -> bool:
	var depth := -camera.to_local(point).z
	return depth > attributes.dof_blur_near_distance and depth < attributes.dof_blur_far_distance

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var authored: Node = load("res://scenes/lighting/sunlit_miniature_v2.tscn").instantiate()
	check(authored.get_node("WorldEnvironment").camera_attributes == null, "authored scene has no editor depth of field resource")
	authored.free()
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	game.persist_progress = false
	add_child(game)
	await wait(15)
	var lighting: Node3D = game.get_node("World/Lighting")
	var attributes: CameraAttributesPractical = lighting.get_node("WorldEnvironment").camera_attributes
	var rig: Node3D = game.get_node("CameraRig")
	var camera: Camera3D = rig.camera
	check(game.world.runtime_valid, "default authored world still assembles")
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "third-person perspective camera is retained by lighting")
	check(camera.attributes == null and attributes != null, "V2 owns post-processing without overwriting camera resources")
	check(not attributes.dof_blur_near_enabled and not attributes.dof_blur_far_enabled, "third-person gameplay keeps distant clues sharp")
	var unchanged_editor: Node = load("res://scenes/lighting/sunlit_miniature_v2.tscn").instantiate()
	check(unchanged_editor.get_node("WorldEnvironment").camera_attributes == null, "running the game does not attach blur to the authored editor scene")
	unchanged_editor.free()
	for room in game.world.rooms():
		var floor: Node3D = room.object_by_id("floor")
		check(is_equal_approx(floor.size.y, 3.6) and is_zero_approx(floor.position.y + floor.size.y * 0.5), room.room_id + " thick floor preserves the original walkable height")
	check(in_focus(camera, attributes, game.player.global_position) and in_focus(camera, attributes, game.player.global_position + Vector3.UP * 1.78), "player head and feet remain sharp")
	check(in_focus(camera, attributes, game.player.global_position + Vector3(3, 0, 0)), "nearby interaction area remains sharp")
	var distances := [rig.min_distance, rig.max_distance]
	for distance in distances:
		rig.distance = distance
		rig.pitch_degrees = rig.max_pitch if distance == rig.min_distance else rig.min_pitch
		rig.yaw_degrees += 95.0
		rig._apply()
		await wait(3)
		check(in_focus(camera, attributes, game.player.global_position + Vector3.UP), "focus follows zoom and rotation at distance %.1f" % distance)
	# Lighting follows a distant camera while whitebox simulation runs.
	rig.distance = 19.0
	rig._apply()
	await wait(3)
	check(in_focus(camera, attributes, game.player.global_position + Vector3.UP), "focus updates for a distant whitebox view")
	var other: Node = load("res://scenes/lighting/sunlit_miniature_v2.tscn").instantiate()
	check(attributes != other.runtime_camera_attributes, "separate V2 instances have independent focus resources")
	other.free()
	var v1: Node = load("res://scenes/lighting/cloud_island_v1.tscn").instantiate()
	check(v1.get_meta("lighting_version") == 1 and v1.get_node("WorldEnvironment").camera_attributes == null, "V1 baseline remains independently usable")
	v1.free()
	game.queue_free()
	await wait(3)
	print("LIGHTING: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
