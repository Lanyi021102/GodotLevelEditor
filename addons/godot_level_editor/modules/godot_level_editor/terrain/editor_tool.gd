@tool
extends RefCounted

const TERRAIN := preload("terrain.gd")
const LAYOUT := preload("layout.gd")
const VIEW := preload("editor_view.gd")
const STYLE := preload("../../godot_level_editor_suite/editor_style.gd")
const SPAWN := preload("../runtime/spawn_marker.gd")
const MIN_EDGE := 2.0

enum Mode { SELECT, PEAK, RIVER, PLATEAU, PRESET }
var plugin: EditorPlugin
var button: Button
var actions: HBoxContainer
var options: HBoxContainer
var mode_buttons: Array[Button] = []
var top_button: Button
var profile: OptionButton
var fields: Array[LineEdit] = []
var field_labels: Array[Label] = []
var field_specs: Array[Array] = []
var finish_button: Button
var remove_button: Button
var duplicate_button: Button
var camera: Camera3D
var terrain: Node3D
var ghost: Node3D
var mode := Mode.SELECT
var active := false
var hover: Variant = null
var selected := 0
var selected_ridge := ""
var river_points := PackedVector2Array()
var rectangle_start: Variant = null
var drag := {}
var defaults := {"height": 12.0, "radius": 25.0, "width": 5.0, "depth": 1.4, "plateau_height": 9.0, "shoulder": 14.0, "profile": 0}
var preset_index := 0
var view_states := {}
var draft_dirty := false
var preview_wait := 0.0
var saved_layout: Dictionary = {}

func setup(editor: EditorPlugin, toolbar: HBoxContainer) -> void:
	plugin = editor
	button = _button(toolbar, "地形", func():
		if active: cancel()
		else: open())
	button.toggle_mode = true
	button.tooltip_text = "在当前关卡点山峰、画河流或拖出高原。"
	actions = HBoxContainer.new()
	toolbar.add_child(actions)
	for i in 4:
		var new_button := _button(actions, ["选择", "山峰", "河流", "高原"][i], set_mode.bind(i))
		new_button.toggle_mode = true
		mode_buttons.append(new_button)
	var presets := MenuButton.new()
	presets.text = "预设"
	for index in 2:
		presets.get_popup().add_item(["双峰山口", "高原河谷"][index], index)
	presets.get_popup().id_pressed.connect(_choose_preset)
	actions.add_child(presets)
	top_button = _button(actions, "俯视", _toggle_view)
	options = HBoxContainer.new()
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, options)
	profile = OptionButton.new()
	profile.add_item("圆丘")
	profile.add_item("陡峰")
	profile.item_selected.connect(_set_profile)
	options.add_child(profile)
	for i in 2:
		var label := Label.new()
		options.add_child(label)
		field_labels.append(label)
		var field := LineEdit.new()
		field.custom_minimum_size.x = 58 * EditorInterface.get_editor_scale()
		field.select_all_on_focus = true
		field.text_submitted.connect(func(_value: String): field.release_focus())
		field.focus_exited.connect(_apply_field.bind(i))
		options.add_child(field)
		fields.append(field)
	finish_button = _button(options, "完成河流", _finish_river)
	duplicate_button = _button(options, "复制", _duplicate_feature)
	remove_button = _button(options, "删除", _delete_selected)
	_refresh()

func _button(container: Control, title: String, handler: Callable) -> Button:
	var result := Button.new()
	result.text = title
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(handler)
	container.add_child(result)
	return result

func root() -> Node3D:
	return EditorInterface.get_edited_scene_root() as Node3D

func open(view_camera: Camera3D = null) -> void:
	if root() == null or EditorInterface.is_playing_scene():
		_refresh()
		return
	if active:
		return
	plugin.radial_tool.cancel()
	plugin.measurement.cancel()
	plugin.push_pull.set_enabled(false)
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	camera = view_camera if view_camera != null else viewport.get_camera_3d() if viewport != null else null
	_sync_terrain()
	active = true
	mode = Mode.SELECT if terrain != null else Mode.PEAK
	if is_instance_valid(camera):
		_set_top(true)
	_refresh()

