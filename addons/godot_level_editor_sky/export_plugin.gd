@tool
extends EditorExportPlugin
const LIBRARY := preload("res://addons/godot_level_editor_sky/library.gd")
var _included: Dictionary = {}
func _get_name() -> String: return "GodotLevelEditorSkyPresets"
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	_included.clear()
	for path in LIBRARY.paths(): _include(path)
func _include(path: String) -> void:
	if _included.has(path) or not FileAccess.file_exists(path): return
	_included[path] = true
	add_file(path, FileAccess.get_file_as_bytes(path), false)
	# Presets found at runtime by catalog also require imported HDRI remaps and payloads.
	if FileAccess.file_exists(path + ".import"):
		_include(path + ".import")
		var config := ConfigFile.new()
		if config.load(path + ".import") == OK:
			for imported in config.get_value("deps", "dest_files", PackedStringArray()): _include(str(imported))
	if path.get_extension() in ["tres", "tscn", "gd", "gdshader"]:
		for dependency in ResourceLoader.get_dependencies(path):
			var target := str(dependency).split("::")[-1]
			if target.begins_with("res://"): _include(target)
