extends Node
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/factory.gd")
const STORE := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd")
func _ready() -> void:
	var failed := false
	for kind in FACTORY.Schema.COMPONENT_KINDS:
		var path := "res://addons/godot_level_editor/scenes/mechanisms/" + str(kind) + ".tscn"
		if FileAccess.file_exists(path): continue
		var asset := FACTORY.standalone(kind)
		var result := STORE.save_pair(asset, path, true); asset.free()
		if not result.ok: push_error(str(result.errors)); failed = true
	get_tree().quit(1 if failed else 0)
