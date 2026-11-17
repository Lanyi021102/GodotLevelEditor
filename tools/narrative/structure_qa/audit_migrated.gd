extends SceneTree
const ROOT := "res://addons/godot_level_editor/modules/"
const TASK := preload(ROOT + "godot_level_editor_narrative/runtime/task_definition.gd")

func _initialize() -> void:
	var result := {"tasks": [], "graph_files": [], "levels": [], "errors": []}
	var catalog: Dictionary = load(ROOT + "godot_level_editor_suite/runtime/event_catalog.gd").load_book()
	result.errors.append_array(Array(catalog.errors))
	if catalog.catalog != null:
		for row in catalog.catalog.tasks:
			var graph: Resource = ResourceLoader.load(str(row.graph_path), "", ResourceLoader.CACHE_MODE_IGNORE)
			result.tasks.append({"task_id": row.task_id, "level_id": row.level_id, "path": row.graph_path, "loaded": graph is TASK, "nodes": graph.nodes.size() if graph is TASK else 0, "validation": Array(graph.validate()) if graph is TASK else ["missing graph"]})
	var files := []
	collect("res://content/resources", files)
	for path in files:
		var graph := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if graph is TASK and not graph.is_level_logic():
			result.graph_files.append({"path": path, "nodes": graph.nodes.size(), "edges": graph.edges.size(), "graph_id": graph.graph_id, "script": graph.get_script().resource_path, "table": graph.table_file(), "validation": Array(graph.validate())})
	var levels: Dictionary = load(ROOT + "godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	result.errors.append_array(Array(levels.errors))
	if levels.catalog != null:
		for row in levels.catalog.levels:
			var scene := ResourceLoader.load(str(row.scene_path), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var world: Node = scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if scene != null else null
			result.levels.append({"id": row.level_id, "path": row.scene_path, "saved_id": str(world.get("level_id")) if world != null else "", "loaded": world != null})
			if world != null: world.free()
	var file := FileAccess.open("user://narrative-migrated-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print("MIGRATED_NARRATIVE_AUDIT: ", result.tasks.size(), " catalog tasks; ", result.graph_files.size(), " graph files; ", result.levels.size(), " native maps; ", result.errors.size(), " catalog errors")
	for row in result.graph_files:
		print(row.path, ": ", row.nodes, " nodes, ", row.validation.size(), " validation messages")
	quit(0 if result.errors.is_empty() else 1)

func collect(path: String, files: Array) -> void:
	for name in DirAccess.get_files_at(path):
		if name.ends_with(".tres"): files.append(path.path_join(name))
	for name in DirAccess.get_directories_at(path): collect(path.path_join(name), files)
