extends Node
const OUT = "res://docs/levels/dusk_mountain_2026-11-16/"

func shot(filename: String) -> void:
	for i in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + filename + ".png")

func _ready() -> void: run.call_deferred()

func run() -> void:
	var world: Node3D = load("res://content/scenes/levels/dusk_mountain_house.tscn").instantiate()
	get_tree().root.add_child(world); get_tree().current_scene = world
	for i in 30: await get_tree().physics_frame
	var main := get_tree().get_first_node_in_group("main")
	main.camera_rig.release_mouse()
	await shot("01_spawn")
	var camera := Camera3D.new(); world.add_child(camera); camera.current = true; camera.fov = 62
	camera.global_position = Vector3(51, 54, 64); camera.look_at(Vector3(0, 0, -10))
	await shot("02_overview")
	camera.global_position = Vector3(24, 17, -22); camera.look_at(Vector3(0, 5.4, -47))
	await shot("03_house")
	camera.global_position = Vector3(5.5, 6.7, -54); camera.look_at(Vector3(0, 5.4, -46))
	await shot("04_interior")
	print("DUSK_PREVIEW_PASS"); get_tree().quit()
