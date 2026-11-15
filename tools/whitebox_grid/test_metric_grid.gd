extends Node3D
const BLOCK := preload("res://addons/godot_level_editor/runtime/whitebox_block.gd")
const SHAPES := preload("res://addons/godot_level_editor/runtime/whitebox_shapes.gd")
const GRID := preload("res://scripts/tools/metric_grid.gd")
var failures := 0
var checks := 0
var render_checks := false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame
func _ready() -> void:
	get_tree().create_timer(55).timeout.connect(func(): get_tree().quit(2))
	render_checks = "--grid-render" in OS.get_cmdline_user_args()
	for kind in SHAPES.LABELS:
		var block := BLOCK.new()
		block.shape_kind = kind
		block.size = Vector3(2, 1.5, 3)
		block.scale = Vector3(1.5, 0.8, 0.6)
		add_child(block)
		var meshes := block.find_children("*", "MeshInstance3D", false, false)
		check(meshes.size() == 1 and meshes[0].material_override is ShaderMaterial and meshes[0].material_override.shader == GRID.MATERIAL.shader, kind + " uses the shared metric grid")
		block.free()
	var first := BLOCK.new()
	var second := BLOCK.new()
	first.tint = Color(0.3, 0.4, 0.5)
	add_child(first)
	add_child(second)
	var mat_a: ShaderMaterial = first.get_child(0).material_override
	var mat_b: ShaderMaterial = second.get_child(0).material_override
	check(mat_a != mat_b and mat_a.get_shader_parameter("base_color") == first.tint, "per-object tint does not modify the shared material")
	var custom := Node3D.new()
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	visual.material_override = StandardMaterial3D.new()
	custom.add_child(visual)
	visual.owner = custom
	var packed := PackedScene.new()
	packed.pack(custom)
	custom.free()
	second.visual_scene = packed
	await frames()
	check(second.get_child(0).get_child(0).material_override is StandardMaterial3D, "authored replacement art retains its own material")
	first.free()
	second.free()
	var playground := load("res://scenes/3cplayground.tscn").instantiate() as Node3D
	add_child(playground)
	await frames(8)
	var all_grid := true
	var surfaces := 0
	for mesh in playground.get_node("World").find_children("*", "MeshInstance3D", true, false):
		surfaces += 1
		all_grid = all_grid and mesh.material_override is ShaderMaterial and mesh.material_override.shader == GRID.MATERIAL.shader
	check(all_grid and surfaces >= 30, "all %d playground solid/marking meshes use the grid in scene and generated mechanisms" % surfaces)
	var lever := playground.get_node("World/Lever")
	lever.set_powered(true)
	var grip := lever.get_node("Generated").find_children("Grip", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check(grip.material_override.get_shader_parameter("base_color") == lever.color_active and grip.material_override.get_shader_parameter("state_energy") > 0, "lever grid retains powered tint and emission")
	lever.set_powered(false)
	check(is_zero_approx(grip.material_override.get_shader_parameter("state_energy")), "lever grid clears powered emission on restore/off")
	var door := playground.get_node("World/Door")
	door.tl_restore({"ratio": 1.0, "powered": true, "command": true, "graph_driven": true})
	var panel := door.get_node("Panel") as MeshInstance3D
	check(panel.material_override.get_shader_parameter("base_color") == door.color_open, "door grid follows restored opening state")
	door.reset_state()
	if render_checks:
		await capture_playground(playground)
	playground.free()
	if render_checks:
		await calibration()
		await capture_shapes()
		await capture_world()
	print("METRIC GRID: %d checks / %d failed%s" % [checks, failures, " (includes GPU pixel spacing)" if render_checks else ""])
	get_tree().quit(1 if failures else 0)
func screenshot(path: String) -> void:
	# Let temporal AA settle after changing the inspection camera.
	await frames(48)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "saved " + path.get_file())
