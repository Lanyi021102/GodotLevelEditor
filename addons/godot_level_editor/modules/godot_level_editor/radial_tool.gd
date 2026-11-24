@tool
extends RefCounted
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_catalog.gd")
const MENU := preload("res://addons/godot_level_editor/modules/godot_level_editor/radial_menu.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const SPAWN := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/spawn_marker.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const BINDING := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_binding.gd")
const METADATA := "godot_level_editor_quick_add"
var plugin: EditorPlugin
var menu: Control
var button: Button
var settings_button: MenuButton
var key_dialog: AcceptDialog
var shortcut := InputEventKey.new()
var recent := PackedStringArray()
var camera: Camera3D
var scene_root: Node
var target_parent: Node
var ghost: Node3D
var active_asset: Dictionary = {}
var placement_valid := false
var placement_transform := Transform3D.IDENTITY
var base_basis := Basis.IDENTITY
var yaw := 0.0
var last_mouse := Vector2.ZERO
var _triangle_cache := {}
var _release_buttons := {}
var _selection_click := false

func setup(editor: EditorPlugin, toolbar: Control) -> void:
	plugin = editor
	var metadata := EditorInterface.get_editor_settings()
	shortcut.keycode = int(metadata.get_project_metadata(METADATA, "shortcut", KEY_QUOTELEFT))
	shortcut.ctrl_pressed = bool(metadata.get_project_metadata(METADATA, "ctrl", false))
	shortcut.alt_pressed = bool(metadata.get_project_metadata(METADATA, "alt", false))
	shortcut.shift_pressed = bool(metadata.get_project_metadata(METADATA, "shift", false))
	shortcut.meta_pressed = bool(metadata.get_project_metadata(METADATA, "meta", false))
	recent = PackedStringArray(metadata.get_project_metadata(METADATA, "recent", PackedStringArray()))
	button = Button.new(); button.text = "呼出轮盘"; button.icon = EditorInterface.get_base_control().get_theme_icon("Add", "EditorIcons"); toolbar.add_child(button)
	button.pressed.connect(func(): toggle_wheel())
	settings_button = MenuButton.new(); settings_button.text = "⌄"; settings_button.tooltip_text = "轮盘设置"; toolbar.add_child(settings_button)
	settings_button.get_popup().add_item("设置呼出键", 0)
	settings_button.get_popup().add_item("恢复默认呼出键", 1)
	settings_button.get_popup().id_pressed.connect(func(id: int):
		if id == 0: _edit_shortcut()
		else: shortcut = InputEventKey.new(); shortcut.keycode = KEY_QUOTELEFT; _save_shortcut())
	key_dialog = AcceptDialog.new(); key_dialog.title = "设置轮盘呼出键"; key_dialog.dialog_text = "按下新的按键组合；Esc 取消。"; key_dialog.get_ok_button().hide()
	EditorInterface.get_base_control().add_child(key_dialog)
	key_dialog.window_input.connect(_capture_shortcut)
	EditorInterface.get_base_control().get_window().focus_exited.connect(cancel)
	_update_tooltip()

func _update_tooltip() -> void:
	button.tooltip_text = "短按 %s 或鼠标侧键呼出／取消；点击分类进入二级轮盘，白盒每页 8 个，滚轮翻页。选择后左键放置，右键 / Esc 结束；R 旋转。" % shortcut.as_text()

func _edit_shortcut() -> void:
	cancel()
	key_dialog.popup_centered(Vector2i(400, 110))

