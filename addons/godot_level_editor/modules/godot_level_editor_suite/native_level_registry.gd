@tool
extends RefCounted
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")

static func _id_at(catalog: Resource, path: String) -> String:
	for row in catalog.levels:
		if str(row.scene_path) == path: return str(row.level_id)
	return ""

static func _assign_identity(root: Node, id: String) -> void:
	root.level_id = id
	root.world_id = "level_" + id
	for key in ["topology", "events", "level_logic"]:
		var graph: Resource = root.get(key)
		if graph != null:
			graph = graph.duplicate(true)
			graph.graph_id = root.world_id + "_" + key
			root.set(key, graph)

static func prepare(root: Node) -> void:
	if root == null or root.get_script() != WORLD: return
	var book := LEVELS.load_book(LEVELS.PATH, false)
	if book.catalog == null: return
	var existing: Dictionary = book.catalog.by_id(str(root.level_id))
	var duplicate := not existing.is_empty() and str(existing.scene_path) != root.scene_file_path and FileAccess.file_exists(str(existing.scene_path))
	var destination_id := _id_at(book.catalog, root.scene_file_path)
	if str(root.level_id).is_empty() or duplicate or (not destination_id.is_empty() and str(root.level_id) != destination_id):
		_assign_identity(root, destination_id if not destination_id.is_empty() else book.catalog.allocate_id())
		EditorInterface.mark_scene_as_unsaved()

static func saved_world(root: Node) -> void:
	# Godot emits scene_saved before updating scene_file_path. POST_SAVE runs
	# after that update, including for a non-current tab saved by Save All.
	if root == null or root.get_script() != WORLD: return
	var path := root.scene_file_path
	if path.is_empty() or path.begins_with("res://addons/") or not FileAccess.file_exists(path): return
	var book := LEVELS.load_book(LEVELS.PATH, false)
	if book.catalog == null: return
	var row: Dictionary = book.catalog.by_id(str(root.level_id))
	var destination_id := _id_at(book.catalog, path)
	if str(root.level_id).is_empty() or (not destination_id.is_empty() and str(root.level_id) != destination_id) or (not row.is_empty() and str(row.scene_path) != path and FileAccess.file_exists(str(row.scene_path))):
		var previous := {"level_id": root.level_id, "world_id": root.world_id}
		for key in ["topology", "events", "level_logic"]: previous[key] = root.get(key)
		_assign_identity(root, destination_id if not destination_id.is_empty() else book.catalog.allocate_id())
		var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var error := scene.pack(root) if scene != null else ERR_CANT_OPEN
		if error == OK: error = ResourceSaver.save(scene, path, ResourceSaver.FLAG_REPLACE_SUBRESOURCE_PATHS)
		if error != OK:
			for key in previous: root.set(key, previous[key])
			push_error("关卡副本 ID 保存失败：" + error_string(error))
			return
		EditorInterface.get_resource_filesystem().update_file(path)
	saved(path)

static func saved(path: String) -> void:
	if path.begins_with("res://addons/"): return
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null: return
	var state := scene.get_state()
	if state.get_node_count() == 0: return
	var id := ""; var script: Script
	for i in state.get_node_property_count(0):
		match str(state.get_node_property_name(0, i)):
			"script": script = state.get_node_property_value(0, i)
			"level_id": id = str(state.get_node_property_value(0, i))
	if script != WORLD:
		# Native inherited scenes can omit the script at their root.
		if state.get_node_instance(0) == null: return
		var instance := scene.instantiate()
		if instance.get_script() == WORLD: id = str(instance.level_id); script = WORLD
		instance.free()
	if script != WORLD or id.is_empty(): return
	var book := LEVELS.load_book(LEVELS.PATH, false)
	if book.catalog == null: return
	var row: Dictionary = book.catalog.by_id(id)
	if not row.is_empty() and str(row.scene_path) != path and FileAccess.file_exists(str(row.scene_path)):
		push_warning("此关卡 ID 已由另一个场景使用，请在原生编辑器中打开并保存此场景。")
		return
	if row.is_empty():
		row = {"level_id": id, "name": "level_" + id, "display_name": path.get_file().get_basename(), "scene_path": path, "notes": "", "preview_path": ""}
		book.catalog.levels.append(row)
	else: row.scene_path = path
	book.catalog.next_id = maxi(book.catalog.next_id, int(id) + 1)
	var errors: PackedStringArray = book.catalog.save_book()
	if not errors.is_empty(): push_error("关卡任务索引保存失败：" + "; ".join(errors))

static func _matches(path: String, old: String) -> bool:
	return path == old or path.begins_with(old.trim_suffix("/") + "/")

static func moved(old: String, target: String) -> void:
	var book := LEVELS.load_book(LEVELS.PATH, false)
	if book.catalog == null: return
	var changed := false
	for row in book.catalog.levels:
		for key in ["scene_path", "preview_path"]:
			var value := str(row.get(key, ""))
			if _matches(value, old):
				row[key] = target.trim_suffix("/") + value.substr(old.trim_suffix("/").length())
				changed = true
	if changed:
		var errors: PackedStringArray = book.catalog.save_book(LEVELS.PATH, false)
		if not errors.is_empty(): push_error("关卡路径更新失败：" + "; ".join(errors))
	# XLSX string fields aren't Godot resource dependencies. Follow task graph
	# file moves explicitly, while retaining tasks and every stable ID.
	var catalog = load("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
	var events: Dictionary = catalog.load_book()
	if events.catalog == null: return
	changed = false
	for row in events.catalog.tasks:
		var path := str(row.graph_path)
		if _matches(path, old):
			row.graph_path = target.trim_suffix("/") + path.substr(old.trim_suffix("/").length())
			changed = true
	if changed:
		var errors: PackedStringArray = events.catalog.save_book()
		if not errors.is_empty(): push_error("任务图路径更新失败：" + "; ".join(errors))

static func removed(path: String) -> void:
	var book := LEVELS.load_book(LEVELS.PATH, false)
	if book.catalog == null: return
	var retained: Array[Dictionary] = []
	for row in book.catalog.levels:
		if not _matches(str(row.scene_path), path): retained.append(row)
	if retained.size() == book.catalog.levels.size(): return
	book.catalog.levels.assign(retained)
	var errors: PackedStringArray = book.catalog.save_book(LEVELS.PATH, false)
	if not errors.is_empty(): push_error("关卡索引更新失败：" + "; ".join(errors))
