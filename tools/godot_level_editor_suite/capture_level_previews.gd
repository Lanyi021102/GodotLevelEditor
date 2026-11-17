@tool
extends RefCounted
static func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	if DisplayServer.get_name() == "headless":
		push_error("关卡缩略图需要实际渲染，不能使用 headless。")
		tree.quit(1); return
	tree.create_timer(90, true).timeout.connect(func(): tree.quit(2))
	var result := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book(suite.level_preview.workbook_path)
	if result.catalog == null: print(result.errors); tree.quit(1); return
	var count := [0, 0]
	suite.level_preview.preview_updated.connect(func(_id, _scene, _path, _texture): count[0] += 1)
	suite.level_preview.preview_failed.connect(func(_scene, _reason): count[1] += 1)
	for row in result.catalog.levels: suite.level_preview.request(str(row.scene_path))
	if suite.level_preview.is_busy(): await suite.level_preview.idle
	print("LEVEL EDITOR STATIC PREVIEWS: ", count[0], " saved, ", count[1], " failed")
	tree.quit(0 if count[1] == 0 else 1)