func _capture_shortcut(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE: key_dialog.hide(); return
	if event.keycode in [KEY_CTRL, KEY_ALT, KEY_SHIFT, KEY_META] or event.keycode == KEY_NONE: return
	shortcut = event.duplicate(); shortcut.pressed = false; shortcut.unicode = 0
	_save_shortcut(); key_dialog.hide(); key_dialog.set_input_as_handled()

func _save_shortcut() -> void:
	var metadata := EditorInterface.get_editor_settings()
	metadata.set_project_metadata(METADATA, "shortcut", shortcut.keycode)
	for modifier in ["ctrl", "alt", "shift", "meta"]: metadata.set_project_metadata(METADATA, modifier, shortcut.get(modifier + "_pressed"))
	_update_tooltip()

func is_trigger(event: InputEvent) -> bool:
	if event is InputEventMouseButton: return event.button_index == MOUSE_BUTTON_XBUTTON1
	if event is InputEventKey:
		return not event.echo and event.keycode == shortcut.keycode and (not event.pressed or (event.ctrl_pressed == shortcut.ctrl_pressed and event.alt_pressed == shortcut.alt_pressed and event.shift_pressed == shortcut.shift_pressed and event.meta_pressed == shortcut.meta_pressed))
	return false

func usable_root() -> Node:
	var root := EditorInterface.get_edited_scene_root()
	return root if root != null and root.get_script() in [WORLD, FACTORY.ROOM] else null

func toggle_wheel(view_camera: Camera3D = null, point := Vector2(-1, -1)) -> void:
	if is_instance_valid(menu) and menu.is_open(): cancel(true)
	else: open_wheel(view_camera, point)

func open_wheel(view_camera: Camera3D = null, point := Vector2(-1, -1)) -> void:
	var root := usable_root()
	if root == null:
		plugin.show_message("请先打开关卡或房间场景，再添加物件。")
		return
	if view_camera == null:
		if is_instance_valid(camera) and camera.get_viewport().get_parent().is_visible_in_tree(): view_camera = camera
		else:
			for i in 4:
				var view := EditorInterface.get_editor_viewport_3d(i)
				if view != null and view.get_parent().is_visible_in_tree(): view_camera = view.get_camera_3d(); break
	if view_camera == null: return
	if plugin.measurement != null: plugin.measurement.cancel()
	if "terrain_tool" in plugin and plugin.terrain_tool != null: plugin.terrain_tool.cancel()
	cancel()
	camera = view_camera; scene_root = root; target_parent = root
	if plugin.push_pull.enabled:
		plugin.push_pull.set_enabled(false)
		for push_button in plugin.push_buttons: push_button.set_pressed_no_signal(false)
	# Native 3D input overlays are siblings of the SubViewportContainer. Put the
	# wheel above those overlays so its buttons and search field receive GUI input.
	var container: Control = camera.get_viewport().get_parent()
	while container.get_parent() is Control and container.get_class() != "Node3DEditorViewport": container = container.get_parent()
	if not is_instance_valid(menu):
		menu = MENU.new(); menu.tool = self; container.add_child(menu)
	elif menu.get_parent() != container:
		menu.reparent(container); menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if point.x < 0: point = container.size * 0.5
	last_mouse = point
	menu.open_at(point)

func open_terrain(from_mouse := false) -> void:
	if plugin.terrain_tool == null:
		return
	plugin.terrain_tool.open(camera)
	_selection_click = from_mouse

func begin_asset(asset: Dictionary, consume_selection_click := false) -> bool:
	if plugin.measurement != null: plugin.measurement.cancel()
	if "terrain_tool" in plugin and plugin.terrain_tool != null: plugin.terrain_tool.cancel()
	_clear_ghost()
	if is_instance_valid(menu): menu.close_menu(true)
	if usable_root() == null or asset.is_empty(): return false
	var packed := load(str(asset.path)) as PackedScene
	if packed == null: plugin.show_message("素材加载失败：" + str(asset.path)); return false
	if not is_instance_valid(camera): return false
	var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if not instance is Node3D:
		instance.free(); plugin.show_message("素材的根节点必须是三维节点。"); return false
	ghost = instance
	configure_entity(ghost, asset)
	ghost.name = "QuickAddPreview"
	ghost.process_mode = Node.PROCESS_MODE_DISABLED
	ghost.set_meta("godot_level_editor_radial_preview", true)
	_make_ghost_passive(ghost)
	# The ghost lives beside the editor camera, outside the authored scene tree.
	camera.get_viewport().add_child(ghost)
	base_basis = ghost.basis; yaw = 0
	_make_ghost_passive(ghost)
	if ghost.get_script() == SPAWN:
		var body := MeshInstance3D.new(); var capsule := CapsuleMesh.new(); capsule.radius = 0.28; capsule.height = 1.7
		body.mesh = capsule; body.position.y = 0.85; ghost.add_child(body)
		var arrow := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(0.12, 0.08, 0.8)
		arrow.mesh = box; arrow.position = Vector3(0, 0.08, -0.65); ghost.add_child(arrow)
		_make_ghost_passive(ghost)
	active_asset = asset.duplicate()
	var entity_kind := CATALOG.entity_kind(str(asset.category))
	if not entity_kind.is_empty():
		active_asset.entity_kind = entity_kind
		active_asset.lifetime = asset.get("lifetime", "level")
	_selection_click = consume_selection_click
	scene_root = usable_root()
	target_parent = scene_root
	if scene_root.get_script() == FACTORY.ROOM and asset.category == "常驻 Room":
		plugin.show_message("请在关卡中添加触发区域。"); _clear_ghost(); return false
	_triangle_cache.clear()
	update_preview(camera, last_mouse)
	plugin.update_overlays()
	return true

func _make_ghost_passive(node: Node) -> void:
	if node is WorldEnvironment:
		node.environment = null; node.camera_attributes = null; node.compositor = null
	if node is AudioStreamPlayer3D:
		node.autoplay = false; node.stop()
	if node is CollisionObject3D:
		node.collision_layer = 0; node.collision_mask = 0; node.input_ray_pickable = false
	if node is Light3D: node.visible = false
	if node is Camera3D: node.current = false
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.18, 0.48, 1.0, 0.42)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _make_ghost_passive(child)

