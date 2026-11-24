@tool
extends SubViewport
## All presets light the same private whitebox. Only one thumbnail is rendered at a time.
signal thumbnail_ready(path: String, texture: Texture2D)
const RUNTIME := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/runtime.gd")
var _runtime: Node3D
var _cache := {}
var _pending := {}
var _active := ""
var _active_digest := ""

func _ready() -> void:
	own_world_3d = true
	size = Vector2i(192, 108)
	gui_disable_input = true
	render_target_update_mode = UPDATE_DISABLED
	set_process(false)
	get_parent().visibility_changed.connect(_visibility_changed)
	var stage := Node3D.new()
	add_child(stage)
	_box(stage, Vector3(100, 0.25, 100), Vector3(0, -0.125, -28))
	_box(stage, Vector3(0.55, 3.5, 5), Vector3(-2.6, 1.75, -1))
	_box(stage, Vector3(4.9, 3.5, 0.55), Vector3(-0.4, 1.75, -3.4))
	for step in 5:
		var height := (step + 1) * 0.32
		_box(stage, Vector3(3.4, height, 0.6), Vector3(0.25, height * 0.5, 1.4 - step * 0.6))
	_box(stage, Vector3(4, 6, 4), Vector3(5, 3, -24))
	_box(stage, Vector3(7, 9, 5), Vector3(-9, 4.5, -42))
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(5, 3, 8)
	camera.look_at(Vector3(0, 1.9, -1), Vector3.UP)
	camera.fov = 46
	camera.current = true
	_runtime = RUNTIME.new()
	stage.add_child(_runtime)

func _box(stage: Node, extent: Vector3, center: Vector3) -> void:
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = extent
	block.mesh = mesh
	block.position = center
	stage.add_child(block)

func request(preset: Resource) -> Texture2D:
	var path := preset.resource_path
	var digest := FileAccess.get_md5(path)
	for dependency in [preset.hdri, preset.base_environment]:
		if dependency != null and FileAccess.file_exists(dependency.resource_path):
			digest += str(FileAccess.get_modified_time(dependency.resource_path))
	var cached: Dictionary = _cache.get(path, {})
	if cached.get("digest") == digest: return cached.texture
	if path != _active or digest != _active_digest:
		_pending[path] = {"preset": preset, "digest": digest}
	_visibility_changed()
	return null

func _visibility_changed() -> void:
	set_process(not _active.is_empty() or (not _pending.is_empty() and get_parent().is_visible_in_tree()))

func _process(_delta: float) -> void:
	if not _active.is_empty():
		# An unfocused editor may suspend ordinary draws.
		RenderingServer.force_draw(false)
		var frame := get_texture().get_image()
		if frame != null and not frame.is_empty() and not _pending.has(_active):
			var texture := ImageTexture.create_from_image(frame)
			_cache[_active] = {"digest": _active_digest, "texture": texture}
			thumbnail_ready.emit(_active, texture)
		_active = ""
		render_target_update_mode = UPDATE_DISABLED
	if _pending.is_empty():
		set_process(false)
		return
	if not get_parent().is_visible_in_tree():
		set_process(false)
		return
	var path: String = _pending.keys()[0]
	var job: Dictionary = _pending[path]
	_pending.erase(path)
	if _runtime.apply(job.preset).is_empty():
		_active = path
		_active_digest = job.digest
		render_target_update_mode = UPDATE_ONCE
