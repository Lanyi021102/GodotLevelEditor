@tool
extends RefCounted
## One source for warehouse cards and the native viewport quick-add wheel.
const SHAPES := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_shapes.gd")
const VEHICLE := "载具"
const VEHICLE_SCRIPT := preload("res://addons/godot_level_editor/modules/godot_level_editor_vehicle/vehicle.gd")
const CATEGORIES := ["玩家出生点", "Layout 白盒", "常驻 Room", "常驻机关", "常驻 NPC", VEHICLE]
const RECENT := "最近使用"

static func assets(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match category:
		"玩家出生点": _append(result, "res://addons/godot_level_editor/modules/godot_level_editor/palette_assets/spawn.tscn", "玩家出生点", category)
		"Layout 白盒":
			for kind in SHAPES.LABELS:
				_append(result, "res://addons/godot_level_editor/modules/godot_level_editor/palette_assets/" + kind + ".tscn", SHAPES.LABELS[kind], category, kind)
		"常驻 Room":
			_append(result, "res://addons/godot_level_editor/scenes/level_editor/rooms/trigger_room.tscn", "触发区域", category)
		"常驻机关":
			_folder(result, "res://addons/godot_level_editor/scenes/mechanisms", category)
			_folder(result, "res://content/scenes/mechanisms", category)
		"常驻 NPC":
			_folder(result, "res://addons/godot_level_editor/scenes/npcs", category)
			_folder(result, "res://content/scenes/npcs", category)
		VEHICLE:
			_vehicle_folder(result, "res://addons/godot_level_editor/scenes/vehicles")
			_vehicle_folder(result, "res://content/scenes/vehicles")
	return result

static func find_asset(path: String) -> Dictionary:
	if path.begins_with("{"):
		var record: Variant = JSON.parse_string(path)
		if record is Dictionary:
			var source := find_asset(str(record.get("path", "")))
			if source.is_empty() and record.get("template", false) and FileAccess.file_exists(str(record.get("path", ""))): source = record.duplicate()
			if not source.is_empty():
				source.merge(record, true)
				if source.get("template", false) and source.get("entity_kind") == "room":
					source.title = template(source.category, source.get("lifetime", "level")).title
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

static func preview_path(asset: Dictionary) -> String:
	# Use the same saved previews as the NPC and mechanism workspace cards.
	var path := str(asset.get("path", ""))
	if str(asset.get("category", "")) == "常驻机关":
		var saved := "res://addons/godot_level_editor/resources/mechanisms/whitebox_v1/previews/" + path.get_file().get_basename() + ".png"
		if FileAccess.file_exists(saved): return saved
	if str(asset.get("category", "")) == "常驻 NPC" and FileAccess.file_exists(path):
		var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
		if scene != null:
			var state := scene.get_state()
			if state.get_node_count() == 0: return ""
			for i in state.get_node_property_count(0):
				var key := str(state.get_node_property_name(0, i))
				if key in ["enemy_definition", "definition"]:
					var definition := state.get_node_property_value(0, i) as Resource
					var sample: Dictionary = definition.get_meta("npc_sample_v1", {}) if definition != null else {}
					var saved := str(sample.get("preview_path", ""))
					if not saved.is_empty() and FileAccess.file_exists(saved): return saved
	return ""

static func template(category: String, lifetime: String) -> Dictionary:
	var kind := entity_kind(category)
	var path: String = {"npc": "res://addons/godot_level_editor/scenes/npcs/v1_human_medium_male.tscn", "mechanism": "res://addons/godot_level_editor/modules/godot_level_editor/palette_assets/placeholder.tscn", "room": "res://addons/godot_level_editor/scenes/level_editor/rooms/trigger_room.tscn"}.get(kind, "")
	var label: String = {"npc": "NPC", "mechanism": "机关", "room": "触发区域"}.get(kind, "")
	return {"path": path, "title": ("关卡常驻 " if lifetime == "level" else "任务 ") + label, "category": category, "kind": "", "entity_kind": kind, "lifetime": lifetime, "template": true}

static func recent_key(asset: Dictionary) -> String:
	return JSON.stringify(asset) if asset.has("entity_kind") else str(asset.path)

static func _append(result: Array[Dictionary], path: String, title: String, category: String, kind := "") -> void:
	for asset in result:
		if asset.path == path: return
	result.append({"path": path, "title": title, "category": category, "kind": kind})

static func _folder(result: Array[Dictionary], folder: String, category: String) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".tscn"):
			var path := folder.path_join(file)
			var title := file.get_basename()
			if category == "常驻 NPC": title = _scene_title(path, title)
			_append(result, path, title, category)

static func _scene_title(path: String, fallback: String) -> String:
	var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
	if scene == null: return fallback
	var state := scene.get_state()
	if state.get_node_count() == 0: return fallback
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == "metadata/editor_display_name": return str(state.get_node_property_value(0, i))
	return fallback


static func _vehicle_folder(result: Array[Dictionary], folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".tscn"): continue
		var path := folder.path_join(file)
		var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
		if scene == null: continue
		var state := scene.get_state()
		if state.get_node_count() == 0: continue
		var title := file.get_basename()
		var is_vehicle := false
		for index in state.get_node_property_count(0):
			match str(state.get_node_property_name(0, index)):
				"script": is_vehicle = state.get_node_property_value(0, index) == VEHICLE_SCRIPT
				"display_name": title = str(state.get_node_property_value(0, index))
		if is_vehicle: _append(result, path, title, VEHICLE)
	for name in DirAccess.get_directories_at(folder):
		_vehicle_folder(result, folder.path_join(name))
