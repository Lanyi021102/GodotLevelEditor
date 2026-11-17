@tool
extends RefCounted
const PRESET := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/preset.gd")
const DIRECTORY := "res://addons/godot_level_editor/resources/sky_presets"
const CUSTOM := "res://content/resources/sky_presets/custom"
const DEFAULT := DIRECTORY + "/builtin/sunny_v2.tres"

static func paths(directory := DIRECTORY) -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".tres"): result.append(directory.path_join(file))
	for folder in DirAccess.get_directories_at(directory): result.append_array(paths(directory.path_join(folder)))
	if directory == DIRECTORY: result.append_array(paths(CUSTOM))
	result.sort()
	return result

static func bound_preset(scene_path: String) -> Resource:
	var scene := ResourceLoader.load(scene_path, "PackedScene") as PackedScene
	if scene == null: return null
	var state := scene.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"sky_preset": return state.get_node_property_value(0, i)
	return null

static func users(path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var levels := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	if levels.catalog == null: return result
	for row in levels.catalog.levels:
		var preset := bound_preset(str(row.scene_path))
		if preset != null and preset.resource_path == path: result.append(str(row.display_name))
	return result

static func thumbnail(preset: Resource) -> ImageTexture:
	var image := Image.create(96, 48, false, Image.FORMAT_RGB8)
	for y in 48:
		var color: Color = preset.top_color.lerp(preset.horizon_color, float(y) / 47.0)
		for x in 96: image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
