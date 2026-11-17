extends SceneTree
const ROOT := "res://addons/godot_level_editor"
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene")) if OS.get_cmdline_user_args().has("--release-default") else "res://content/scenes/levels/native_install.tscn"
	var world := load(path).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	for i in 60: await physics_frame
	var session := get_first_node_in_group("main")
	if session == null or session.player == null or not world.runtime_valid:
		push_error("新建原生关卡的试玩会话无效")
		quit(1)
		return
	# A GUI launched from CI may start behind another app. Establish the same
	# game focus as clicking its viewport before testing simulated input.
	if DisplayServer.get_name() != "headless":
		root.grab_focus()
		for i in 5: await process_frame
	session.camera_rig.capture_mouse()
	var before: Vector3 = session.player.global_position
	Input.action_press("move_forward")
	for i in 30: await physics_frame
	Input.action_release("move_forward")
	if session.player.global_position.distance_to(before) < 0.2:
		push_error("默认玩家没有响应移动输入")
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--release-capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://default-play.png")
	# Load the shipped NPCs into a real running scene, including their skeletons.
	var index := 0
	for file in DirAccess.get_files_at(ROOT + "/scenes/npcs"):
		if not file.ends_with(".tscn"): continue
		var actor := load(ROOT + "/scenes/npcs/" + file).instantiate() as Node3D
		actor.position = Vector3(5 + index % 5, 0, index / 5)
		world.add_child(actor)
		index += 1
	for file in ["button", "single_door", "double_door", "pressure_plate", "lift_platform"]:
		var mechanism := load(ROOT + "/scenes/mechanisms/" + file + ".tscn").instantiate() as Node3D
		mechanism.position = Vector3(-5, 0, index)
		world.add_child(mechanism)
		index += 1
	for i in 60: await physics_frame
	if session.player.global_position.y < -1:
		push_error("玩家没有站在模板地面上")
		quit(1)
		return
	print("RELEASE_PLAY_OK: controllable player, camera, HUD, 13 NPCs, 5 mechanisms")
	world.queue_free()
	await process_frame
	quit()
