@tool
extends Node3D
const PRESET := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/preset.gd")
const SKY_SHADER := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/whitebox_sky.gdshader")
var environment: Environment
var sun: DirectionalLight3D
var active_preset: Resource
var _world: World3D
var _original_environment: Environment
var _original_attributes: CameraAttributes
var _hidden: Array[VisualInstance3D] = []
var _paused: Array[Node] = []

func apply(preset: Resource) -> PackedStringArray:
	if preset == null:
		clear()
		return PackedStringArray()
	if preset.get_script() != PRESET: return PackedStringArray(["天空预设类型无效"])
	var errors: PackedStringArray = preset.validate()
	if not errors.is_empty(): return errors
	if _world == null:
		_world = get_world_3d()
		_original_environment = _world.environment
		_original_attributes = _world.camera_attributes
		_suppress(get_parent())
	if is_instance_valid(sun): sun.free()
	environment = preset.base_environment.duplicate(true) if preset.base_environment != null else Environment.new()
	environment.volumetric_fog_enabled = false
	environment.background_mode = Environment.BG_SKY
	environment.background_energy_multiplier = preset.sky_energy if preset.sky_mode == 2 else 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if preset.sky_mode == 1 and preset.hdri_lighting else Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = preset.ambient_color
	environment.ambient_light_energy = preset.ambient_energy
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = preset.exposure
	environment.fog_enabled = preset.fog_enabled
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = preset.fog_begin
	environment.fog_depth_end = preset.fog_end
	environment.fog_density = preset.fog_density
	environment.fog_light_color = preset.fog_color
	var angles: Vector2 = preset.solar_angles()
	var daylight := smoothstep(-6.0, 8.0, angles.x)
	sun = DirectionalLight3D.new()
	sun.name = "PresetSun"
	add_child(sun)
	sun.rotation_degrees = Vector3(-angles.x, -angles.y, 0)
	sun.light_color = preset.sun_color
	sun.light_energy = preset.sun_energy * daylight
	sun.light_angular_distance = preset.sun_size
	sun.shadow_enabled = preset.shadows
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 150.0
	if preset.sky_mode != 2:
		var sky := Sky.new()
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		if preset.sky_mode == 1:
			var material := PanoramaSkyMaterial.new()
			material.panorama = preset.hdri
			material.energy_multiplier = preset.sky_energy
			sky.sky_material = material
			environment.sky_rotation = Vector3(0, deg_to_rad(preset.hdri_rotation), 0)
		else:
			var material := ShaderMaterial.new()
			material.shader = SKY_SHADER
			for key in ["top_color", "horizon_color", "ground_color", "cloud_color", "cloud_height", "cloud_scale", "cloud_seed", "sky_energy", "sun_color"]:
				material.set_shader_parameter(key, preset.get(key))
			material.set_shader_parameter("cloud_coverage", preset.cloud_coverage if preset.clouds_enabled else 0.0)
			material.set_shader_parameter("sun_direction", sun.basis.z)
			material.set_shader_parameter("sun_radius", deg_to_rad(maxf(0.1, preset.sun_size) * 0.5))
			material.set_shader_parameter("daylight", daylight)
			if preset.sun_mode == 1:
				var twilight := 1.0 - smoothstep(0.0, 25.0, absf(angles.x))
				var night := Color(0.015, 0.025, 0.065)
				material.set_shader_parameter("top_color", night.lerp(preset.top_color, daylight))
				material.set_shader_parameter("horizon_color", night.lerp(preset.horizon_color.lerp(Color(0.95, 0.45, 0.22), twilight * 0.65), daylight))
				material.set_shader_parameter("cloud_color", Color(0.06, 0.08, 0.14).lerp(preset.cloud_color, daylight))
			sky.sky_material = material
		environment.sky = sky
	_world.environment = environment
	var attributes := CameraAttributesPractical.new()
	attributes.auto_exposure_enabled = false
	_world.camera_attributes = attributes
	active_preset = preset.copy_preset()
	return PackedStringArray()

func _suppress(node: Node) -> void:
	for child in node.get_children():
		if child == self: continue
		# RenderingServer changes never alter authored node properties or scene files.
		if child is DirectionalLight3D or child is FogVolume:
			_hidden.append(child)
			RenderingServer.instance_set_visible(child.get_instance(), false)
		if child.get_script() != null and child.get_script().resource_path == "res://addons/godot_level_editor/scripts/presentation/miniature_lighting.gd" and child.is_processing():
			_paused.append(child); child.set_process(false)
		_suppress(child)

func clear() -> void:
	if _world != null and _world.environment == environment:
		_world.environment = _original_environment
		_world.camera_attributes = _original_attributes
	for node in _hidden:
		if is_instance_valid(node): RenderingServer.instance_set_visible(node.get_instance(), node.is_visible_in_tree())
	for node in _paused:
		if is_instance_valid(node): node.set_process(true)
	_hidden.clear(); _paused.clear()
	if is_instance_valid(sun): sun.free()
	sun = null; active_preset = null; environment = null; _world = null

func _exit_tree() -> void:
	clear()