func cancel() -> void:
	if not active:
		return
	_clear_draft()
	active = false
	view_states.clear()
	selected = 0
	selected_ridge = ""
	camera = null
	terrain = null
	_refresh()

func dispose() -> void:
	cancel()
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, options)
	options.queue_free()

func _sync_terrain() -> void:
	if is_instance_valid(terrain) and terrain.is_inside_tree() and terrain.get_parent() == root():
		return
	terrain = null
	if root() != null:
		for child in root().get_children():
			if child.get_script() == TERRAIN:
				terrain = child
				break

func process(delta: float) -> void:
	button.disabled = root() == null or EditorInterface.is_playing_scene()
	if button.disabled:
		cancel()
	if not active:
		return
	var previous := terrain
	_sync_terrain()
	if previous != terrain:
		selected = 0
		selected_ridge = ""
		_refresh()
	elif terrain != null and ((selected > 0 and LAYOUT.find(terrain.layout, selected).is_empty()) or
			(not selected_ridge.is_empty() and _current_ridge().is_empty())) and drag.is_empty():
		selected = 0
		selected_ridge = ""
		_refresh()
	preview_wait -= delta
	if is_instance_valid(camera):
		top_button.text = "透视" if VIEW.is_top(camera) else "俯视"
	if terrain != null and terrain.layout != saved_layout and drag.is_empty():
		_refresh()
	if draft_dirty and preview_wait <= 0.0:
		draft_dirty = false
		preview_wait = 0.065
		_update_preview()

func _toggle_view() -> void:
	if is_instance_valid(camera):
		_set_top(not VIEW.is_top(camera))
	_refresh()

func _set_top(value: bool) -> void:
	if not is_instance_valid(camera):
		return
	var id := camera.get_instance_id()
	if value and not VIEW.is_top(camera):
		view_states[id] = VIEW.snapshot(camera)
		VIEW.change(camera, true)
	elif not value:
		if not VIEW.restore(camera, view_states.get(id, {})):
			VIEW.change(camera, false)
		view_states.erase(id)

func set_mode(value: int) -> void:
	_clear_draft()
	mode = value as Mode
	selected = 0
	selected_ridge = ""
	_refresh()

func _choose_preset(index: int) -> void:
	preset_index = index
	set_mode(Mode.PRESET)

func _state() -> Dictionary:
	return terrain.layout.duplicate(true) if is_instance_valid(terrain) else LAYOUT.empty()

func _basis() -> Transform3D:
	return terrain.global_transform if is_instance_valid(terrain) and terrain.is_inside_tree() else root().global_transform

func _cursor(point: Vector2, elevation := 0.0) -> Variant:
	var inverse := _basis().affine_inverse()
	var at: Variant = Plane(Vector3.UP, elevation).intersects_ray(inverse * camera.project_ray_origin(point), inverse.basis * camera.project_ray_normal(point))
	if at == null:
		return null
	return Vector2(at.x, at.z).snapped(Vector2.ONE * maxf(0.05, plugin.edit_step))

func _peak(at: Vector2) -> Dictionary:
	return LAYOUT.peak(at, defaults.height, defaults.radius, defaults.profile)

func _clear_draft() -> void:
	hover = null
	river_points.clear()
	rectangle_start = null
	drag.clear()
	draft_dirty = false
	_clear_preview()

func _clear_preview() -> void:
	if is_instance_valid(ghost):
		ghost.free()
		ghost = null
	if is_instance_valid(terrain) and terrain.is_inside_tree():
		terrain.restore_preview()

func _river_add(points: PackedVector2Array, at: Vector2) -> void:
	if points.is_empty() or points[-1].distance_to(at) >= 0.5:
		points.append(at)

