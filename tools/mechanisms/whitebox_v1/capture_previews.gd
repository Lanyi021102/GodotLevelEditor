extends Node

func _ready() -> void:
	var output := "res://resources/mechanisms/whitebox_v1/previews"
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new(); viewport.size = Vector2i(512, 320); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(viewport)
	var stage := Node3D.new(); viewport.add_child(stage)
	var environment := WorldEnvironment.new(); var settings := Environment.new(); settings.background_mode = Environment.BG_COLOR; settings.background_color = Color("e9eff5"); settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color = Color.WHITE; settings.ambient_light_energy = 0.75; settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC; environment.environment = settings; stage.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-55, -30, 0); light.light_energy = 0.8; light.shadow_enabled = true; stage.add_child(light)
	var floor_mesh := MeshInstance3D.new(); var floor_plane := PlaneMesh.new(); floor_plane.size = Vector2(30, 30); floor_mesh.mesh = floor_plane; floor_mesh.position.y = -0.04
	var material := StandardMaterial3D.new(); material.albedo_color = Color("c5d0dc"); material.roughness = 1.0; floor_mesh.material_override = material; stage.add_child(floor_mesh)
	settings.ambient_light_energy = 0.35; settings.ssao_enabled = true
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; stage.add_child(camera); camera.current = true
	for kind in ["button", "toggle_switch", "pressure_plate", "sliding_door", "hinged_door", "lift_platform", "terminal", "button_door", "dual_plate_door", "terminal_lift"]:
		var instance: Node3D = load("res://scenes/mechanisms/" + kind + ".tscn").instantiate(); stage.add_child(instance)
		for label in instance.find_children("*", "Label3D", true, false): label.hide()
		var large: bool = kind in ["button_door", "dual_plate_door", "terminal_lift"]
		camera.size = 8.5 if large else float({"button": 2.2, "toggle_switch": 2.6, "pressure_plate": 4.0, "sliding_door": 5.5, "hinged_door": 5.5, "lift_platform": 6.8, "terminal": 2.8}[kind])
		camera.position = Vector3(8, 5.7, 9) if large else Vector3(5.2, 3.9, 6)
		camera.look_at(Vector3(0, 1.1 if kind in ["sliding_door", "hinged_door", "lift_platform"] or large else 0.5, 0))
		for tick in 8: await get_tree().process_frame
		RenderingServer.force_draw(false)
		var result := viewport.get_texture().get_image().save_png(output + "/" + kind + ".png")
		print("PREVIEW ", kind, " ", result)
		stage.remove_child(instance); instance.free()
	get_tree().quit()
