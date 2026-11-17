extends SceneTree
const Factory := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/factory.gd")
const Store := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd")
func _initialize() -> void:
	var failed := false
	for kind in Factory.Schema.COMPONENT_KINDS:
		var path := "res://addons/godot_level_editor/scenes/mechanisms/" + str(kind) + ".tscn"
		if FileAccess.file_exists(path): continue
		var asset := Factory.standalone(kind)
		var result := Store.save_pair(asset, path); asset.free()
		if not result.ok: push_error(str(result.errors)); failed = true
	quit(1 if failed else 0)