func _add_preset(state: Dictionary, at: Vector2) -> void:
	for feature: Dictionary in LAYOUT.preset(preset_index, at).features:
		LAYOUT.add(state, feature)

func _update_preview() -> void:
	if not active or not is_instance_valid(camera):
		return
	var draft := _state()
	if not drag.is_empty():
		draft = drag.layout
	elif mode == Mode.PEAK and hover != null and _can_place_peak(draft, hover):
		LAYOUT.add(draft, _peak(hover))
	elif mode == Mode.RIVER and not river_points.is_empty():
		var points := river_points.duplicate()
		if hover != null:
			_river_add(points, hover)
		if points.size() >= 2:
			LAYOUT.add(draft, LAYOUT.river(points, defaults.width, defaults.depth))
	elif mode == Mode.PLATEAU and rectangle_start != null and hover != null and _large_enough(rectangle_start, hover):
		LAYOUT.add(draft, LAYOUT.plateau(rectangle_start, hover, defaults.plateau_height, defaults.shoulder))
	elif mode == Mode.PRESET and hover != null:
		_add_preset(draft, hover)
	if not draft.is_empty() and draft != _state():
		if is_instance_valid(terrain):
			terrain.preview_layout(draft)
		else:
			if not is_instance_valid(ghost):
				ghost = TERRAIN.new()
				ghost.preview_only = true
				ghost.layout = draft
				camera.get_viewport().add_child(ghost)
				ghost.global_transform = _basis().translated(Vector3(0, 0.025, 0))
			else:
				ghost.preview_layout(draft)
	else:
		_clear_preview()
	plugin.update_overlays()

func _commit(state: Dictionary, title: String) -> void:
	_clear_preview()
	var scene := root()
	if scene == null:
		return
	if terrain == null:
		terrain = TERRAIN.new()
		terrain.name = "Terrain"
		terrain.layout = state
		plugin._add_undoable(scene, terrain, scene, title)
	else:
		if terrain.layout == state:
			return
		var history := plugin.get_undo_redo()
		history.create_action(title, UndoRedo.MERGE_DISABLE, scene)
		history.add_do_method(terrain, "apply_layout", state)
		history.add_undo_method(terrain, "apply_layout", terrain.layout)
		history.commit_action()
	_refresh()

func _finish_river() -> void:
	if mode != Mode.RIVER or river_points.size() < 2:
		return
	var state := _state()
	selected = LAYOUT.add(state, LAYOUT.river(river_points.duplicate(), defaults.width, defaults.depth))
	_clear_draft()
	mode = Mode.SELECT
	_commit(state, "添加河流")

func _delete_selected() -> void:
	var state := _state()
	if not selected_ridge.is_empty():
		state.ridges[selected_ridge] = {"disabled": true}
		selected_ridge = ""
		_commit(state, "断开山脊")
	elif selected > 0:
		LAYOUT.remove(state, selected)
		selected = 0
		_commit(state, "删除地形要素")

func _duplicate_feature() -> void:
	var state := _state()
	var feature := LAYOUT.find(state, selected).duplicate(true)
	if feature.is_empty():
		return
	var offset := Vector2(6, 6)
	if feature.has("center"):
		while not _can_place_peak(state, feature.center + offset):
			offset += Vector2(2, 2)
		feature.center += offset
	else:
		var points: PackedVector2Array = feature.points
		for i in points.size():
			points[i] += offset
		feature.points = points
	selected = LAYOUT.add(state, feature)
	_commit(state, "复制地形要素")

func _large_enough(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) >= MIN_EDGE and absf(a.y - b.y) >= MIN_EDGE

func _can_place_peak(state: Dictionary, at: Vector2, ignore := 0) -> bool:
	return not state.features.any(func(feature: Dictionary) -> bool:
		return feature.kind == "peak" and feature.id != ignore and at.distance_squared_to(feature.center) < 1.0)

