@tool
extends RefCounted

const BLOCK := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd")
const INK := Color(0.08, 0.13, 0.20, 0.94)
const LINE := Color(0.34, 0.90, 1.0)

var plugin: EditorPlugin
var button: Button
var selected_block: Node3D
var points := PackedVector3Array()
var hover: Variant = null
var _last_dimensions := Vector3.ZERO

func setup(editor: EditorPlugin, toolbar: Control) -> void:
	plugin = editor
	button = Button.new()
	button.text = "测距"
	button.tooltip_text = "点击两个表面位置测量直线距离和高差，Esc 退出。"
	button.toggle_mode = true
	button.toggled.connect(_toggle)
	toolbar.add_child(button)

func _toggle(enabled: bool) -> void:
	points.clear()
	hover = null
	if enabled:
		plugin.radial_tool.cancel()
		if plugin.terrain_tool != null: plugin.terrain_tool.cancel()
		if plugin.push_pull.enabled:
			plugin.push_pull.set_enabled(false)
	plugin.update_overlays()

func cancel() -> void:
	if is_instance_valid(button) and button.button_pressed:
		button.button_pressed = false

func update_selection(nodes: Array) -> void:
	selected_block = nodes[0] if nodes.size() == 1 and nodes[0].get_script() == BLOCK else null
	plugin.update_overlays()

func dimensions() -> Vector3:
	if not is_instance_valid(selected_block) or not selected_block.is_inside_tree():
		return Vector3.ZERO
	# Keep width, height and depth aligned with the block, including ancestor scale.
	var local_size: Vector3 = selected_block.geometry().get_aabb().size
	var axes := selected_block.global_basis
	return local_size * Vector3(axes.x.length(), axes.y.length(), axes.z.length())

func process() -> void:
	button.disabled = EditorInterface.get_edited_scene_root() == null or EditorInterface.is_playing_scene()
	if button.disabled:
		cancel()
	var current := dimensions()
	if not current.is_equal_approx(_last_dimensions):
		_last_dimensions = current
		plugin.update_overlays()

func input(camera: Camera3D, event: InputEvent) -> bool:
	if not button.button_pressed:
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		return true
	var motion := event is InputEventMouseMotion
	var click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	if not (motion or click) or event.alt_pressed or event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
		return false
	if click and not event.pressed:
		return true
	if motion and points.size() == 2:
		return false
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null:
		return false
	var hit: Dictionary = plugin.radial_tool.pick_surface(camera, event.position, scene, false)
	hover = hit.get("position")
	if click and hover != null:
		if points.size() == 2:
			points.clear()
		points.append(hover)
	plugin.update_overlays()
	return click

func draw(control: Control) -> void:
	if button.button_pressed:
		var end: Variant = points[1] if points.size() == 2 else hover
		var caption := "测距   点击第一个表面位置"
		if points.size() == 1:
			caption = "测距   点击第二个表面位置"
		if not points.is_empty() and end != null:
			var delta: Vector3 = end - points[0]
			caption = "距离 %s m     高差 %s m" % [String.num(delta.length(), 3), String.num(delta.y, 3)]
			caption += "     点击重新测量" if points.size() == 2 else "     点击确定"
		_draw_markers(control, end)
		_draw_caption(control, caption + "     Esc 退出")
	elif is_instance_valid(selected_block) and selected_block.is_inside_tree() and plugin.radial_tool.active_asset.is_empty() and not (is_instance_valid(plugin.radial_tool.menu) and plugin.radial_tool.menu.visible):
		var size := dimensions()
		var caption := "宽 %s m     高 %s m     深 %s m" % [String.num(size.x, 3), String.num(size.y, 3), String.num(size.z, 3)]
		if plugin.push_pull.dragging and plugin.push_pull.picked.get("block") == selected_block:
			caption += "     本次位移 %s m" % String.num(plugin.push_pull.displacement, 3)
		_draw_caption(control, caption)

func _draw_markers(control: Control, end: Variant) -> void:
	var owner: Node = control
	while owner != null and owner.get_class() != "Node3DEditorViewport":
		owner = owner.get_parent()
	if owner == null:
		return
	for index in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(index)
		if viewport == null or not owner.is_ancestor_of(viewport):
			continue
		var camera := viewport.get_camera_3d()
		if camera == null:
			return
		var dots := PackedVector2Array()
		if not points.is_empty() and not camera.is_position_behind(points[0]):
			dots.append(camera.unproject_position(points[0]))
		if end != null and not camera.is_position_behind(end):
			dots.append(camera.unproject_position(end))
		var scale := EditorInterface.get_editor_scale()
		if dots.size() == 2:
			control.draw_line(dots[0], dots[1], INK, 4 * scale, true)
			control.draw_line(dots[0], dots[1], LINE, 2 * scale, true)
		for dot in dots:
			control.draw_circle(dot, 4.5 * scale, INK, true, -1, true)
			control.draw_circle(dot, 3 * scale, LINE, true, -1, true)
		return

func _draw_caption(control: Control, caption: String) -> void:
	var font := control.get_theme_default_font()
	var size := control.get_theme_default_font_size()
	var pad := Vector2(0.65, 0.35) * size
	var available := maxf(1, control.size.x - 4 * pad.x)
	var lines := PackedStringArray()
	var line := ""
	for field in caption.split("     "):
		var joined := line + "     " + field if not line.is_empty() else field
		if not line.is_empty() and font.get_string_size(joined, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > available:
			lines.append(line)
			line = field
		else:
			line = joined
	lines.append(line)
	var width := 0.0
	for row in lines:
		width = maxf(width, font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var row_height := font.get_height(size)
	var bounds := Vector2(minf(width, available), lines.size() * row_height) + 2 * pad
	var origin := Vector2(pad.x, maxf(0, control.size.y - bounds.y - pad.y))
	control.draw_rect(Rect2(origin, bounds), INK)
	var baseline := origin + pad + Vector2(0, font.get_ascent(size))
	for row in lines:
		control.draw_string(font, baseline, row, HORIZONTAL_ALIGNMENT_LEFT, available, size, Color.WHITE)
		baseline.y += row_height
