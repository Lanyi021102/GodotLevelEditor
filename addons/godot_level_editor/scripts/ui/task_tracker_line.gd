@tool
extends Control
@export var heading := false
var strike := 0.0:
	set(value): strike = value; queue_redraw()
@onready var label: Label = $Text

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22 if heading else 18)
	label.add_theme_color_override("font_color", Color("f4f7f8"))
	label.add_theme_color_override("font_shadow_color", Color(0.015, 0.025, 0.03, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.025, 0.03, 0.7))
	label.add_theme_constant_override("outline_size", 4)
	label.resized.connect(queue_redraw)
	label.resized.connect(_sync_height)
	label.minimum_size_changed.connect(_sync_height)

func set_text(value: String) -> void:
	label.text = value
	_sync_height.call_deferred()
	queue_redraw()

func _sync_height() -> void:
	var height := maxf(32, label.get_minimum_size().y)
	custom_minimum_size.y = height
	if label.offset_bottom != height: label.offset_bottom = height

func _draw() -> void:
	if strike > 0 and is_instance_valid(label):
		var font := label.get_theme_font("font")
		var width := minf(label.size.x, font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x)
		var y := label.position.y + label.size.y * 0.52
		draw_line(Vector2(label.position.x, y), Vector2(label.position.x + width * strike, y), Color("d4e8e8"), 1.8, true)