func input(view_camera: Camera3D, event: InputEvent) -> bool:
	if not active:
		return false
	if camera != view_camera:
		_clear_preview()
		camera = view_camera
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if not drag.is_empty() or rectangle_start != null or not river_points.is_empty():
				_clear_draft()
				_refresh()
			elif mode != Mode.SELECT:
				set_mode(Mode.SELECT)
			else:
				cancel()
			return true
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and mode == Mode.RIVER and river_points.size() >= 2:
			_finish_river()
			return true
		if event.keycode in [KEY_DELETE, KEY_BACKSPACE] and (selected > 0 or not selected_ridge.is_empty()):
			_delete_selected()
			return true
	if event is InputEventMouseMotion and not event.alt_pressed and not event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
		hover = _cursor(event.position)
		if not drag.is_empty():
			_move_drag(event.position)
		draft_dirty = true
		plugin.update_overlays()
		return not drag.is_empty() or rectangle_start != null
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.alt_pressed:
		return false
	if not event.pressed:
		if rectangle_start != null:
			hover = _cursor(event.position)
		if not drag.is_empty():
			_move_drag(event.position)
		_release()
		return true
	hover = _cursor(event.position)
	match mode:
		Mode.SELECT:
			_press_handle(event.position, event.double_click)
		Mode.PEAK, Mode.PRESET:
			if hover != null:
				var state := _state()
				if mode == Mode.PEAK:
					if _can_place_peak(state, hover):
						LAYOUT.add(state, _peak(hover))
						_commit(state, "添加山峰")
					else:
						plugin.show_message("两个山峰至少间隔 1 米。")
				else:
					_add_preset(state, hover)
					mode = Mode.SELECT
					_commit(state, "添加地形预设")
		Mode.RIVER:
			if hover != null:
				_river_add(river_points, hover)
				draft_dirty = true
		Mode.PLATEAU:
			rectangle_start = hover
	_refresh()
	return true

func _release() -> void:
	if not drag.is_empty():
		var state: Dictionary = drag.layout
		drag.clear()
		draft_dirty = false
		_commit(state, "调整地形")
	elif rectangle_start != null:
		if hover != null and _large_enough(rectangle_start, hover):
			var state := _state()
			selected = LAYOUT.add(state, LAYOUT.plateau(rectangle_start, hover, defaults.plateau_height, defaults.shoulder))
			mode = Mode.SELECT
			_commit(state, "添加高原")
		rectangle_start = null
		draft_dirty = true

func _world(at: Vector2, elevation: float) -> Vector3:
	return _basis() * Vector3(at.x, elevation, at.y)

func _current_surface() -> RefCounted:
	if is_instance_valid(ghost): return ghost.surface
	if is_instance_valid(terrain) and terrain.is_inside_tree(): return terrain.surface
	return null

func _current_ridge() -> Dictionary:
	var surface := _current_surface()
	if surface != null:
		for ridge: Dictionary in surface.ridges:
			if ridge.key == selected_ridge:
				return ridge
	return {}

func _press_handle(at: Vector2, double_click: bool) -> void:
	if not is_instance_valid(terrain):
		return
	var state := _state()
	var surface := _current_surface()
	var handles := VIEW.handles(camera, _basis(), surface, state, selected)
	var closest := {}
	var distance := 14.0 * EditorInterface.get_editor_scale()
	for handle: Dictionary in handles:
		var current: float = handle.screen.distance_to(at)
		if current < distance:
			distance = current
			closest = handle
	if closest.is_empty():
		closest = VIEW.ridge_handle_at(camera, _basis(), surface, handles, at)
	if closest.is_empty():
		var feature := LAYOUT.find(state, selected)
		if feature.get("kind") == "plateau":
			var index := VIEW.edge_at(camera, _basis(), surface, feature.points, at)
			if index >= 0:
				var point: Variant = _cursor(at, feature.height)
				if double_click and point != null:
					var points: PackedVector2Array = feature.points
					point = Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()])
					points.insert(index + 1, point)
					if LAYOUT.polygon_is_valid(points):
						feature.points = points
						_commit(state, "添加高原边界点")
				return
		selected = 0
		selected_ridge = ""
		return
	selected = closest.id
	selected_ridge = closest.get("ridge", "")
	var anchor: Variant = _cursor(at, closest.y)
	drag = {"start": at, "anchor": anchor, "handle": closest, "layout": state.duplicate(true), "before": state}