func capture_playground(playground: Node3D) -> void:
	var rig := playground.get_node("CameraRig")
	rig.set_process(false)
	rig.global_position = Vector3(0, 0.7, 0)
	rig.distance = 41.0
	rig.yaw_degrees = 20.0
	rig.pitch_degrees = 52.0
	rig._apply()
	await screenshot("res://docs/whitebox_grid/playground_overview.png")
	rig.global_position = Vector3(0, 0.5, 5)
	rig.distance = 8.0
	rig.yaw_degrees = 20.0
	rig._apply()
	await screenshot("res://docs/whitebox_grid/playground_detail.png")
func calibration() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 1024)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	world.add_child(environment)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	mesh.mesh = plane
	mesh.material_override = GRID.material(Color(0.5, 0.5, 0.5))
	mesh.scale = Vector3(1.7, 0.8, 0.9)
	world.add_child(mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	world.add_child(camera)
	for label in ["floor", "slope", "rotated_wall"]:
		var n := Vector3.UP
		if label == "slope": n = Vector3(0.4, 1, 0.8).normalized()
		if label == "rotated_wall": n = Vector3(1, 0, 0.7).normalized()
		var t := Vector3.RIGHT if label == "floor" else Vector3.UP.cross(n).normalized()
		var b := n.cross(t).normalized()
		mesh.basis = Basis(t, n, -b).scaled_local(Vector3(1.7, 0.8, 0.9))
		camera.position = n * 4
		camera.look_at(Vector3.ZERO, b)
		await frames(10)
		await RenderingServer.frame_post_draw
		var img := viewport.get_texture().get_image()
		var base := brightness_at(img, camera, t * 0.15 + b * 0.037)
		var minor := brightness_at(img, camera, t * 0.1 + b * 0.037)
		var half_line := brightness_at(img, camera, t * 0.5 + b * 0.037)
		var major := brightness_at(img, camera, t * 1.0 + b * 0.037)
		print("[PIXELS] ", label, " background/minor/half/major: ", [base, minor, half_line, major])
		check(major > half_line + 0.015 and half_line > minor + 0.025 and minor > base + 0.005, label + " has distinct 1m / 0.5m / 0.1m line strengths after nonuniform scale")
		var positions_ok := true
		for coordinate in [-0.9, -0.5, -0.1, 0.0, 0.1, 0.5, 0.9, 1.0]:
			var on_line := brightness_at(img, camera, t * coordinate + b * 0.037)
			var off_line := brightness_at(img, camera, t * (coordinate + 0.05) + b * 0.037)
			positions_ok = positions_ok and on_line > off_line + 0.005
		check(positions_ok, label + " rendered lines match measured positive and negative world metre coordinates")
		img.save_png("res://docs/whitebox_grid/calibration_" + label + ".png")
	viewport.free()
func brightness_at(img: Image, camera: Camera3D, point: Vector3) -> float:
	var pixel := Vector2i(camera.unproject_position(point))
	var result := 0.0
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var color := img.get_pixel(clampi(pixel.x + dx, 0, img.get_width() - 1), clampi(pixel.y + dy, 0, img.get_height() - 1))
			result = maxf(result, (color.r + color.g + color.b) / 3.0)
	return result
func capture_world() -> void:
	var current := load("res://scenes/main.tscn").instantiate() as Node3D
	add_child(current)
	await screenshot("res://docs/whitebox_grid/current_world.png")
	current.free()
func capture_shapes() -> void:
	var stage := Node3D.new()
	add_child(stage)
	stage.add_child(load("res://scenes/lighting/cloud_island_v1.tscn").instantiate())
	var floor_block := BLOCK.new()
	floor_block.size = Vector3(14, 0.4, 14)
	floor_block.position.y = -0.2
	stage.add_child(floor_block)
	var index := 0
	for kind in SHAPES.LABELS:
		var block := BLOCK.new()
		block.shape_kind = kind
		block.size = Vector3(2, 2, 2)
		block.position = Vector3((index % 4) * 3 - 4.5, 1, (index / 4) * 3 - 4.5)
		stage.add_child(block)
		index += 1
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.5
	stage.add_child(camera)
	camera.position = Vector3(10, 15, 17)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	await screenshot("res://docs/whitebox_grid/shapes.png")
	stage.free()
