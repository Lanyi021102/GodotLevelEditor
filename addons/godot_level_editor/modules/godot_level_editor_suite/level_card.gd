@tool
extends Control
signal selected(id: String)
signal activated(id: String)
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")
static var _placeholder_texture: Texture2D
static var _preview_cache: Dictionary = {}
var data: Dictionary = {}
var is_new := false
var new_title := "新建关卡"
var is_selected := false:
	set(value):
		if is_selected == value: return
		is_selected = value
		_animate_selection()
var cover: TextureRect
var _uses_file_preview := false
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
	custom_minimum_size = Vector2(230, 260)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	if is_new:
		var content := VBoxContainer.new(); content.name = "NewContent"; content.alignment = BoxContainer.ALIGNMENT_CENTER; content.add_theme_constant_override("separation", 12); content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); content.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(content)
		var mark := Label.new(); mark.text = "+"; mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; mark.add_theme_font_size_override("font_size", 30); mark.add_theme_color_override("font_color", STYLE.BLUE); mark.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(mark)
		var label := Label.new(); label.name = "NewLabel"; label.text = new_title; label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.add_theme_color_override("font_color", STYLE.INK); label.add_theme_font_size_override("font_size", 17); label.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(label)
		var hint := Label.new(); hint.text = "从空白工作区开始" if new_title == "新建关卡" else "创建新的可编辑资源"; hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.add_theme_color_override("font_color", STYLE.MUTED); hint.add_theme_font_size_override("font_size", 13); hint.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(hint)
	else:
		cover = TextureRect.new(); cover.name = "Cover"; cover.mouse_filter = Control.MOUSE_FILTER_IGNORE; cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; add_child(cover); _round(cover, 7)
		var path := str(data.get("preview_path", ""))
		cover.texture = preview_texture(path)
		_uses_file_preview = cover.texture != null
		if cover.texture == null:
			EditorInterface.get_resource_previewer().queue_resource_preview(str(data.scene_path), self, "_preview", null)
			cover.texture = data.get("fallback_icon", placeholder_texture())
			if data.has("fallback_icon"): cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var title := Label.new(); title.name = "Title"; title.text = str(data.display_name); title.add_theme_font_size_override("font_size", 17); title.add_theme_color_override("font_color", STYLE.INK); title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; title.tooltip_text = str(data.display_name); title.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(title)
		var meta := Label.new(); meta.name = "Metadata"; meta.text = str(data.get("metadata", "ID " + str(data.level_id) + "   ·   " + str(data.name))); meta.add_theme_font_size_override("font_size", 13); meta.add_theme_color_override("font_color", STYLE.MUTED); meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; meta.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(meta)
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
	var material := ShaderMaterial.new(); material.shader = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/rounded_preview.gdshader"); material.set_shader_parameter("radius", radius); view.material = material
	view.resized.connect(func(): material.set_shader_parameter("rect_size", view.size))
func _layout() -> void:
	var preview_height := roundf(clampf((size.x - 24) * 0.5625, 132, 216))
	var desired_height := preview_height + 112
	if not is_equal_approx(custom_minimum_size.y, desired_height): custom_minimum_size.y = desired_height
	if cover == null: return
	cover.position = Vector2(12, 12); cover.size = Vector2(maxf(0, size.x - 24), preview_height)
	var text_top := preview_height + 24
	get_node("Title").position = Vector2(16, text_top); get_node("Title").size = Vector2(size.x - 32, 26)
	get_node("Metadata").position = Vector2(16, text_top + 31); get_node("Metadata").size = Vector2(size.x - 32, 20)
	get_node("Notes").position = Vector2(16, text_top + 54); get_node("Notes").size = Vector2(size.x - 32, 20)

static func placeholder_texture() -> Texture2D:
	if _placeholder_texture != null: return _placeholder_texture
	# A neutral level illustration is immediately available while Godot generates
	# its actual preview. It never instantiates or rewrites an authored scene.
	var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="960" height="540" viewBox="0 0 640 360">
<defs><linearGradient id="b" x2="1" y2="1"><stop stop-color="#e8eef7"/><stop offset="1" stop-color="#f5f8fc"/></linearGradient><pattern id="g" width="32" height="32" patternUnits="userSpaceOnUse"><path d="M32 0H0V32" fill="none" stroke="#d5dfed" stroke-width="1"/></pattern></defs>
<rect width="640" height="360" fill="url(#b)"/><rect width="640" height="360" fill="url(#g)"/>
<ellipse cx="324" cy="270" rx="173" ry="30" fill="#aebfd6" opacity=".18"/>
<path d="M136 196L320 96L506 196L320 298Z" fill="#cbd8ea"/><path d="M136 196L320 298V312L136 210Z" fill="#a9bad2"/><path d="M320 298L506 196V210L320 312Z" fill="#b9c9df"/>
<path d="M184 173L268 127L323 157L239 203Z" fill="#fbfcff"/><path d="M184 173L239 203V239L184 209Z" fill="#c5d2e5"/><path d="M239 203L323 157V193L239 239Z" fill="#dce5f1"/>
<path d="M321 187L390 149L454 184L385 222Z" fill="#eaf0fa"/><path d="M321 187L385 222V254L321 219Z" fill="#b6c8e2"/><path d="M385 222L454 184V216L385 254Z" fill="#ccdaed"/>
<path d="M287 221L318 204L349 221L318 238Z" fill="#6c96db"/>
<path d="M393 137V99L427 118V155Z" fill="#80a9e8"/><path d="M393 99L403 94L437 113L427 118Z" fill="#b0caf0"/><path d="M427 118L437 113V150L427 155Z" fill="#5682c4"/>
</svg>"""
	var image := Image.new()
	if image.load_svg_from_string(svg) == OK: _placeholder_texture = ImageTexture.create_from_image(image)
	return _placeholder_texture

static func clear_preview_cache() -> void:
	_preview_cache.clear()

static func preview_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		_preview_cache.erase(path)
		return null
	var digest := FileAccess.get_md5(path)
	if _preview_cache.has(path) and _preview_cache[path].digest == digest:
		return _preview_cache[path].texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty(): return null
	# Covers are UI thumbnails; retain enough detail for Retina without holding
	# full-resolution screenshots indefinitely. Bound the shared cache as well.
	var longest := maxi(image.get_width(), image.get_height())
	if longest > 768:
		var factor := 768.0 / longest
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	if _preview_cache.size() >= 64: _preview_cache.erase(_preview_cache.keys()[0])
	_preview_cache[path] = {"digest": digest, "texture": texture}
	return texture
func _preview(_path: String, texture: Texture2D, _small: Texture2D, _data: Variant) -> void:
	if not _uses_file_preview and texture != null and cover != null:
		cover.texture = texture; cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
func set_preview(path: String, texture: Texture2D) -> void:
	if texture == null: return
	data.preview_path = path
	_uses_file_preview = true
	# Reuse the bounded, content-aware cache for later selections and reloads.
	_preview_cache.erase(path)
	if cover != null:
		cover.texture = texture
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
	var surface := STYLE.bordered(fill, border, 12, 0)
	surface.set_border_width_all(2 if is_selected or has_focus() else 1)
	surface.shadow_color = Color(0.10, 0.17, 0.28, 0.025 + hover_amount * 0.045 + selection_pulse * 0.08)
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
