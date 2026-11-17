@tool
extends RefCounted
func run(plugin: EditorPlugin) -> void:
	# The narrative smoke now follows native scene saves and lazy task/dialogue
	# pages instead of invoking the retired map-card suite checks.
	var test: EditorPlugin = load("res://tools/narrative/structure_qa/plugin.gd").new()
	plugin.add_child(test)
	plugin.get_tree().create_timer(115, true).timeout.connect(func(): plugin.get_tree().quit(2))
	await test._run()
