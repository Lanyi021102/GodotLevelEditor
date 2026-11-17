@tool
extends RefCounted
## Filled identity tags. Keep native typography and authored workbooks intact.
const PALETTE := [Color("2563eb"), Color("0f766e"), Color("7c3aed"), Color("0369a1"), Color("e0e7ff"), Color("ccfbf1"), Color("bae6fd"), Color("ede9fe")]
const DARK_TEXT := Color("243247")

static func ink(key: String) -> Color:
	if key.is_empty(): return Color("738196")
	if key.begins_with("level:") and key.trim_prefix("level:").is_valid_int():
		return PALETTE[int(key.trim_prefix("level:")) % PALETTE.size()]
	return PALETTE[key.sha256_text().substr(0, 8).hex_to_int() % PALETTE.size()]

static func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b

static func text_color(background: Color) -> Color:
	var lightness := luminance(background)
	var white_contrast := 1.05 / (lightness + 0.05)
	var dark_contrast := (lightness + 0.05) / (luminance(DARK_TEXT) + 0.05)
	return Color.WHITE if white_contrast >= dark_contrast else DARK_TEXT

static func apply(item: TreeItem, column: int, key: String) -> void:
	if key.is_empty(): return
	var badge := StyleBoxFlat.new()
	badge.bg_color = ink(key)
	badge.border_color = badge.bg_color.darkened(0.08)
	badge.set_border_width_all(1)
	badge.set_corner_radius_all(4)
	item.set_meta("identity_frame_" + str(column), key)
	# Changing a TreeItem's mode resets its cell text in Godot.
	var text := item.get_text(column)
	item.set_cell_mode(column, TreeItem.CELL_MODE_CUSTOM)
	item.set_text(column, text)
	# This native override also keeps selected-row text readable on the badge.
	item.set_custom_color(column, text_color(badge.bg_color))
	item.set_custom_draw_callback(column, _draw_badge.bind(column, badge))

static func _draw_badge(item: TreeItem, rect: Rect2, column: int, badge: StyleBoxFlat) -> void:
	var tree := item.get_tree()
	var font := tree.get_theme_font("font")
	var font_size := tree.get_theme_font_size("font_size")
	var text_width := font.get_string_size(item.get_text(column), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var height := minf(font.get_height(font_size) + 8.0, rect.size.y - 4.0)
	var width := minf(text_width + 14.0, rect.size.x + 7.0)
	if height <= 0.0 or width <= 0.0: return
	var frame := Rect2(Vector2(rect.position.x - 7.0, rect.get_center().y - height / 2.0), Vector2(width, height))
	# Tree's drawing canvas clips to its scrolling content, below the header.
	# The engine draws its usual text immediately after this callback.
	badge.draw(tree.get_custom_drawing_canvas_item(), frame)
