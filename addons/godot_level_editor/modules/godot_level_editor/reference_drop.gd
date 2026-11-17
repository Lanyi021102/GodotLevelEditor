@tool
extends PanelContainer
## Compact drop surface; children ignore input so GraphEdit can still select cards.
var resolve: Callable
var accept: Callable
var _highlight := false
var _label: Label

func setup(caption: String, value: String, resolver: Callable, receiver: Callable) -> void:
	resolve = resolver
	accept = receiver
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(210, 36)
	tooltip_text = "从场景树拖入%s；放下后自动绑定。" % caption
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = caption + " · " + (value if not value.is_empty() else "拖入对象")
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.tooltip_text = value
	add_child(_label)
	add_to_group("godot_level_editor_reference_drop")
	mouse_exited.connect(func():
		if not get_meta("scene_reference_cross_hover", false): _set_highlight(false))
	_set_highlight(false)

func _set_highlight(enabled: bool) -> void:
	if _highlight == enabled and has_theme_stylebox_override("panel"): return
	_highlight = enabled
	var style := StyleBoxFlat.new()
	style.bg_color = Color("eaf1ff") if enabled else Color("f4f7fb")
	style.border_color = Color("2563eb") if enabled else Color("dce3ed")
	style.set_border_width_all(2 if enabled else 1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 9; style.content_margin_right = 9
	style.content_margin_top = 6; style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)
	if _label != null: _label.add_theme_color_override("font_color", Color("2563eb") if enabled else Color("52637d"))

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	var valid := resolve.is_valid() and not str(resolve.call(data)).is_empty()
	if not get_meta("scene_reference_cross_hover", false): _set_highlight(valid)
	return valid

func _drop_data(_position: Vector2, data: Variant) -> void:
	_set_highlight(false)
	if accept.is_valid() and resolve.is_valid() and not str(resolve.call(data)).is_empty(): accept.call_deferred(data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _highlight: _set_highlight(false)
