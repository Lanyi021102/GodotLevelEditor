@tool
extends RefCounted
const ROOT := "res://addons/godot_level_editor"
const STORE := preload("res://addons/godot_level_editor/modules/enemy_editor/definition_store.gd")
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const IMPORT := preload("res://addons/godot_level_editor/modules/enemy_editor/model_import.gd")
var passed := 0
var failed := 0
var report: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	report.append({"ok": ok, "check": label})
	print("[PASS] " if ok else "[FAIL] ", label)

func frames(panel: Control, count := 8) -> void:
	for i in count: await panel.get_tree().process_frame

func run(panel: Control, _plugin: EditorPlugin) -> void:
	if not FileAccess.file_exists("res://.npc_structure_qa"):
		push_error("NPC structure QA requires its isolated project marker.")
		panel.get_tree().quit(2); return
	panel.get_tree().create_timer(90, true).timeout.connect(func(): panel.get_tree().quit(2))
	await frames(panel, 20)
	print("NPC_QA_USER_DIR: ", OS.get_user_data_dir())
	var suite: EditorPlugin = panel.get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
	suite.open_tab("敌人")
	var library: Control = suite.asset_panels["敌人"]
	library.reload_catalog()
	var builtin := ROOT + "/resources/enemies/samples_v1/human_medium_male.tres"
	var original := FileAccess.get_file_as_string(builtin)
	var original_hash := FileAccess.get_sha256(builtin)
	var original_uid := ResourceLoader.get_resource_uid(builtin)
	check(library.entries.has(builtin), "内置 NPC 出现在目录")
	library.select_asset(builtin); library.enter_edit(); await frames(panel)
	check(panel.file_path == builtin and panel.appearance_panel.visual != null, "内置素材可进入模型与动画编辑")
	panel._set_state("speed", 1.8)
	check(panel.dirty, "状态编辑形成草稿")
	panel.save(); await frames(panel, 2)
	check(FileAccess.get_sha256(builtin) == original_hash and panel.dirty, "内置素材保存不覆盖插件且保留草稿")
	check(panel.save_dialog.visible and panel.save_dialog.current_path.begins_with("res://content/"), "保存内置素材引导另存到个人目录")
	panel.save_dialog.hide()
	panel._save_to(builtin)
	check(FileAccess.get_sha256(builtin) == original_hash, "直接另存内置路径被拒绝")
	var direct_result := STORE.save_definition(panel.definition, builtin)
	check(direct_result == ERR_UNAUTHORIZED, "定义存储层阻止写入插件目录")
	# Before-fix reproduction runs only inside the isolated copy; restore its source.
	if FileAccess.get_sha256(builtin) != original_hash:
		var restore := FileAccess.open(builtin, FileAccess.WRITE); restore.store_string(original); restore.close()
	var path := "res://content/resources/enemies/structure_qa/personal_npc.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	panel._save_to(path)
	check(panel.file_path == path and not panel.dirty and FileAccess.file_exists(path), "草稿另存为个人 NPC")
	var personal_uid := ResourceLoader.get_resource_uid(path)
	check(personal_uid != ResourceUID.INVALID_ID and personal_uid != original_uid, "个人副本拥有独立 UID")
	panel._set_state("speed", 2.1); panel.save()
	check(ResourceLoader.get_resource_uid(path) == personal_uid, "原位保存保留个人资源 UID")
	panel._load(path)
	check(is_equal_approx(float(panel.definition.states[0].speed), 2.1), "状态图参数保存后重开保留")
	var appearance: Resource = panel.definition.appearance.duplicate(true)
	appearance.height = 2.6; panel._set_appearance(appearance); panel.save()
	panel._choose_npc_scene()
	check(panel.npc_scene_dialog.current_path.begins_with("res://content/scenes/npcs/"), "生成场景默认保存到个人 NPC 目录")
	panel.npc_scene_dialog.hide()
	var forbidden := ROOT + "/scenes/npcs/structure_qa_forbidden.tscn"
	check(not panel.create_npc_scene(forbidden) and not FileAccess.file_exists(forbidden), "生成 NPC 不允许写入插件目录")
	if FileAccess.file_exists(forbidden): DirAccess.remove_absolute(forbidden)
	var scene_path := "res://content/scenes/npcs/structure_qa_personal.tscn"
	DirAccess.make_dir_recursive_absolute(scene_path.get_base_dir())
	check(panel.create_npc_scene(scene_path), "生成可放置的个人 NPC 场景")
	var scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var npc := scene.instantiate() as Node3D
	check(npc.get("enemy_definition").resource_path == path, "生成场景引用个人定义")
	var shape: CapsuleShape3D = npc.get_node("Collision").shape
	check(is_equal_approx(shape.height, 2.6) and is_equal_approx(npc.get_node("Collision").position.y, 1.3), "生成碰撞与修改后的模型身高一致")
	check(npc.has_meta(PROFILE.META) and is_equal_approx(npc.get_meta(PROFILE.META).body_height, 2.6), "生成实例属性保存实际体型与行为定义")
	npc.free()
	var catalog := preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_catalog.gd")
	check(catalog.assets("常驻 NPC").any(func(row: Dictionary): return row.path == scene_path), "个人 NPC 可由原生轮盘发现")
	library.reload_catalog(); library.select_asset(path); library.enter_edit(); await frames(panel)
	check(library.entries.has(path) and panel.file_path == path, "个人 NPC 可由目录重开")
	var external := OS.get_user_data_dir().path_join("external")
	DirAccess.make_dir_recursive_absolute(external)
	var file := "Superhero_Male_FullBody.gltf"
	var source_dir := ROOT + "/assets/characters/quaternius_base"
	for source_file in DirAccess.get_files_at(source_dir):
		if source_file.get_extension() in ["gltf", "bin", "png"]: DirAccess.copy_absolute(ProjectSettings.globalize_path(source_dir.path_join(source_file)), external.path_join(source_file))
	var imported := IMPORT.prepare(external.path_join(file))
	check(not imported.has("error") and str(imported.get("path", "")).begins_with("res://content/assets/characters/npc_imports/"), "外部 glTF 与依赖复制到个人素材目录")
	if not imported.has("error"):
		var snapshot := IMPORT.scene_snapshot(imported.path, true)
		check(not snapshot.has("error") and str(snapshot.get("path", "")).begins_with("res://content/assets/characters/npc_imports/"), "导入快照保存在插件目录之外")
		if not snapshot.has("error"):
			check(panel.appearance_panel.apply_source(load(snapshot.path), "model"), "个人导入模型可应用到 NPC")
			panel.save()
			var snapshot_path: String = panel.definition.appearance.model.resource_path
			panel._load(path)
			check(panel.definition.appearance.model.resource_path == snapshot_path, "个人模型依赖随定义重开保持")
			check(panel.definition.appearance.motions.is_empty() and panel.appearance_panel.visual.pose_status == "T Pose", "可选动画留空后恢复 T Pose")
	check(FileAccess.get_sha256(builtin) == original_hash, "完整工作流未改写内置定义")
	print("PERSONAL BEFORE NATIVE: ", panel.definition.appearance.model.resource_path)
	var personal_hash := FileAccess.get_sha256(path)
	await native_workflow(panel, suite, _plugin)
	check(FileAccess.get_sha256(path) == personal_hash, "生成另一份 NPC 与原生试玩不改写已保存的个人导入定义")
	if OS.get_cmdline_user_args().has("--capture"):
		suite.window.size = Vector2i(1504, 1000)
		await frames(panel, 15)
		suite.window.get_texture().get_image().save_png("res://npc-structure-editor.png")
	var output := FileAccess.open("res://npc-structure-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": report, "user_dir": OS.get_user_data_dir(), "definition": path, "scene": scene_path}, "  ")); output.close()
	print("NPC STRUCTURE EDITOR: %d passed / %d failed" % [passed, failed])
	panel.get_tree().quit(0 if failed == 0 else 1)

