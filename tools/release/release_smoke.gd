@tool
extends Node
const ROOT := "res://addons/godot_level_editor"
const USER := "res://content"
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("RELEASE_CHECK: " + message)

func run(entry: EditorPlugin) -> void:
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(2))
	for i in 15: await get_tree().process_frame
	check(entry._started, "主插件初始化")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://host.tscn", "保留宿主主场景")
	check(ProjectSettings.get_setting("input/move_forward").events[0].physical_keycode == KEY_UP, "保留已有输入")
	check(ProjectSettings.get_setting("autoload/NoiseBus") == "*res://host.gd", "保留宿主同名服务")
	for service in entry.SERVICES:
		check(ProjectSettings.has_setting("autoload/" + str(service)), "运行服务 " + str(service))
	var suites := get_tree().get_nodes_in_group("godot_level_editor_editor_suite")
	check(suites.size() == 1, "统一套件只有一个实例")
	if suites.is_empty(): _finish(); return
	var suite = suites[0]
	suite.prepare_all_pages()
	for i in 10: await get_tree().process_frame
	check(suite.modules.size() == 4, "四个编辑后端")
	check(suite.asset_panels["机关"].entries.size() == 5, "五种机关")
	check(suite.asset_panels["敌人"].entries.size() == 13, "13 个 NPC")
	for category in ["机关", "敌人"]:
		for source_path in suite.asset_panels[category].entries:
			var path: String = str(source_path)
			check(ResourceLoader.exists(path), "素材可加载 " + path)
	for file in DirAccess.get_files_at(ROOT + "/scenes/npcs"):
		if file.ends_with(".tscn"):
			var actor := load(ROOT + "/scenes/npcs/" + file).instantiate() as Node
			check(actor != null, "NPC 实例 " + file)
			if actor != null: actor.free()
	var events = load(ROOT + "/modules/godot_level_editor_suite/runtime/event_catalog.gd").load_book()
	check(events.errors.is_empty() and events.catalog.tasks.is_empty(), "空任务配表")
	var library = load(ROOT + "/modules/godot_level_editor_narrative/runtime/dialogue_library.gd").read_xlsx(USER + "/tables/dialogues.xlsx")
	check(library.errors.is_empty() and library.library.groups.is_empty(), "空对白配表")
	check(suite.sky_panel != null, "天空编辑器可打开")
	var levels = load(ROOT + "/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	check(levels.errors.is_empty(), "关卡配表可读")
	if OS.get_cmdline_user_args().has("--release-reopen"):
		check(levels.catalog.levels.size() == 1, "更新后保留用户关卡")
	else:
		check(levels.catalog.levels.is_empty(), "安装包不预装地图")
		EditorInterface.open_scene_from_path(ROOT + "/templates/empty_level.tscn")
		for i in 10: await get_tree().process_frame
		var path := USER + "/scenes/levels/native_install.tscn"
		EditorInterface.save_scene_as(path, false)
		check(FileAccess.file_exists(path), "Godot 原生另存场景")
		for i in 10: await get_tree().process_frame
		var saved = load(ROOT + "/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
		check(saved.catalog.levels.size() == 1, "原生保存同步任务索引")
		check(suite.level_panel.catalog.levels.size() == 1, "已打开的关卡与任务索引刷新")
		var level := load(path).instantiate() as Node
		check(level != null and not str(level.level_id).is_empty(), "原生关卡保存稳定 ID")
		if level != null: level.free()
		var id: String = str(saved.catalog.levels[0].level_id)
		var moved := USER + "/scenes/levels/renamed.tscn"
		check(DirAccess.rename_absolute(path, moved) == OK, "移动验证夹具")
		EditorInterface.get_file_system_dock().files_moved.emit(path, moved)
		var renamed = load(ROOT + "/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
		check(renamed.errors.is_empty() and str(renamed.catalog.by_id(id).scene_path) == moved, "文件移动回调保留 ID 并更新路径")
		check(DirAccess.rename_absolute(moved, path) == OK, "还原验证夹具")
		EditorInterface.get_file_system_dock().files_moved.emit(moved, path)
	var catalog = load(ROOT + "/modules/godot_level_editor/asset_catalog.gd")
	check(catalog.assets("常驻 NPC").size() == 13, "轮盘 NPC 素材")
	check(catalog.assets("常驻机关").size() == 5, "轮盘机关素材")
	if OS.get_cmdline_user_args().has("--release-visual"):
		EditorInterface.open_scene_from_path(USER + "/scenes/levels/native_install.tscn")
		suite.open_tab("关卡")
		for i in 10: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		suite.window.get_texture().get_image().save_png("res://release-editor.png")
		suite.open_tab("敌人")
		for i in 10: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		suite.window.get_texture().get_image().save_png("res://release-npcs.png")
	_finish()

func _finish() -> void:
	if OS.get_cmdline_user_args().has("--release-visual"):
		reparent(get_tree().root)
		EditorInterface.set_plugin_enabled("godot_level_editor", false)
		for i in 5: await get_tree().process_frame
		check(get_tree().get_nodes_in_group("godot_level_editor_suite_modules").is_empty(), "禁用主插件停用全部后端")
	print("RELEASE_SMOKE_RESULT: ", checks, " checks; ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