func _valid_parent(node: Node) -> bool:
	return is_instance_valid(node) and node == scene_root

func configure_entity(node: Node3D, asset: Dictionary) -> void:
	var kind := CATALOG.entity_kind(str(asset.category))
	if kind.is_empty(): return
	var previous: Resource = node.get_meta(PROFILE.META) if node.has_meta(PROFILE.META) else null
	var config: Resource = previous.duplicate(false) if previous != null else PROFILE.new()
	config.resource_local_to_scene = true
	config.kind = kind; config.lifetime = str(asset.get("lifetime", "level"))
	if previous == null:
		config.model_id = "box" if kind == "mechanism" and asset.get("template", false) else "default"
	if asset.get("template", false):
		node.name = {"npc": "NPC", "mechanism": "Mechanism", "room": "Room"}[kind]
		if node.get("display_name") is String: node.display_name = {"npc": "NPC", "room": "触发区域"}.get(kind, "机关")
		if kind == "room": node.uses_topology = false; node.bounds_size = Vector3.ONE
		if node.get("placeholder_contract") is String: node.placeholder_contract = ""
	node.set_meta(PROFILE.META, config)
	node.set_meta("_edit_group_", true)
	if node.get_node_or_null(NodePath(str(PROFILE.BINDING))) == null:
		var binding := BINDING.new(); binding.name = PROFILE.BINDING; node.add_child(binding)

func pick_surface(view_camera: Camera3D, point: Vector2, root: Node = null, allow_ground_plane := true) -> Dictionary:
	var origin := view_camera.project_ray_origin(point)
	var direction := view_camera.project_ray_normal(point)
	var result := {}
	var queue: Array[Node] = [root if root != null else scene_root]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is Node3D and not node.is_visible_in_tree(): continue
		if node.get_meta("godot_level_editor_room_preview", false): continue
		if node.get_script() == FACTORY.BLOCK and node.is_covered_by_terrain(): continue
		var mesh: Mesh
		var transform := Transform3D.IDENTITY
		var block_geometry: bool = node.get_script() == FACTORY.BLOCK and (allow_ground_plane or node.visual_scene == null)
		if block_geometry:
			mesh = node.geometry(); transform = node.global_transform
		elif node is MeshInstance3D:
			mesh = node.mesh; transform = node.global_transform
		for child in node.get_children():
			if not block_geometry or not child.get_meta("godot_level_editor_generated", false): queue.append(child)
		if mesh == null or is_zero_approx(transform.basis.determinant()): continue
		var inverse := transform.affine_inverse()
		var local_origin := inverse * origin
		var local_ray := inverse.basis * direction
		if mesh.get_aabb().intersects_ray(local_origin, local_ray) == null: continue
		var triangles: TriangleMesh
		if allow_ground_plane:
			# Placement keeps one surface cache for the lifetime of its ghost.
			var key := mesh.get_instance_id()
			if not _triangle_cache.has(key): _triangle_cache[key] = mesh.generate_triangle_mesh()
			triangles = _triangle_cache[key]
		else:
			# A measurement can stay open across Inspector edits to the same Mesh.
			triangles = mesh.generate_triangle_mesh()
		if triangles == null: continue
		var hit := triangles.intersect_ray(local_origin, local_ray)
		if hit.is_empty(): continue
		var at: Vector3 = transform * hit.position
		var distance := origin.distance_to(at)
		if distance > 10000 or (not result.is_empty() and distance >= result.distance): continue
		result = {"position": at, "normal": (transform.basis.inverse().transposed() * hit.normal).normalized(), "distance": distance}
	if result.is_empty() and allow_ground_plane:
		var at: Variant = Plane(Vector3.UP, 0).intersects_ray(origin, direction)
		if at is Vector3 and origin.distance_to(at) < 10000: result = {"position": at, "normal": Vector3.UP, "distance": origin.distance_to(at)}
	return result

