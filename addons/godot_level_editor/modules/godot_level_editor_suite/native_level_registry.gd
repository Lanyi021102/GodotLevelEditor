@tool
extends RefCounted
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")

static func prepare(root: Node) -> void:
	if root == null or root.get_script() != WORLD: return
	var book := LEVELS.load_book(LEVELS.PATH, false)
	if book.catalog == null: return
	var existing: Dictionary = book.catalog.by_id(str(root.level_id))
	var duplicate := not existing.is_empty() and str(existing.scene_path) != root.scene_file_path and FileAccess.file_exists(str(existing.scene_path))
	if str(root.level_id).is_empty() or duplicate:
		root.level_id = book.catalog.allocate_id()
		root.world_id = "level_" + str(root.level_id)
		for key in ["topology", "events", "level_logic"]:
			var graph: Resource = root.get(key)
			if graph != null:
				graph = graph.duplicate(true)
				graph.graph_id = root.world_id + "_" + key
				root.set(key, graph)
		EditorInterface.mark_scene_as_unsaved()

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
		push_warning("此关卡 ID 已由另一个场景使用。再次保存当前场景可分配独立 ID。")
		prepare(EditorInterface.get_edited_scene_root())
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
		var errors: PackedStringArray = LEVELS.XLSX.write_book(LEVELS.PATH, book.catalog.sheets())
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
	var errors: PackedStringArray = LEVELS.XLSX.write_book(LEVELS.PATH, book.catalog.sheets())
	if not errors.is_empty(): push_error("关卡索引更新失败：" + "; ".join(errors))
