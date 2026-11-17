@tool
extends RefCounted
static var _thumb: Texture2D
static var _hover: Texture2D
static var _disabled: Texture2D
static func _icon(color: String) -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><circle cx="9" cy="9" r="7" fill="' + color + '" stroke="#ffffff" stroke-width="2"/></svg>')
	return ImageTexture.create_from_image(image)
static func apply(slider: HSlider) -> void:
	if _thumb == null:
		_thumb = _icon("#2563eb"); _hover = _icon("#1e40af"); _disabled = _icon("#94a3b8")
	for key in ["slider", "grabber_area", "grabber_area_highlight"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("dce3ed") if key == "slider" else Color("2563eb")
		style.set_corner_radius_all(3)
		style.content_margin_top = 3; style.content_margin_bottom = 3
		slider.add_theme_stylebox_override(key, style)
	slider.add_theme_icon_override("grabber", _thumb)
	slider.add_theme_icon_override("grabber_highlight", _hover)
	slider.add_theme_icon_override("grabber_disabled", _disabled)
