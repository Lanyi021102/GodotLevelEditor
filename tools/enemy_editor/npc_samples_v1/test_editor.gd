@tool
extends RefCounted
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(panel: Control, count := 4) -> void:
	for i in count: await panel.get_tree().process_frame
func run(panel: Control, _plugin: EditorPlugin) -> void:
	await frames(panel, 20)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/godot_level_editor/resources/enemies/samples_v1/catalog.json"))
	var suite: EditorPlugin = panel.get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
	suite.open_tab("敌人")
	var library: Control = suite.asset_panels["敌人"]
	library.reload_catalog()
	check(library.entries.keys().filter(func(path: String): return path.begins_with("res://addons/godot_level_editor/")).size() == 13, "我的NPC目录仅显示13个新示例，不再列出旧守卫")
	for row in catalog.samples:
		check(library.entries.has(row.definition), row.id + "：我的NPC目录可见")
		library.select_asset(row.definition); library.enter_edit()
		await frames(panel)
		check(panel.file_path == row.definition and panel.appearance_panel.visual != null and panel.appearance_panel.visual.errors.is_empty(), row.id + "：打开模型与动画页成功")
		check(panel.appearance_panel.options.size() == int(row.animation_count), row.id + "：实际可选动作数量正确")
		check(FileAccess.file_exists(str(row.preview_path)), row.id + "：真实缩略图存在")
	for word in ["Goblin", "Casual", "Superhero", "Cow", "Yeti", "小体型"]:
		library.search.text = word; library._filter()
		check(library.cards.values().any(func(card: Control): return card.visible), "中文/原模型名搜索：" + word)
	library.search.text = ""; library._filter()
	var assets: Array = preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_catalog.gd").assets("常驻 NPC")
	for row in catalog.samples:
		check(assets.any(func(asset: Dictionary): return asset.path == row.scene and asset.title == row.title), row.id + "：轮盘显示中文名称")
	if OS.get_cmdline_user_args().has("--capture"):
		suite.window.size = Vector2i(1504, 1000)
		library.set_mode(0)
		await frames(panel, 15)
		var output := "res://docs/enemy_editor/samples_v1_2026-11-16"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		suite.window.get_texture().get_image().save_png(output.path_join("npc_catalog.png"))
		library.select_asset("res://addons/godot_level_editor/resources/enemies/samples_v1/monster_cactus.tres"); library.enter_edit(); await frames(panel, 15)
		panel.appearance_panel.visual.play("idle")
		await frames(panel, 8)
		suite.window.get_texture().get_image().save_png(output.path_join("npc_editor.png"))
	print("NPC SAMPLE EDITOR: %d passed / %d failed" % [passed, failed])
	panel.get_tree().quit(1 if failed else 0)
