extends SceneTree
func _initialize() -> void:
	var definition = load("res://addons/enemy_editor/runtime/guard_template.gd").create()
	var errors = definition.validate()
	if not errors.is_empty():
		printerr(errors)
		quit(1)
		return
	quit(ResourceSaver.save(definition, "res://resources/enemies/guard_default.tres"))
