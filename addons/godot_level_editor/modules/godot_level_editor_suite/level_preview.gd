@tool
extends Node
## Renders saved levels in a private world; never moves the editor camera.
signal preview_updated(level_id: String, scene_path: String, preview_path: String, texture: Texture2D)
signal preview_failed(scene_path: String, reason: String)
signal idle
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const IMAGE_SIZE := Vector2i(1024, 576)
const VIEW_DIRECTION := Vector3(1.1, 1.0, 1.4)
var workbook_path := LEVELS.PATH
var output_directory := "res://content/resources/level_previews"
var _pending: Dictionary = {}
var _busy := false
var _closed := false
var _viewport: SubViewport

func request(scene_path: String) -> void:
	# A dummy renderer must never replace a good PNG with an empty image.
	if _closed or DisplayServer.get_name() == "headless": return
	scene_path = scene_path.simplify_path()
	if not scene_path.begins_with("res://") or scene_path.begins_with("res://addons/"): return
	var result := LEVELS.load_book(workbook_path)
	if result.catalog == null:
		_fail(scene_path, "; ".join(result.errors)); return
	var row := _row_for_scene(result.catalog, scene_path)
	if row.is_empty(): return
	_pending[scene_path] = str(row.level_id)
	if not _busy:
		_busy = true
		_drain.call_deferred()

func is_busy() -> bool:
	return _busy

func dispose() -> void:
	_closed = true
	_pending.clear()
	if is_instance_valid(_viewport): _viewport.queue_free()

func _drain() -> void:
	# Merge repeated saves in the same editor frame.
	await get_tree().process_frame
	while not _closed and not _pending.is_empty():
		var scene_path: String = _pending.keys()[0]
		var id: String = _pending[scene_path]
		_pending.erase(scene_path)
		var current := LEVELS.load_book(workbook_path)
		if current.catalog != null and _row_for_scene(current.catalog, scene_path).is_empty(): continue
		var result: Dictionary = await _capture(scene_path)
		if _closed: break
		# A newer save arrived while rendering: publish only the latest state.
		if _pending.has(scene_path): continue
		if not result.get("error", "").is_empty():
			_fail(scene_path, result.error); continue
		_publish(id, scene_path, result.image)
	_busy = false
	if not _closed: idle.emit()

func _capture(scene_path: String) -> Dictionary:
	var packed := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null: return {"error": "无法读取已保存的关卡场景"}
	var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if not instance is Node3D:
		if instance != null: instance.free()
		return {"error": "关卡场景根节点必须为三维节点"}
	var world := instance as Node3D
	_prepare(world)
	_viewport = SubViewport.new()
	_viewport.size = IMAGE_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.gui_disable_input = true
	add_child(_viewport)
	_viewport.add_child(world)
	# Tool nodes build their meshes and imported models in deferred calls.
	for i in 5:
		await get_tree().process_frame
		if _closed: return {"error": "预览已取消"}
	_prepare(world)
	var bounds := geometry_bounds(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("e9edf2")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	_viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-54, -35, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	_viewport.add_child(light)
	var camera := Camera3D.new()
	_viewport.add_child(camera)
	frame_camera(camera, bounds)
	camera.current = true
	for i in 4:
		await get_tree().process_frame
		if _closed: return {"error": "预览已取消"}
	# The editor can suspend redraws while idle or unfocused. Explicitly draw the
	# private viewport before readback instead of awaiting a possibly absent frame.
	RenderingServer.force_draw(false)
	var image := _viewport.get_texture().get_image()
	_viewport.queue_free()
	_viewport = null
	if image == null or image.is_empty(): return {"error": "未取得关卡预览图像"}
	return {"image": image}

static func _prepare(node: Node) -> void:
	# All changes below affect only the disposable instance, including generated nodes.
	if node.get_script() == WORLD: node.sky_preset = null
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Camera3D: node.current = false
	if node is CanvasItem or node is CanvasLayer: node.visible = false
	if node is Node3D and (node.get_meta("godot_level_editor_room_preview", false) or node is Label3D): node.hide()
	for child in node.get_children():
		var script: Script = child.get_script()
		if child is Light3D or child is WorldEnvironment or child is FogVolume or (script != null and script.resource_path == "res://addons/godot_level_editor/scripts/presentation/miniature_lighting.gd"):
			child.free()
		else: _prepare(child)

static func geometry_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "Node3D", true, false))
	for node in nodes:
		if not (node is MeshInstance3D or node is MultiMeshInstance3D or node is CSGShape3D) or not node.is_visible_in_tree(): continue
		var local: AABB = node.get_aabb()
		if not local.position.is_finite() or not local.size.is_finite() or local.size.is_zero_approx(): continue
		var box: AABB = node.global_transform * local
		bounds = bounds.merge(box) if found else box
		found = true
	return bounds if found else AABB(Vector3(-5, -0.5, -5), Vector3(10, 1, 10))

static func frame_camera(camera: Camera3D, bounds: AABB) -> void:
	var center := bounds.get_center()
	var distance := maxf(10, bounds.size.length() * 2)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = distance + maxf(20, bounds.size.length() * 2)
	camera.position = center + VIEW_DIRECTION.normalized() * distance
	camera.look_at(center, Vector3.UP)
	var inverse := camera.global_transform.affine_inverse()
	var extent := Vector2.ZERO
	for i in 8:
		var projected: Vector3 = inverse * bounds.get_endpoint(i)
		extent.x = maxf(extent.x, absf(projected.x))
		extent.y = maxf(extent.y, absf(projected.y))
	var aspect := float(IMAGE_SIZE.x) / IMAGE_SIZE.y
	camera.size = maxf(1, maxf(extent.y, extent.x / aspect) * 2 * 1.14)

func _publish(id: String, scene_path: String, image: Image) -> void:
	# Re-read after rendering so unrelated metadata edits and deletions are respected.
	var result := LEVELS.load_book(workbook_path)
	if result.catalog == null:
		_fail(scene_path, "; ".join(result.errors)); return
	var row: Dictionary = result.catalog.by_id(id)
	if row.is_empty() or str(row.scene_path) != scene_path: return
	var target := output_directory.path_join(id + ".png")
	var temporary := output_directory.path_join("." + id + ".tmp.png")
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	if error == OK: error = image.save_png(ProjectSettings.globalize_path(temporary))
	if error == OK: error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(target))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		_fail(scene_path, "无法保存关卡预览：" + error_string(error)); return
	if str(row.preview_path) != target:
		row.preview_path = target
		var errors: PackedStringArray = result.catalog.save_book(workbook_path)
		if not errors.is_empty():
			_fail(scene_path, "; ".join(errors)); return
	EditorInterface.get_resource_filesystem().update_file(target)
	preview_updated.emit(id, scene_path, target, ImageTexture.create_from_image(image))

static func _row_for_scene(catalog: Resource, scene_path: String) -> Dictionary:
	for row in catalog.levels:
		if str(row.scene_path) == scene_path: return row
	return {}

func _fail(scene_path: String, reason: String) -> void:
	preview_failed.emit(scene_path, reason)
	push_warning("关卡已保存，缩略图更新失败（" + scene_path + "）：" + reason)
