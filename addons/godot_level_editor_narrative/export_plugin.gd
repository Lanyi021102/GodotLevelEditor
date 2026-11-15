@tool
extends EditorExportPlugin
const TASK := preload("res://addons/godot_level_editor_narrative/runtime/task_definition.gd")
const CATALOG := preload("res://addons/godot_level_editor_suite/runtime/event_catalog.gd")
var _included: Dictionary = {}
func _get_name() -> String: return "GodotLevelEditorWorkbookTables"
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	_included.clear()
	for filename in DirAccess.get_files_at("res://配表"):
		if filename.ends_with(".xlsx"): _include("res://配表/" + filename)
	var catalog := CATALOG.load_book()
	if catalog.errors.is_empty():
		for task in catalog.catalog.tasks:
			if FileAccess.file_exists(task.graph_path): _include(task.graph_path)
	var levels := preload("res://addons/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	if levels.errors.is_empty():
		_include("res://scenes/level_editor/play_session.tscn")
		for row in levels.catalog.levels: _include(row.scene_path)
func _include(path: String) -> void:
	if _included.has(path): return
	if not FileAccess.file_exists(path): push_error("导出缺少配表：" + path); return
	add_file(path, FileAccess.get_file_as_bytes(path), false)
	_included[path] = true
	if path.get_extension() in ["tres", "tscn", "gd", "gdshader"]:
		if path.ends_with(".tres"):
			var source := load(path)
			_include_graph(source)
		elif path.ends_with(".tscn"):
			var scene: PackedScene = load(path)
			if scene != null:
				var state := scene.get_state()
				for i in state.get_node_count():
					for j in state.get_node_property_count(i):
						if state.get_node_property_name(i, j) == &"level_logic": _include_graph(state.get_node_property_value(i, j))
		for dependency in ResourceLoader.get_dependencies(path):
			var target := str(dependency).split("::")[-1]
			if target.begins_with("res://"): _include(target)
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.get_extension() != "tres": return
	var source := load(path)
	_include_graph(source)

func _include_graph(source: Resource) -> void:
	if source == null or not source.has_method("load_dialogue"): return
	_include(source.table_file())
	if source.is_level_logic(): _include(source.events_xlsx)
	for n in source.nodes:
		if n.kind == "run_subgraph": _include(str(n.params.graph_path))
