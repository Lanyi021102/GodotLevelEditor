@tool
extends Control
var tool: RefCounted
var editor_view: SubViewport

func _ready() -> void:
	name = "GroupedAssetDrop"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return tool.preview_drop(self, at, data)

func _drop_data(at: Vector2, data: Variant) -> void:
	tool.commit_drop(self, at, data)

func camera_point(at: Vector2) -> Vector2:
	var container := editor_view.get_parent() as Control
	var point := container.get_global_transform_with_canvas().affine_inverse() * (get_global_transform_with_canvas() * at)
	return point * Vector2(editor_view.size) / container.size