func _move_drag(at: Vector2) -> void:
	var handle: Dictionary = drag.handle
	if at.distance_to(drag.start) < 1.5:
		drag.layout = drag.before.duplicate(true)
		return
	var state: Dictionary = drag.before.duplicate(true)
	var feature := LAYOUT.find(state, handle.id)
	var pointer: Variant = _cursor(at, handle.y)
	var change := Vector2.ZERO
	if pointer != null and drag.anchor != null:
		change = pointer - drag.anchor
	var height_change: float = (drag.start.y - at.y) * VIEW.meters_per_pixel(camera, _world(handle.at, handle.y))
	var point: Vector2 = handle.at + change
	match handle.kind:
		"center":
			if _can_place_peak(state, point, feature.id):
				feature.center = point
		"radius":
			feature.radius = clampf(point.distance_to(feature.center), 4.0, 250.0)
		"height":
			feature.height = clampf(handle.y + height_change, 0.5, 200.0)
		"move":
			var points: PackedVector2Array = feature.points
			for i in points.size():
				points[i] += change
			feature.points = points
		"ridge":
			state.ridges[handle.ridge] = {"height": clampf(handle.height + height_change, 0.0, handle.limit)}
		"vertex":
			var points: PackedVector2Array = feature.points
			points[handle.index] = point
			if feature.kind == "plateau" and not LAYOUT.polygon_is_valid(points):
				return
			if feature.kind == "river":
				if (handle.index > 0 and point.distance_to(points[handle.index - 1]) < 0.5) or (handle.index + 1 < points.size() and point.distance_to(points[handle.index + 1]) < 0.5):
					return
			feature.points = points
		"width":
			feature.width = clampf(absf((point - handle.middle).dot(handle.normal)) * 2.0, 2.0, 70.0)
	drag.layout = state

func _set_profile(index: int) -> void:
	var state := _state()
	if mode == Mode.SELECT:
		var feature := LAYOUT.find(state, selected)
		if feature.get("kind") != "peak":
			return
		feature.profile = index
		_commit(state, "调整山体类型")
	else:
		defaults.profile = index
		draft_dirty = true

func _apply_field(index: int) -> void:
	if index >= field_specs.size() or not active:
		return
	var spec: Array = field_specs[index]
	var field := fields[index]
	if not field.text.is_valid_float() or not is_finite(field.text.to_float()):
		_refresh()
		return
	var value := clampf(field.text.to_float(), spec[2], spec[3])
	var key: String = spec[1]
	var state := _state()
	if not selected_ridge.is_empty():
		state.ridges[selected_ridge] = {"height": value}
		_commit(state, "调整山口高度")
	elif selected > 0 and mode == Mode.SELECT:
		var feature := LAYOUT.find(state, selected)
		if not feature.is_empty():
			feature[key] = value
			_commit(state, "调整地形尺寸")
	else:
		defaults[key] = value
		draft_dirty = true
	_refresh()

