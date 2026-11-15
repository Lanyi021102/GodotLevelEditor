@tool
extends RefCounted
## One source for warehouse cards and the native viewport quick-add wheel.
const SHAPES := preload("res://addons/godot_level_editor/runtime/whitebox_shapes.gd")
const CATEGORIES := ["玩家出生点", "Layout 白盒", "常驻 Room", "常驻机关", "常驻 NPC"]
const RECENT := "最近使用"

static func assets(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match category:
		"玩家出生点": _append(result, "res://addons/godot_level_editor/palette_assets/spawn.tscn", "玩家出生点", category)
		"Layout 白盒":
			for kind in SHAPES.LABELS:
				_append(result, "res://addons/godot_level_editor/palette_assets/" + kind + ".tscn", SHAPES.LABELS[kind], category, kind)
		"常驻 Room":
			_append(result, "res://scenes/level_editor/rooms/permanent_room.tscn", "常驻 Room", category)
			_folder(result, "res://scenes/level_editor/rooms", category)
		"常驻机关": _folder(result, "res://scenes/mechanisms", category)
		"常驻 NPC":
			_append(result, "res://scenes/narrative/npc.tscn", "中立 NPC", category)
			_append(result, "res://scenes/guard.tscn", "守卫", category)
			_folder(result, "res://scenes/npcs", category)
	return result

static func find_asset(path: String) -> Dictionary:
	if path.begins_with("{"):
		var record: Variant = JSON.parse_string(path)
		if record is Dictionary:
			var source := find_asset(str(record.get("path", "")))
			if source.is_empty() and record.get("template", false) and FileAccess.file_exists(str(record.get("path", ""))): source = record.duplicate()
			if not source.is_empty():
				source.merge(record, true)
			return source
	for category in CATEGORIES:
		for asset in assets(category):
			if asset.path == path: return asset
	return {}

static func recent_assets(paths: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for path in paths:
		var asset := find_asset(path)
		if not asset.is_empty(): result.append(asset)
	return result

static func entity_kind(category: String) -> String:
	return {"常驻 NPC": "npc", "常驻机关": "mechanism", "常驻 Room": "room"}.get(category, "")

static func template(category: String, lifetime: String) -> Dictionary:
	var kind := entity_kind(category)
	var path: String = {"npc": "res://scenes/narrative/npc.tscn", "mechanism": "res://addons/godot_level_editor/palette_assets/placeholder.tscn", "room": "res://scenes/level_editor/rooms/permanent_room.tscn"}.get(kind, "")
	var label: String = {"npc": "NPC", "mechanism": "机关", "room": "Room"}.get(kind, "")
	return {"path": path, "title": ("关卡常驻 " if lifetime == "level" else "任务 ") + label, "category": category, "kind": "", "entity_kind": kind, "lifetime": lifetime, "template": true}

static func recent_key(asset: Dictionary) -> String:
	return JSON.stringify(asset) if asset.has("entity_kind") else str(asset.path)

static func _append(result: Array[Dictionary], path: String, title: String, category: String, kind := "") -> void:
	for asset in result:
		if asset.path == path: return
	result.append({"path": path, "title": title, "category": category, "kind": kind})

static func _folder(result: Array[Dictionary], folder: String, category: String) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".tscn"): _append(result, folder + "/" + file, file.get_basename(), category)
