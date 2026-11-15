@tool
extends Control
signal selected(id: String)
signal activated(id: String)
const STYLE := preload("res://addons/godot_level_editor_suite/editor_style.gd")
var data: Dictionary = {}
var is_new := false
var new_title := "新建关卡"
var is_selected := false:
	set(value):
		if is_selected == value: return
		is_selected = value
		_animate_selection()
var cover: TextureRect
var _hover := false
var hover_amount := 0.0:
	set(value): hover_amount = value; queue_redraw()
var _tween: Tween
var _selection_tween: Tween
var selection_amount := 0.0:
	set(value): selection_amount = value; queue_redraw()
var selection_pulse := 0.0:
	set(value): selection_pulse = value; queue_redraw()
func _ready() -> void:
	custom_minimum_size = Vector2(230, 248)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	if is_new:
		var label := Label.new(); label.name = "NewLabel"; label.text = "+\n" + new_title; label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.add_theme_color_override("font_color", STYLE.BLUE); label.add_theme_font_size_override("font_size", 18); label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); label.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(label)
	else:
		cover = TextureRect.new(); cover.mouse_filter = Control.MOUSE_FILTER_IGNORE; cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; add_child(cover); _round(cover, 6)
		var path := str(data.get("preview_path", ""))
		if not path.is_empty() and FileAccess.file_exists(path): cover.texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path)))
		if cover.texture == null: EditorInterface.get_resource_previewer().queue_resource_preview(str(data.scene_path), self, "_preview", null)
		if cover.texture == null and data.has("fallback_icon"):
			cover.texture = data.fallback_icon
			cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var title := Label.new(); title.name = "Title"; title.text = str(data.display_name); title.add_theme_font_size_override("font_size", 17); title.add_theme_color_override("font_color", STYLE.INK); title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; title.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(title)
		var meta := Label.new(); meta.name = "Metadata"; meta.text = str(data.get("metadata", "ID " + str(data.level_id) + "   ·   " + str(data.name))); meta.add_theme_font_size_override("font_size", 12); meta.add_theme_color_override("font_color", STYLE.MUTED); meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; meta.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(meta)
		var notes := Label.new(); notes.name = "Notes"; notes.text = str(data.get("notes", "")); notes.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; notes.add_theme_font_size_override("font_size", 13); notes.add_theme_color_override("font_color", STYLE.MUTED); notes.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(notes)
	resized.connect(_layout); _layout()
	mouse_entered.connect(func(): _hover = true; _animate(); queue_redraw())
	mouse_exited.connect(func(): _hover = false; _animate(); queue_redraw())
	focus_entered.connect(queue_redraw); focus_exited.connect(queue_redraw)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			if _tween != null and _tween.is_valid(): _tween.kill()
			if _selection_tween != null and _selection_tween.is_valid(): _selection_tween.kill()
			_hover = false; hover_amount = 0.0; selection_amount = 1.0 if is_selected else 0.0; selection_pulse = 0.0)
func _round(view: TextureRect, radius: float) -> void:
	var material := ShaderMaterial.new(); material.shader = preload("res://addons/godot_level_editor_suite/rounded_preview.gdshader"); material.set_shader_parameter("radius", radius); view.material = material
	view.resized.connect(func(): material.set_shader_parameter("rect_size", view.size))
func _layout() -> void:
	if cover == null: return
	cover.position = Vector2(10, 10); cover.size = Vector2(size.x - 20, size.y - 98)
	get_node("Title").position = Vector2(14, size.y - 80); get_node("Title").size = Vector2(size.x - 28, 26)
	get_node("Metadata").position = Vector2(14, size.y - 51); get_node("Metadata").size = Vector2(size.x - 28, 20)
	get_node("Notes").position = Vector2(14, size.y - 29); get_node("Notes").size = Vector2(size.x - 28, 20)
func _preview(_path: String, texture: Texture2D, _small: Texture2D, _data: Variant) -> void:
	if texture != null and cover != null:
		cover.texture = texture; cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
func _animate() -> void:
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "hover_amount", 1.0 if _hover else 0.0, 0.14)
func _animate_selection() -> void:
	if _selection_tween != null and _selection_tween.is_valid(): _selection_tween.kill()
	if not is_inside_tree() or not is_visible_in_tree():
		selection_amount = 1.0 if is_selected else 0.0
		selection_pulse = 0.0
		return
	selection_pulse = 1.0 if is_selected else selection_pulse
	_selection_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_selection_tween.tween_property(self, "selection_amount", 1.0 if is_selected else 0.0, 0.18)
	_selection_tween.tween_property(self, "selection_pulse", 0.0, 0.24)
func _draw() -> void:
	var fill := STYLE.PANEL if is_new else STYLE.PAPER.lerp(STYLE.TINT, selection_amount * 0.3)
	var border := STYLE.BLUE if has_focus() else STYLE.BORDER.lerp(STYLE.BLUE, maxf(selection_amount, hover_amount * 0.4))
	var surface := STYLE.bordered(fill, border, 10, 0)
	surface.set_border_width_all(2 if is_selected or has_focus() else 1)
	surface.shadow_color = Color(0.10, 0.17, 0.28, 0.035 + hover_amount * 0.04 + selection_pulse * 0.1)
	surface.shadow_size = 3 + int(hover_amount * 3 + selection_pulse * 5)
	surface.shadow_offset = Vector2(0, 2)
	draw_style_box(surface, Rect2(Vector2.ZERO, size))
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		if is_new: activated.emit("")
		elif event.double_click: activated.emit(str(data.level_id))
		else: selected.emit(str(data.level_id))
	if event.is_action_pressed("ui_accept"):
		activated.emit("" if is_new else str(data.level_id))
		accept_event()
