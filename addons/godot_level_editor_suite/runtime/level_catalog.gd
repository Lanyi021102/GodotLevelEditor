@tool
extends Resource
const XLSX := preload("res://addons/godot_level_editor_suite/runtime/xlsx.gd")
const PATH := "res://配表/levels.xlsx"
const DIRECTORY := "res://scenes/levels"
const FIELDS := ["level_id", "name", "display_name", "scene_path", "notes", "preview_path"]
@export var levels: Array[Dictionary] = []
@export var next_id := 1
func by_id(id: String) -> Dictionary:
	for row in levels:
		if str(row.level_id) == id: return row
	return {}
func for_world(world: Node) -> Dictionary:
	if world == null: return {}
	var id: Variant = world.get("level_id")
	if id is String and not id.is_empty(): return by_id(id)
	for row in levels:
		if row.scene_path == world.scene_file_path: return row
	return {}
func allocate_id() -> String:
	while not by_id(str(next_id)).is_empty(): next_id += 1
	var id := str(next_id)
	next_id += 1
	return id
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}; var names := {}; var paths := {}
	for row in levels:
		var id := str(row.get("level_id", ""))
		if not id.is_valid_int() or int(id) < 1 or ids.has(id): errors.append("关卡 ID 无效或重复：" + id)
		ids[id] = true
		if not str(row.get("name", "")).is_valid_identifier() or names.has(row.get("name")): errors.append("关卡名无效或重复")
		names[row.get("name")] = true
		if str(row.get("display_name", "")).strip_edges().is_empty(): errors.append("关卡中文名不能为空")
		var path := str(row.get("scene_path", ""))
		if not path.begins_with(DIRECTORY + "/") or not path.ends_with(".tscn") or paths.has(path) or not FileAccess.file_exists(path): errors.append("关卡场景无效：" + path)
		paths[path] = true
	return errors
func sheets() -> Dictionary:
	var rows := [FIELDS]
	for level in levels:
		var row := []
		for key in FIELDS: row.append(str(level.get(key, "")))
		rows.append(row)
	return {"关卡": rows, "配置": [["key", "value"], ["version", "1"], ["next_level_id", str(next_id)]]}
func save_book(path := PATH) -> PackedStringArray:
	var errors := validate()
	return XLSX.write_book(path, sheets()) if errors.is_empty() else errors
static func load_book(path := PATH) -> Dictionary:
	var book := XLSX.read_book(path)
	if not book.errors.is_empty(): return {"catalog": null, "errors": book.errors}
	var rows := XLSX.records(book.sheets, "关卡", ["level_id", "name", "display_name", "scene_path"])
	var meta := XLSX.records(book.sheets, "配置", ["key", "value"])
	var errors: PackedStringArray = rows.errors
	errors.append_array(meta.errors)
	var catalog: Resource = load("res://addons/godot_level_editor_suite/runtime/level_catalog.gd").new()
	catalog.levels.assign(rows.rows)
	for row in catalog.levels:
		row.notes = str(row.get("notes", "")); row.preview_path = str(row.get("preview_path", ""))
	var version := ""
	for row in meta.rows:
		if row.key == "version": version = row.value
		if row.key == "next_level_id": catalog.next_id = maxi(1, int(row.value))
	if version != "1": errors.append("关卡配表版本无效")
	for row in catalog.levels: catalog.next_id = maxi(catalog.next_id, int(row.level_id) + 1)
	errors.append_array(catalog.validate())
	return {"catalog": catalog if errors.is_empty() else null, "errors": errors}
