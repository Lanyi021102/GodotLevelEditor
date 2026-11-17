@tool
extends RefCounted
## The retired dock smoke suite is replaced by the current native wheel workflow.
static func run(editor: EditorPlugin) -> void:
	await load("res://tools/level_editor/test_quick_add.gd").new().run(editor)
