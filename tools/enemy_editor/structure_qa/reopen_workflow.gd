@tool
extends RefCounted
var passed := 0
var failed := 0
var checks: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	checks.append({"ok": ok, "check": label})
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(panel: Control, count := 8) -> void:
	for i in count: await panel.get_tree().process_frame
func run(panel: Control, _plugin: EditorPlugin) -> void:
	if not FileAccess.file_exists("res://.npc_structure_qa"): panel.get_tree().quit(2); return
	panel.get_tree().create_timer(60, true).timeout.connect(func(): panel.get_tree().quit(2))
	await frames(panel, 20)
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://npc-update-expected.json"))
	for path in expected.files:
		check(FileAccess.file_exists(path) and FileAccess.get_sha256(path) == expected.files[path], "更新插件后个人文件字节保留：" + str(path))
	for path in expected.uids:
		var uid := ResourceLoader.get_resource_uid(path)
		check(uid != ResourceUID.INVALID_ID and ResourceUID.id_to_text(uid) == expected.uids[path], "更新后资源 UID 保留：" + str(path))
	var suite: EditorPlugin = panel.get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
	suite.open_tab("敌人")
	var library: Control = suite.asset_panels["敌人"]
	library.reload_catalog()
	var path := "res://content/resources/enemies/structure_qa/personal_npc.tres"
	check(library.entries.has(path), "更新后个人 NPC 仍在目录")
	library.select_asset(path); library.enter_edit(); await frames(panel)
	check(panel.file_path == path and panel.appearance_panel.visual != null and panel.appearance_panel.visual.errors.is_empty(), "更新后个人模型与骨骼可打开")
	check(panel.definition.appearance.model.resource_path.begins_with("res://content/assets/characters/npc_imports/"), "模型依赖继续指向项目个人素材")
	var scene := load("res://content/scenes/npcs/structure_qa_walking.tscn") as PackedScene
	var npc := scene.instantiate() as Node3D
	check(npc.get("enemy_definition").resource_path == "res://content/resources/enemies/structure_qa/walking_npc.tres", "可放置场景继续引用个人定义")
	check(is_equal_approx(npc.get_node("Collision").shape.radius, 0.42), "更新后保留用户碰撞编辑")
	npc.free()
	if OS.get_cmdline_user_args().has("--capture"):
		suite.window.size = Vector2i(1504, 1000)
		await frames(panel, 15)
		suite.window.get_texture().get_image().save_png("res://npc-structure-editor.png")
	var play_path := "res://npc-structure-play.json"
	if FileAccess.file_exists(play_path): DirAccess.remove_absolute(play_path)
	EditorInterface.play_custom_scene("res://content/scenes/levels/npc_structure_qa.tscn")
	for i in 300:
		if FileAccess.file_exists(play_path): break
		await panel.get_tree().create_timer(0.1, true).timeout
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(play_path)) if FileAccess.file_exists(play_path) else null
	check(result is Dictionary and result.get("failed", 1) == 0, "替换插件后原生 F6 继续通过")
	EditorInterface.stop_playing_scene()
	var output := FileAccess.open("res://npc-structure-update.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": checks}, "  ")); output.close()
	print("NPC STRUCTURE UPDATE: %d passed / %d failed" % [passed, failed])
	panel.get_tree().quit(1 if failed else 0)
