@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor_sky/panel.gd"
# Deliberately fail after suspension, so recovery is tested independently of image codecs.
func _load_hdri_texture(_path: String, _request: int, _owner_draft: Resource) -> Dictionary:
	await get_tree().process_frame
	return {"error": "QA 异步导入失败"}
