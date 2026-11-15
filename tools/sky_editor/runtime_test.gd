extends Node
const PRESET := preload("res://addons/godot_level_editor_sky/preset.gd")
const LIBRARY := preload("res://addons/godot_level_editor_sky/library.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)
func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	for path in LIBRARY.paths(LIBRARY.DIRECTORY + "/builtin"):
		var profile: Resource = load(path)
		check(profile.validate().is_empty(), "valid built-in: " + profile.display_name)
	var profile := PRESET.new()
	profile.sun_mode = 1
	profile.hour = 6; check(absf(profile.solar_angles().x) < 0.001, "sunrise artistic day")
	profile.hour = 12; check(is_equal_approx(profile.solar_angles().x, 65.0), "noon artistic day")
	profile.hour = 18; check(absf(profile.solar_angles().x) < 0.001, "sunset artistic day")
	profile.hour = 0; check(profile.solar_angles().x < -60, "night sun below horizon")
	profile.sun_mode = 0; profile.elevation = 23; profile.azimuth = 145
	check(profile.solar_angles().is_equal_approx(Vector2(23, 145)), "manual angles independent from clock")
	profile.sky_mode = 1; check(not profile.validate().is_empty(), "missing HDRI rejected")
	profile.sky_mode = 0; profile.fog_end = profile.fog_begin
	check(not profile.validate().is_empty(), "invalid fog interval rejected")
	profile.fog_end = 120; profile.version = 9; check(not profile.validate().is_empty(), "unsupported resource version rejected")
	profile.version = 1
	var world: Node3D = load("res://scenes/levels/whitebox_world.tscn").instantiate()
	world.sky_preset = null
	add_child(world); await frames()
	var original_env: Environment = world.get_world_3d().environment
	var original_attributes: CameraAttributes = world.get_world_3d().camera_attributes
	var legacy_env: Environment = world.get_node("Lighting/WorldEnvironment").environment
	var legacy_sun: DirectionalLight3D = world.get_node("Lighting/Sun")
	profile.fog_enabled = true; profile.fog_begin = 20; profile.fog_end = 120; profile.fog_density = 0.4; profile.cloud_height = 2400
	check(world.preview_sky(profile).is_empty(), "preview accepts valid definition")
	check(world.sky_preset == null, "preview does not create a level binding")
	check(world.get_world_3d().environment != original_env and world.sky_runtime.environment.fog_depth_end == 120, "preview controls actual world environment and fog")
	check(world.sky_runtime.environment.sky.sky_material.get_shader_parameter("cloud_height") == 2400, "cloud height reaches sky layer")
	check(world.get_node("Lighting/WorldEnvironment").environment == legacy_env and legacy_sun.visible, "preview preserves authored legacy environment and light visibility")
	var packed := PackedScene.new(); packed.pack(world)
	var state := packed.get_state(); var transient_saved := false
	for i in state.get_node_count(): transient_saved = transient_saved or str(state.get_node_name(i)) == "SkyRuntime"
	check(not transient_saved, "runtime nodes excluded from scene serialization")
	world.refresh_sky()
	check(world.get_world_3d().environment == original_env and world.get_world_3d().camera_attributes == original_attributes, "ending preview restores original environment and camera attributes")
	var baseline: Resource = load(LIBRARY.DEFAULT)
	var old_exposure: float = baseline.base_environment.tonemap_exposure
	world.sky_preset = baseline; await frames()
	check(world.sky_runtime.environment != baseline.base_environment, "bound baseline uses a private environment")
	world.sky_runtime.environment.tonemap_exposure = 4.0
	check(baseline.base_environment.tonemap_exposure == old_exposure, "runtime edits cannot mutate shared baseline")
	profile.sun_mode = 1; profile.hour = 0
	world.preview_sky(profile)
	check(is_zero_approx(world.sky_runtime.sun.light_energy), "night time turns off solar direct light")
	var image := Image.create(16, 8, false, Image.FORMAT_RGBF); image.fill(Color(0.3, 0.5, 0.8))
	profile.hdri = ImageTexture.create_from_image(image); profile.sky_mode = 1; profile.hdri_rotation = 70
	world.preview_sky(profile)
	check(world.sky_runtime.environment.sky.sky_material is PanoramaSkyMaterial, "HDRI uses panorama material")
	check(is_equal_approx(world.sky_runtime.environment.sky_rotation.y, deg_to_rad(70)), "HDRI rotation applied")
	profile.hdri_lighting = false; world.preview_sky(profile)
	check(world.sky_runtime.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "HDRI background can use independent color fill")
	world.sky_preset = null; await frames()
	check(world.get_world_3d().environment == original_env, "unbinding restores legacy lighting")
	world.free(); await frames()
	# Exercise a saved sky reference through the real standalone (F6) session path.
	world = load("res://scenes/levels/whitebox_world.tscn").instantiate()
	world.sky_preset = load("res://resources/sky_presets/builtin/overcast.tres")
	packed = PackedScene.new(); packed.pack(world); ResourceSaver.save(packed, "user://sky_standalone_test.tscn"); world.free()
	world = load("user://sky_standalone_test.tscn").instantiate()
	get_tree().root.add_child(world); get_tree().current_scene = world
	await frames(20)
	check(world.has_node("PlaySession") and world.sky_runtime.active_preset.display_name == "柔光阴天", "F6 standalone applies saved weather and creates standard play session")
	check(world.get_world_3d().environment == world.sky_runtime.environment and get_tree().get_nodes_in_group("godot_level_editor_player").size() == 1, "F6 camera and single player use the bound environment")
	world.free(); await frames()
	print("SKY_RUNTIME_RESULT checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
