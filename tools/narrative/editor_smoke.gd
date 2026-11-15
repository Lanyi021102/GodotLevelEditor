@tool
extends RefCounted
func run(plugin: EditorPlugin) -> void:
	var suite := plugin.get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
	for i in 60:
		if suite != null and suite._built: break
		await plugin.get_tree().process_frame
	await load("res://tools/godot_level_editor_suite/editor_test.gd").new().run(suite)
