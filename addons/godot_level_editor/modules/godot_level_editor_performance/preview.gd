@tool
extends SubViewportContainer

const SAMPLER := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sampler.gd")
var viewport: SubViewport
var _duplicate: Node3D
var _camera: Camera3D
var _sampler: RefCounted

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = SIZE_EXPAND_FILL
	custom_minimum_size.y = 104
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	hide()

func start(world: Node3D, data: Resource, editor_camera: Camera3D) -> void:
	if not is_instance_valid(_duplicate):
		_duplicate = world.duplicate(0) as Node3D
		_prepare(_duplicate)
		_duplicate.transform = world.global_transform
		viewport.add_child(_duplicate)
		_camera = Camera3D.new()
		viewport.add_child(_camera)
		if _duplicate.find_children("*", "WorldEnvironment", true, false).is_empty():
			var environment := Environment.new()
			environment.background_mode = Environment.BG_COLOR
			environment.background_color = Color("41516a")
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color("dae5f7")
			environment.ambient_light_energy = 0.8
			_camera.environment = environment
		_sampler = SAMPLER.new()
		_sampler.fallback_pose = editor_camera.global_transform if editor_camera != null else world.global_transform * Transform3D(Basis.from_euler(Vector3(-0.45, 0, 0)), Vector3(0, 5, 8))
		if editor_camera != null:
			_sampler.fallback_lens = {"projection": editor_camera.projection, "fov": editor_camera.fov, "size": editor_camera.size, "keep_aspect": editor_camera.keep_aspect}
	_sampler.bind(data, world, _duplicate, _camera)
	show()

func sample(time: float) -> void:
	if _sampler != null: _sampler.sample(time, true)

func stop() -> void:
	if is_instance_valid(_duplicate):
		viewport.remove_child(_duplicate)
		_duplicate.queue_free()
	if is_instance_valid(_camera):
		viewport.remove_child(_camera)
		_camera.queue_free()
	_duplicate = null
	_camera = null
	_sampler = null
	hide()

func _prepare(node: Node) -> void:
	# Duplicate with no scene instantiation, scripts, groups or signal connections.
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is AnimationPlayer:
		node.autoplay = ""
		node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if node is AnimationTree: node.active = false
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.autoplay = false
	if node is Camera3D: node.current = false
	for child in node.get_children():
		if child.get_meta("godot_level_editor_room_preview", false):
			child.free()
		else:
			_prepare(child)
