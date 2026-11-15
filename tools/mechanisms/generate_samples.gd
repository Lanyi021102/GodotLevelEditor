extends SceneTree
const Factory := preload("res://addons/godot_level_editor_mechanisms/factory.gd")
const Store := preload("res://addons/godot_level_editor_mechanisms/store.gd")
func _initialize() -> void:
	var sample := Factory.sample()
	var result := Store.save_pair(sample, "res://scenes/mechanisms/lever_plate_door.tscn")
	print(result)
	for kind in ["lever", "door"]:
		var object := Factory.component(kind, kind)
		var packed := PackedScene.new()
		packed.pack(object)
		ResourceSaver.save(packed, "res://scenes/mechanisms/" + kind + ".tscn")
		object.free()
	sample.free()
	quit(0 if result.get("ok", false) else 1)