func update_preview(view_camera: Camera3D, point: Vector2) -> void:
	if not is_instance_valid(ghost): return
	camera = view_camera; last_mouse = point
	var hit := pick_surface(camera, point)
	placement_valid = not hit.is_empty() and _valid_parent(target_parent)
	ghost.visible = placement_valid
	if not placement_valid: plugin.update_overlays(); return
	var basis := Basis(Vector3.UP, yaw) * base_basis
	var position: Vector3 = hit.position.snapped(Vector3.ONE * plugin.edit_step)
	if ghost.get_script() == FACTORY.BLOCK:
		# Support the entire box along the hit normal, keeping a wall hit outside it.
		var normal: Vector3 = hit.normal
		if normal.dot(camera.project_ray_normal(point)) > 0: normal = -normal
		var half: Vector3 = ghost.size * 0.5
		position += normal * (absf(normal.dot(basis.x)) * half.x + absf(normal.dot(basis.y)) * half.y + absf(normal.dot(basis.z)) * half.z)
		position = position.snapped(Vector3.ONE * plugin.edit_step)
	placement_transform = Transform3D(basis, position)
	ghost.global_transform = placement_transform
	plugin.update_overlays()

func place() -> Node3D:
	if not placement_valid or not is_instance_valid(ghost) or usable_root() != scene_root or not _valid_parent(target_parent): return null
	var existing: Node3D
	if active_asset.category == "玩家出生点":
		if scene_root.get_script() == SPAWN and scene_root.role == "player": existing = scene_root
		for node in scene_root.find_children("*", "Marker3D", true, false):
			if node.get_script() == SPAWN and node.role == "player": existing = node; break
	var placed: Node3D
	if existing != null:
		# An uneditable prefab child must not be silently overridden.
		if existing.owner != scene_root and existing != scene_root and not scene_root.is_editable_instance(existing.owner):
			plugin.show_message("出生点位于房间实例内，请打开源房间或开启可编辑子节点。"); return null
		var history := plugin.get_undo_redo()
		history.create_action("移动玩家出生点", UndoRedo.MERGE_DISABLE, scene_root)
		history.add_do_property(existing, "global_transform", placement_transform)
		history.add_undo_property(existing, "global_transform", existing.global_transform)
		history.commit_action()
		placed = existing
	else:
		placed = placement_instance(active_asset, placement_transform)
		if placed == null: return null
		plugin._add_undoable(target_parent, placed, scene_root, "添加 " + str(active_asset.title))
	remember_asset(active_asset)
	plugin.show_message("已放置：" + str(active_asset.title), false)
	_triangle_cache.clear()
	if existing != null or active_asset.category == "玩家出生点": cancel()
	return placed

func placement_instance(asset: Dictionary, world_transform: Transform3D) -> Node3D:
	var packed := load(str(asset.path)) as PackedScene
	if packed == null: return null
	var placed := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	if placed == null: return null
	_fresh_identity(placed)
	configure_entity(placed, asset)
	placed.transform = (scene_root as Node3D).global_transform.affine_inverse() * world_transform
	return placed

func remember_asset(asset: Dictionary) -> void:
	var key := CATALOG.recent_key(asset)
	recent.erase(key); recent.insert(0, key); recent.resize(mini(recent.size(), 12))
	EditorInterface.get_editor_settings().set_project_metadata(METADATA, "recent", recent)

func _fresh_identity(node: Node3D) -> void:
	# Only replace the instance scope; authored child IDs and graph references stay intact.
	for property in ["room_id", "object_id", "instance_id", "enemy_instance_id"]:
		if node.get(property) is String: node.set(property, GRAPH.fresh_id("room" if property == "room_id" else "object"))

