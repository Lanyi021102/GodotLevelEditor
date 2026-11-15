@tool
extends RefCounted
static func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(60, true).timeout.connect(func(): tree.quit(2))
	var result := preload("res://addons/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	if result.catalog == null: print(result.errors); tree.quit(1); return
	DirAccess.make_dir_recursive_absolute("res://resources/level_previews")
	for row in result.catalog.levels:
		var viewport := SubViewport.new(); viewport.size = Vector2i(1024, 720); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		suite.add_child(viewport)
		var world: Node3D = load(row.scene_path).instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		# Static editor thumbnails only; source scenes and gameplay are never modified.
		for child in world.find_children("*", "Node", true, false):
			if is_instance_valid(child) and child.get_script() == preload("res://scripts/presentation/miniature_lighting.gd"): child.free()
		for child in world.find_children("*", "WorldEnvironment", true, false): child.environment = null
		viewport.add_child(world)
		for i in 5: await tree.process_frame
		var bounds := AABB(); var first := true
		for node in world.find_children("*", "Node3D", true, false):
			if node.get_meta("godot_level_editor_room_preview", false): node.hide()
			if node.get_script() != preload("res://addons/godot_level_editor/runtime/whitebox_block.gd"): continue
			var block: AABB = node.global_transform * AABB(Vector3(-node.size.x * 0.5, 0, -node.size.z * 0.5), node.size)
			bounds = block if first else bounds.merge(block); first = false
		if first: bounds = AABB(Vector3(-10, 0, -10), Vector3(20, 5, 20))
		var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color("e9edf2"); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.65; viewport.add_child(environment)
		var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-54, -35, 0); light.light_energy = 1.2; light.shadow_enabled = true; viewport.add_child(light)
		var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = maxf(12, maxf(bounds.size.x, bounds.size.z) * 1.15); camera.far = 1000; viewport.add_child(camera); camera.position = bounds.get_center() + Vector3(1.1, 1.0, 1.4) * camera.size; camera.look_at(bounds.get_center(), Vector3.UP); camera.current = true
		for i in 10: await tree.process_frame
		RenderingServer.force_draw(false)
		viewport.get_texture().get_image().save_png("res://resources/level_previews/" + str(row.level_id) + ".png")
		viewport.queue_free(); await tree.process_frame
	print("LEVEL EDITOR STATIC PREVIEWS: ", result.catalog.levels.size(), " saved")
	tree.quit()
