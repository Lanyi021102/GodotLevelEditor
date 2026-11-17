extends SceneTree
var output := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--media-output="): output = arg.trim_prefix("--media-output=")
	_run.call_deferred()

func capture(view: SubViewport, name: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(output + "/" + name + ".png")

func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1920, 1080)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world := load("res://content/scenes/levels/whitebox_courtyard.tscn").instantiate() as Node3D
	view.add_child(world)
	var session: Node3D = load("res://addons/godot_level_editor/scenes/level_editor/play_session.tscn").instantiate()
	world.add_child(session)
	for i in 90: await physics_frame
	var overview := Camera3D.new()
	world.add_child(overview)
	overview.position = Vector3(19, 16, 23)
	overview.look_at(Vector3(0, 1, -1))
	overview.projection = Camera3D.PROJECTION_ORTHOGONAL
	overview.size = 26
	overview.current = true
	await capture(view, "07_whitebox_play_landscape")
	view.size = Vector2i(1440, 1440)
	overview.size = 28
	await capture(view, "08_whitebox_play_square")
	view.size = Vector2i(1080, 1440)
	overview.size = 33
	await capture(view, "11_whitebox_play_portrait")
	overview.current = false
	session.get_node("CameraRig/Arm/Camera3D").current = true
	view.size = Vector2i(1080, 1350)
	await capture(view, "09_player_play_portrait")
	view.size = Vector2i(1080, 1920)
	await capture(view, "10_player_play_vertical")
	world.queue_free()
	await process_frame
	print("MEDIA_PLAY_OK")
	quit()
