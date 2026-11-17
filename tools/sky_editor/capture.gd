extends Node
func wait_frames(count := 20) -> void:
	for i in count: await get_tree().process_frame
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	var game: Node = load("res://content/scenes/main.tscn").instantiate()
	add_child(game); await wait_frames(30)
	var world: Node3D = game.get_node("World")
	var rig: Node3D = game.get_node("CameraRig")
	rig.release_mouse(); rig.pitch_degrees = -8; rig.yaw_degrees = 25; rig._apply()
	# Temporary whitebox silhouettes show depth, shadows and visibility at a fixed viewpoint.
	for i in 5:
		var block := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = Vector3(1.4, 2.0 + i * 0.8, 1.4); block.mesh = mesh; block.position = Vector3(-7 + i * 3, mesh.size.y * 0.5, -5)
		var material := StandardMaterial3D.new(); material.albedo_color = Color(0.8, 0.82, 0.85); block.material_override = material; world.add_child(block)
	DirAccess.make_dir_recursive_absolute("res://docs/sky_editor/validation")
	for name in ["clear", "overcast", "sunset", "night", "morning"]:
		world.sky_preset = load("res://addons/godot_level_editor/resources/sky_presets/builtin/" + name + ".tres")
		await wait_frames(40); await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://docs/sky_editor/validation/" + name + ".png")
		print("CAPTURE ", name)
	get_tree().quit()
