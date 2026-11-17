@tool
extends RefCounted
## The current workflow uses native inherited maps, saving and F6.
## Do not call the retired level-card selector or creation dialogs.
func run(suite: EditorPlugin) -> void:
	var test := preload("res://tools/sky_editor/structure_test.gd").new()
	test.result_prefix = "SKY_EDITOR_RESULT"
	await test.run(suite)