func native_workflow(panel: Control, suite: EditorPlugin, enemy_plugin: EditorPlugin) -> void:
	# Preserve the external-import definition for update/reopen validation.
	panel._load(ROOT + "/resources/enemies/samples_v1/human_medium_male.tres")
	panel._save_to("res://content/resources/enemies/structure_qa/walking_npc.tres")
	var scene_path := "res://content/scenes/npcs/structure_qa_walking.tscn"
	check(panel.create_npc_scene(scene_path), "生成带行走动画的个人资源")
	EditorInterface.open_scene_from_path(scene_path); await frames(panel, 15)
	var actor := EditorInterface.get_edited_scene_root() as Node3D
	var scene_uid := ResourceLoader.get_resource_uid(scene_path)
	var collision: CollisionShape3D = actor.get_node("Collision")
	collision.shape = collision.shape.duplicate()
	collision.shape.radius = 0.42
	EditorInterface.save_scene_as(scene_path, false)
	var stored := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate() as Node3D
	check(is_equal_approx(stored.get_node("Collision").shape.radius, 0.42) and ResourceLoader.get_resource_uid(scene_path) == scene_uid, "原生碰撞编辑保存重读保留且场景 UID 不变")
	stored.free()
	EditorInterface.open_scene_from_path(ROOT + "/templates/empty_level.tscn"); await frames(panel, 15)
	var level_path := "res://content/scenes/levels/npc_structure_qa.tscn"
	EditorInterface.save_scene_as(level_path, false); await frames(panel)
	var root := EditorInterface.get_edited_scene_root() as Node3D
	EditorInterface.set_main_screen_editor("3D"); await frames(panel)
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var tool: RefCounted = suite.modules.level.radial_tool
	var catalog := preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_catalog.gd")
	tool.open_wheel(camera)
	check(tool.begin_asset(catalog.find_asset(scene_path)), "原生轮盘选择个人 NPC 进入放置")
	tool.update_preview(camera, camera.unproject_position(Vector3(0, 0, -2)))
	var placed: Node3D = tool.place(); tool.cancel()
	check(placed != null, "轮盘实际放置个人 NPC")
	if placed == null: return
	placed.name = "WalkingNPC"
	enemy_plugin.scene_guard = placed
	enemy_plugin._create_route(); await frames(panel)
	check(not placed.patrol_route.is_empty() and placed.get_node(placed.patrol_route).get_child_count() == 2, "编辑器创建可编辑巡逻 Marker3D")
	placed.get_node(placed.patrol_route).get_child(0).position = Vector3(-6, 0, 0)
	placed.get_node(placed.patrol_route).get_child(1).position = Vector3(6, 0, 0)
	var receiver := load(ROOT + "/scenes/narrative/npc.tscn").instantiate() as Node3D
	receiver.name = "DialogueNPC"; receiver.object_id = "qa_dialogue"; receiver.position = Vector3(3, 0, 2)
	root.add_child(receiver); receiver.owner = root
	root.level_logic.nodes.assign([{ "id": "start", "kind": "start", "params": {} }, { "id": "qa_interact", "kind": "npc_interact", "params": {"npc": "$world/qa_dialogue"} }])
	var probe := Node.new(); probe.name = "NPCQA"; probe.set_script(load("res://tools/enemy_editor/structure_qa/play_probe.gd"))
	root.add_child(probe); probe.owner = root
	EditorInterface.save_scene_as(level_path, false)
	var saved := ResourceLoader.load(level_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate() as Node3D
	var saved_actor := saved.find_child("WalkingNPC", true, false)
	check(saved_actor != null and saved_actor.get("enemy_definition").resource_path.begins_with("res://content/") and not saved_actor.get("patrol_route").is_empty(), "原生关卡保存重读保留个人模型、定义与路点")
	saved.free()
	# Native editor launch, rather than a substitute runtime SceneTree.
	var result_path := "res://npc-structure-play.json"
	if FileAccess.file_exists(result_path): DirAccess.remove_absolute(result_path)
	EditorInterface.play_custom_scene(level_path)
	for attempt in 300:
		if FileAccess.file_exists(result_path): break
		await panel.get_tree().create_timer(0.1, true).timeout
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path)) if FileAccess.file_exists(result_path) else null
	check(result is Dictionary and result.get("failed", 1) == 0, "原生 F6 试玩的移动、动画与原有对话全部通过")
	EditorInterface.stop_playing_scene()
	await frames(panel)
