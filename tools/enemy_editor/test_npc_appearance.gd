@tool
extends RefCounted
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(panel: Control, count := 8) -> void:
	for i in count: await panel.get_tree().process_frame
func run(panel: Control, _plugin: EditorPlugin) -> void:
	await frames(panel, 15)
	var suite := panel.get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
	suite.open_tab("敌人")
	var workspace: Control = suite.asset_panels["敌人"]
	workspace.select_asset("res://addons/godot_level_editor/resources/enemies/samples_v1/human_medium_male.tres"); workspace.enter_edit()
	await frames(panel)
	panel._load(panel.TEMPLATE_PATH)
	var appearance: Control = panel.appearance_panel
	check(panel.workspaces.current_tab == 0 and appearance.is_visible_in_tree(), "NPC 编辑打开模型与动画页")
	var model := load("res://addons/godot_level_editor/assets/characters/quaternius_base/adapted_human.tscn") as PackedScene
	check(appearance.apply_source(model, "model") and panel.dirty, "模型导入进入草稿并显示骨骼")
	check(appearance.visual.pose_status == "T Pose" and panel.definition.appearance.motions.is_empty(), "导入后动画默认留空，预览实际为 T Pose")
	var signature: String = panel._signature()
	panel.history.undo()
	check(panel.definition.appearance == null and appearance.data == null and appearance.visual == null, "模型导入可撤销，预览同步恢复旧定义")
	panel.history.redo()
	check(panel._signature() == signature and appearance.data == panel.definition.appearance, "重做恢复模型与骨骼预览")
	var original: Resource = panel.definition.appearance
	var bad := PackedScene.new(); var wrong := Node.new(); wrong.name = "Invalid2D"; bad.pack(wrong); wrong.free()
	check(not appearance.apply_source(bad, "model") and panel.definition.appearance == original, "无效导入保留原模型草稿")
	check(appearance.apply_source(model, "skeleton"), "可从文件导入匹配骨骼")
	check(appearance.apply_source(load("res://addons/godot_level_editor/assets/characters/quaternius_base/UAL1_Standard.glb"), "animation") and appearance.options.size() > 8, "动画来源可选添加，添加不自动绑定动作")
	var candidate: Resource = panel.definition.appearance.duplicate(true)
	for motion in appearance.options:
		if motion.clip == "Idle": candidate.motions.idle = motion; break
	check(appearance._commit(candidate) and appearance.visual.play("idle"), "选择动画后预览实际播放")
	var definition_path := "res://content/resources/enemies/npc_import_test.tres"
	panel._save_to(definition_path)
	check(not panel.dirty, "保存包含模型动画的 NPC 并清除草稿标记")
	panel._load(definition_path)
	check(not panel.dirty and panel.definition.appearance.motions.has("idle"), "重新打开保留模型骨骼和已选动作")
	var scene_path := "res://addons/godot_level_editor/scenes/npcs/npc_import_test.tscn"
	check(panel.create_npc_scene(scene_path), "生成可放进关卡的 NPC 素材")
	check(not panel.create_npc_scene(scene_path), "生成素材拒绝覆盖已有场景")
	var scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var npc := scene.instantiate(); check(npc.enemy_definition.resource_path == definition_path, "生成的 NPC 引用已保存定义")
	check(npc.get_node("ModelRoot").get_script() == preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd") and npc.get_node("ModelRoot").npc_definition == npc.enemy_definition, "生成素材在原生三维编辑器引用同一模型定义")
	var native_preview := Node3D.new(); panel.get_tree().root.add_child(native_preview); native_preview.add_child(npc)
	await frames(panel, 3)
	check(npc.get_node("ModelRoot").model != null and npc.get_node("ModelRoot").model.find_children("*", "MeshInstance3D", true, false).size() >= 3, "生成素材在三维编辑状态实际加载模型网格")
	native_preview.free()
	# Use the external glTF entry point, including adjacent .bin and textures.
	var external := "/tmp/branch-npc-external-" + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(external)
	var source_dir := "res://addons/godot_level_editor/assets/characters/quaternius_base"
	for file in DirAccess.get_files_at(source_dir):
		if file.get_extension() in ["gltf", "bin", "png"]: DirAccess.copy_absolute(ProjectSettings.globalize_path(source_dir.path_join(file)), external.path_join(file))
	appearance.import_kind = "model"
	await appearance.import_file(external.path_join("Superhero_Male_FullBody.gltf"))
	check(panel.definition.appearance.model.resource_path.begins_with("res://addons/godot_level_editor/assets/characters/npc_imports/") and appearance.visual.skeleton != null, "从项目外导入 glTF 时复制模型、二进制和贴图依赖")
	check(appearance.visual.model.find_children("*", "MeshInstance3D", true, false).size() >= 3 and appearance.visual.model.find_children("*", "ImporterMeshInstance3D", true, false).is_empty(), "导入场景包含可渲染网格，不残留编辑器中间网格")
	check(panel.definition.appearance.motions.is_empty() and not appearance.visual.anim.is_playing(), "更换模型后清除旧动作绑定并保持静止")
	if OS.get_cmdline_user_args().has("--capture"):
		appearance.bones_toggle.button_pressed = true
		await frames(panel, 35)
		var output := "res://docs/enemy_editor/model_import_2026-11-15"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		var image: Image = suite.window.get_texture().get_image()
		check(image.save_png(output.path_join("模型与骨骼.png")) == OK, "实际渲染 NPC 模型、骨骼和可选动画页面")
		suite.window.size = Vector2i(1100, 760); await frames(panel, 15)
		check(appearance.fields.size.x >= 300 and appearance.viewport.get_parent().size.x >= 340, "最小窗口保留预览和完整设置区域")
		suite.window.get_texture().get_image().save_png(output.path_join("窄窗口.png"))
	panel._load("res://addons/godot_level_editor/resources/enemies/samples_v1/human_medium_male.tres")
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning() or filesystem.is_importing(): await panel.get_tree().process_frame
	for path in [definition_path, scene_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("NPC APPEARANCE: %d passed / %d failed" % [passed, failed])
	panel.get_tree().quit(1 if failed else 0)
