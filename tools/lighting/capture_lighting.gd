extends Node
## Actual-game capture: --scene=... --lighting=... --capture-dir=/absolute/path
var game: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	var scene_path := "res://scenes/main.tscn"
	var lighting_path := ""
	var output := "/tmp/branch_sunlight_v2/before"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="): scene_path = argument.trim_prefix("--scene=")
		if argument.begins_with("--lighting="): lighting_path = argument.trim_prefix("--lighting=")
		if argument.begins_with("--capture-dir="): output = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	game = load(scene_path).instantiate()
	if "persist_progress" in game: game.persist_progress = false
	add_child(game)
	await _wait(15)
	if not lighting_path.is_empty():
		var old: Node = game.get_node_or_null("World/Lighting")
		if old == null: old = game.get_node("Lighting")
		var parent := old.get_parent()
		parent.remove_child(old)
		old.free()
		var replacement: Node = load(lighting_path).instantiate()
		replacement.name = "Lighting"
		parent.add_child(replacement)
	await _wait(100)
	await _capture(output.path_join("spawn.png"))
	var rig: Node3D = game.get_node("CameraRig")
	rig.distance = 19.0
	rig._apply()
	await _wait(35)
	await _capture(output.path_join("close.png"))
	if scene_path.ends_with("main.tscn"):
		game.player.position = Vector3(16, 0.05, -1)
		game.player.velocity = Vector3.ZERO
		await _wait(100)
		await _capture(output.path_join("mechanisms.png"))
	game.queue_free()
	await _wait(3)
	Timeline.clear()
	get_tree().quit()

func _wait(count: int) -> void:
	for i in count: await get_tree().process_frame

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " ", result)