func _refresh() -> void:
	button.set_pressed_no_signal(active)
	actions.visible = active
	options.visible = active
	saved_layout = terrain.layout if is_instance_valid(terrain) else {}
	if not active:
		plugin.update_overlays()
		return
	for i in mode_buttons.size():
		mode_buttons[i].set_pressed_no_signal(mode == i)
	top_button.text = "透视" if is_instance_valid(camera) and VIEW.is_top(camera) else "俯视"
	var feature := LAYOUT.find(_state(), selected)
	var ridge := _current_ridge()
	var kind: String = feature.get("kind", "")
	var values := defaults if kind.is_empty() else feature
	field_specs.clear()
	if mode == Mode.PEAK or kind == "peak":
		field_specs = [["高度", "height", 0.5, 200.0], ["山脚半径", "radius", 4.0, 250.0]]
	elif mode == Mode.RIVER or kind == "river":
		field_specs = [["河宽", "width", 2.0, 70.0], ["河床深度", "depth", 0.3, 25.0]]
	elif kind == "plateau":
		field_specs = [["高度", "height", 0.5, 200.0], ["边坡宽度", "shoulder", 1.0, 80.0]]
	elif mode == Mode.PLATEAU:
		field_specs = [["高度", "plateau_height", 0.5, 200.0], ["边坡宽度", "shoulder", 1.0, 80.0]]
	elif not ridge.is_empty():
		field_specs = [["山口高度", "height", 0.0, minf(ridge.first, ridge.last)]]
		values = ridge
	profile.visible = mode == Mode.PEAK or kind == "peak"
	if profile.visible:
		profile.select(values.profile)
	for i in fields.size():
		var field := fields[i]
		field.visible = i < field_specs.size()
		field_labels[i].visible = field.visible
		if field.visible and not field.has_focus():
			var spec: Array = field_specs[i]
			field_labels[i].text = spec[0] + " (m)"
			field.text = String.num(values[spec[1]], 2)
	finish_button.visible = mode == Mode.RIVER
	finish_button.disabled = river_points.size() < 2
	duplicate_button.visible = not kind.is_empty()
	remove_button.visible = not kind.is_empty() or not ridge.is_empty()
	remove_button.text = "断开山脊" if not ridge.is_empty() else "删除"
	plugin.update_overlays()

func draw(control: Control) -> void:
	if not active or root() == null or not is_instance_valid(camera) or not VIEW.belongs_to(camera, control):
		return
	var surface := _current_surface()
	if surface != null:
		var state: Dictionary = drag.layout if not drag.is_empty() else surface.state
		VIEW.draw(control, camera, _basis(), surface, state, selected, selected_ridge, mode == Mode.SELECT)
	var caption: String = [
		"选择控制点并拖动  ·  Esc 退出地形",
		"点击添加山峰  ·  靠近其他山峰可预览山脊  ·  Esc 返回选择",
		"从上游向下游点击  ·  Enter 完成  ·  Esc 取消",
		"按住左键拖出高原范围  ·  Esc 返回选择",
		"移动预览，点击放置地形预设  ·  Esc 返回选择",
	][mode]
	if mode == Mode.SELECT and selected > 0 and LAYOUT.find(_state(), selected).get("kind") == "plateau":
		caption = "拖动边界控制点  ·  双击边界加点  ·  Esc 退出地形"
	if mode == Mode.RIVER and surface != null and surface.rivers.any(func(river: Dictionary) -> bool: return 1 in river.cuts):
		caption += "  ·  橙色段需要深挖"
	if surface != null and mode == Mode.SELECT and _spawn_is_buried(surface):
		caption += "  ·  出生点低于地形，可用轮盘重新放置"
	var font := control.get_theme_default_font()
	var size := control.get_theme_default_font_size()
	var width := minf(control.size.x - 24, font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 24)
	var rect := Rect2(Vector2(12, control.size.y - 44), Vector2(width, 30))
	control.draw_style_box(STYLE.box(Color(0.08, 0.13, 0.23, 0.92), 4, 8), rect)
	control.draw_string(font, rect.position + Vector2(12, 21), caption, HORIZONTAL_ALIGNMENT_LEFT, width - 20, size, Color.WHITE)

func _spawn_is_buried(surface: RefCounted) -> bool:
	var scene := root()
	if scene == null: return false
	for marker in scene.find_children("*", "Marker3D", true, false):
		if marker.get_script() != SPAWN or marker.role != "player": continue
		var at: Vector3 = _basis().affine_inverse() * marker.global_position
		if surface.bounds.has_point(Vector2(at.x, at.z)) and surface.height_at(Vector2(at.x, at.z)) > at.y + 0.06:
			return true
	return false