func input(view_camera: Camera3D, event: InputEvent) -> bool:
	# Hiding a menu on mouse-down can forward that same press to the 3D view.
	# Selecting an asset must never also commit a placement.
	if _selection_click and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed: _selection_click = false
		return true
	if event is InputEventMouseButton and not event.pressed and _release_buttons.has(event.button_index):
		_release_buttons.erase(event.button_index); return true
	if event is InputEventMouseMotion and active_asset.is_empty(): camera = view_camera; last_mouse = event.position
	if is_trigger(event) and event.is_pressed():
		toggle_wheel(view_camera, event.position if event is InputEventMouseButton else last_mouse)
		return usable_root() != null
	if is_trigger(event): return usable_root() != null
	if is_instance_valid(menu) and menu.is_open(): return true
	if active_asset.is_empty(): return false
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE: cancel(); return true
		if event.keycode == KEY_R:
			yaw += deg_to_rad(-15 if event.shift_pressed else 15); update_preview(view_camera, last_mouse); return true
	if event is InputEventMouseMotion:
		update_preview(view_camera, event.position)
		return (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) == 0 and not event.alt_pressed
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed: cancel(); _release_buttons[MOUSE_BUTTON_RIGHT] = true
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.alt_pressed: return false
			if event.pressed:
				update_preview(view_camera, event.position); place(); _release_buttons[MOUSE_BUTTON_LEFT] = true
			return true
	return false

func draw(control: Control) -> void:
	if active_asset.is_empty() or not is_instance_valid(camera): return
	var view_owner: Node = camera.get_viewport().get_parent()
	while view_owner != null and view_owner.get_class() != "Node3DEditorViewport": view_owner = view_owner.get_parent()
	if view_owner == null or not view_owner.is_ancestor_of(control): return
	var text := str(active_asset.title) + " · " + (str(target_parent.name) if is_instance_valid(target_parent) else "")
	if not placement_valid: text += " · 无可放置表面"
	elif active_asset.category == "玩家出生点" and not scene_root.find_children("*", "Marker3D", true, false).is_empty(): text = "移动玩家出生点 · " + str(scene_root.name)
	var font := control.get_theme_default_font()
	var font_size := control.get_theme_default_font_size()
	var width := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 24, control.size.x - 24)
	var rect := Rect2(Vector2(12, control.size.y - 42), Vector2(width, 30))
	control.draw_style_box(preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd").box(Color(0.08, 0.13, 0.23, 0.92), 4, 8), rect)
	control.draw_string(font, rect.position + Vector2(12, 21), text, HORIZONTAL_ALIGNMENT_LEFT, width - 20, font_size, Color.WHITE)

func process() -> void:
	# Upgrade an already open editor without reloading or discarding its scenes.
	if is_instance_valid(menu) and menu.get_meta("quick_add_ui_revision", 0) != MENU.UI_REVISION:
		var reopen: bool = menu.visible
		var point: Vector2 = menu.wheel_center
		var category: int = menu.category
		menu.free(); menu = null
		if reopen and usable_root() != null and is_instance_valid(camera): open_wheel(camera, point); menu.select_category(category)
	button.disabled = usable_root() == null or EditorInterface.is_playing_scene()
	if not active_asset.is_empty() or (is_instance_valid(menu) and menu.visible):
		if usable_root() != scene_root or EditorInterface.is_playing_scene() or not is_instance_valid(camera) or not camera.get_viewport().get_parent().is_visible_in_tree(): cancel()

func _clear_ghost() -> void:
	if is_instance_valid(ghost): ghost.free()
	ghost = null; active_asset = {}; placement_valid = false; _selection_click = false; _triangle_cache.clear()

func cancel(animated := false) -> void:
	if is_instance_valid(menu): menu.close_menu(animated)
	_clear_ghost()
	if is_instance_valid(plugin): plugin.update_overlays()

func dispose() -> void:
	cancel()
	var window := EditorInterface.get_base_control().get_window()
	if window.focus_exited.is_connected(cancel): window.focus_exited.disconnect(cancel)
	if is_instance_valid(menu): menu.free()
	if is_instance_valid(key_dialog): key_dialog.queue_free()
