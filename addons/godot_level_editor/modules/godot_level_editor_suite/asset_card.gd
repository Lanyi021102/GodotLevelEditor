@tool
extends Button
var asset_path := ""
func _ready() -> void:
	custom_minimum_size = Vector2(144, 128)
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	expand_icon = true
	add_theme_constant_override("icon_max_width", 80)
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip_text = asset_path
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	EditorInterface.get_resource_previewer().queue_resource_preview(asset_path, self, "_preview", null)
func _preview(_path: String, texture: Texture2D, _small: Texture2D, _data: Variant) -> void:
	if texture != null: icon = texture
func drag_payload() -> Dictionary:
	return {"type": "files", "files": PackedStringArray([asset_path])}
func _get_drag_data(_at: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return drag_payload()
