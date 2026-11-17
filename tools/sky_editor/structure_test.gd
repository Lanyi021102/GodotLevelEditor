@tool
extends RefCounted
const LIBRARY := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/library.gd")
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const SCENE := "res://content/scenes/levels/sky_qa_inherited.tscn"
const SAVED_AS := "res://content/scenes/levels/sky_qa_renamed.tscn"
const CUSTOM := "res://content/resources/sky_presets/custom/sky_structure_qa.tres"
var tree: SceneTree
var checks := 0
var failures := 0
var result_prefix := "SKY_STRUCTURE_RESULT"
func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", title)
func frames(count := 5) -> void:
	for i in count: await tree.process_frame
func open_scene(path: String) -> Node:
	EditorInterface.open_scene_from_path(path)
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path:
			await frames(8)
			return root
		await tree.process_frame
	return null
func run(suite: EditorPlugin) -> void:
	tree = suite.get_tree()
	if not OS.get_user_data_dir().replace("\\", "/").contains("CodexQA/GodotLevelEditor/"):
		push_error("天空保存检查必须通过 tools/sky_editor/run_structure_test.py 在隔离工程中运行。")
		tree.quit(1)
		return
	tree.create_timer(120).timeout.connect(func(): EditorInterface.stop_playing_scene(); tree.quit(2))
	await tree.create_timer(5).timeout
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await tree.process_frame
	suite.open_tab("天空")
	var panel: Control = suite.sky_panel
	var baseline_hash := FileAccess.get_sha256(LIBRARY.DEFAULT)
	var authored := "res://content/scenes/levels/dusk_mountain_house.tscn"
	var authored_hash := FileAccess.get_sha256(authored) if FileAccess.file_exists(authored) else ""
	if not authored_hash.is_empty():
		var source := await open_scene(authored)
		check(source != null and source.sky_preset != null and source.sky_preset.display_name == "暖色黄昏", "migrated authored map retains sky reference")
		panel.open_preset(source.sky_preset.resource_path)
		check(panel.references.text.contains("黄昏山居"), "migrated level appears in used-by list")
	panel.open_preset(LIBRARY.DEFAULT)
	check(panel.items.item_count >= 8 and panel.category_tabs.get_tab_count() == 5, "plugin library and five editable categories available")
	panel.duplicate_preset()
	panel.fields.display_name.text = "天空流程检查"
	panel.fields.display_name.text_changed.emit("天空流程检查")
	panel.save()
	check(panel.save_dialog.visible and panel.save_dialog.current_dir == LIBRARY.CUSTOM, "Save button opens project custom directory")
	panel.save_dialog.canceled.emit(); panel.save_dialog.hide()
	check(panel.dirty and panel.selected_path.is_empty(), "canceling save retains unsaved draft")
	panel.save_as(); panel.save_dialog.file_selected.emit(CUSTOM); panel.save_dialog.hide()
	check(FileAccess.file_exists(CUSTOM) and not panel.dirty and panel.selected_path == CUSTOM, "save dialog stores duplicate outside plugin")
	panel.reload_library(); panel.open_preset(LIBRARY.DEFAULT); panel.open_preset(CUSTOM)
	check(panel.draft.display_name == "天空流程检查", "refresh and reopen recover custom preset")
	check(FileAccess.get_sha256(LIBRARY.DEFAULT) == baseline_hash, "built-in preset stays byte identical")
	var file := FileAccess.open(SCENE, FileAccess.WRITE)
	file.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="res://addons/godot_level_editor/templates/empty_level.tscn" id="base"]\n[ext_resource type="Script" path="res://tools/sky_editor/structure_play_probe.gd" id="probe"]\n\n[node name="SkyFlowCheck" instance=ExtResource("base")]\n\n[node name="SkyQAProbe" type="Node" parent="."]\nscript = ExtResource("probe")\n')
	file.close(); EditorInterface.get_resource_filesystem().update_file(SCENE)
	var inherited := LIBRARY.bound_preset(SCENE)
	check(inherited != null and inherited.resource_path == LIBRARY.DEFAULT, "inherited map resolves template sky without root override")
	var chain := "res://content/scenes/levels/sky_qa_chain.tscn"
	file = FileAccess.open(chain, FileAccess.WRITE)
	file.store_string('[gd_scene format=3]\n[ext_resource type="PackedScene" path="' + SCENE + '" id="base"]\n[node name="SkyChain" instance=ExtResource("base")]\n')
	file.close()
	inherited = LIBRARY.bound_preset(chain)
	check(inherited != null and inherited.resource_path == LIBRARY.DEFAULT, "nested inheritance resolves the original template sky")
	var world := await open_scene(SCENE)
	if world == null:
		check(false, "native inherited scene opens"); tree.quit(1); return
	check(world.scene_file_path == SCENE and world.scene_file_path.begins_with("res://content/"), "native inherited scene opens outside plugin")
	world.sky_preset = null
	EditorInterface.mark_scene_as_unsaved()
	check(EditorInterface.save_scene() == OK, "native Save supports clearing an inherited sky")
	check(LIBRARY.bound_preset(SCENE) == null and LIBRARY.bound_preset(chain) == null, "explicit empty binding overrides inherited sky")
	panel.bind_current()
	check(world.sky_preset != null and world.sky_preset.resource_path == CUSTOM, "saved custom sky binds through panel action")
	check(EditorInterface.save_scene() == OK, "native Save commits scene binding")
	await frames(15)
	var saved_binding := LIBRARY.bound_preset(SCENE)
	check(saved_binding != null and saved_binding.resource_path == CUSTOM, "saved inherited scene stores sky override")
	check(panel.references.text.contains("sky_qa_inherited"), "native save immediately refreshes used-by level list")
	var registered: Dictionary = LEVELS.load_book().catalog.for_world(world)
	check(not registered.is_empty() and str(registered.scene_path) == SCENE, "native save registers stable task level ID")
	EditorInterface.save_scene_as(SAVED_AS, false)
	await frames(15)
	check(EditorInterface.get_edited_scene_root() == world and world.scene_file_path == SAVED_AS and panel.visible and panel.references.text.contains("sky_qa_renamed"), "Save As refreshes used-by immediately while sky stays open")
	registered = LEVELS.load_book().catalog.for_world(world)
	check(not registered.is_empty() and str(registered.scene_path) == SAVED_AS and LIBRARY.bound_preset(SAVED_AS).resource_path == CUSTOM, "Save As indexes the new native scene with its sky binding")
	EditorInterface.close_scene(); await tree.create_timer(0.5).timeout
	world = await open_scene(SAVED_AS)
	check(world != null and world.sky_preset != null and world.sky_preset.resource_path == CUSTOM, "native close and reopen retain custom binding")
	var saved_hash := FileAccess.get_sha256(SAVED_AS)
	panel.start_preview(); panel.change("sun_energy", 1.23)
	check(panel.preview_active and world.sky_runtime.active_preset.sun_energy == 1.23 and not is_equal_approx(world.sky_preset.sun_energy, 1.23), "live draft edits preview without modifying binding")
	panel._preview_variant("neutral")
	check(world.sky_runtime.active_preset.display_name == "中性白盒", "neutral inspection uses temporary environment")
	panel._preview_variant("bound")
	check(world.sky_runtime.active_preset.display_name == "天空流程检查", "compare restores saved sky")
	panel.stop_preview(); panel.discard()
	check(not panel.preview_active and FileAccess.get_sha256(SAVED_AS) == saved_hash, "end preview preserves saved scene bytes")
	var image := Image.create(32, 16, false, Image.FORMAT_RGBF); image.fill(Color(0.2, 0.35, 0.7))
	var hdri := "user://sky_structure.exr"; image.save_exr(hdri)
	await panel.import_hdri(ProjectSettings.globalize_path(hdri))
	check(panel.dirty and panel.draft.hdri != null and panel.draft.hdri.resource_path.begins_with("res://content/assets/sky_hdri/"), "fresh EXR imports into project assets")
	panel.save()
	var reloaded := ResourceLoader.load(CUSTOM, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded.hdri != null and reloaded.hdri.get_width() == 32, "saved preset reloads imported EXR")
	check(EditorInterface.save_scene() == OK, "native save works after HDRI update")
	await frames(10)
	EditorInterface.close_scene(); await tree.create_timer(0.5).timeout
	world = await open_scene(SAVED_AS)
	check(world.sky_preset.hdri != null and world.sky_preset.hdri.get_width() == 32, "reopened inherited map resolves saved HDRI")
	panel.change("sky_energy", 1.37); suite._save_external_data()
	check(not panel.dirty and is_equal_approx(ResourceLoader.load(CUSTOM, "", ResourceLoader.CACHE_MODE_IGNORE).sky_energy, 1.37), "native external-data save persists existing custom draft")
	var marker := "user://sky-structure-play.json"
	if FileAccess.file_exists(marker): DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
	panel.start_preview()
	EditorInterface.play_current_scene()
	var deadline := Time.get_ticks_msec() + 60000
	while not FileAccess.file_exists(marker) and Time.get_ticks_msec() < deadline: await tree.create_timer(0.1).timeout
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker)) if FileAccess.file_exists(marker) else {}
	print("SKY_STRUCTURE_F6 playing=", EditorInterface.is_playing_scene(), " data=", data)
	check(EditorInterface.is_playing_scene() and data is Dictionary and data.get("scene") == SAVED_AS and data.get("binding") == CUSTOM and data.get("hdri", false) and data.get("valid", false) and data.get("player", false), "F6 runs reopened map with HDRI and default player")
	check(not panel.preview_active, "F6 ends temporary editor preview")
	EditorInterface.stop_playing_scene(); await tree.create_timer(1).timeout
	# Also cover the first native Save As of a genuinely unsaved inherited map.
	EditorInterface.open_scene_from_path("res://addons/godot_level_editor/templates/empty_level.tscn", true)
	await frames(15)
	var created := EditorInterface.get_edited_scene_root()
	check(created != world and created.has_method("preview_sky"), "native inherited-scene command creates a new editable map")
	var created_path := "res://content/scenes/levels/sky_qa_created.tscn"
	EditorInterface.save_scene_as(created_path, false)
	await frames(15)
	var created_row: Dictionary = LEVELS.load_book().catalog.for_world(created)
	check(created.scene_file_path == created_path and not created_row.is_empty() and str(created_row.scene_path) == created_path and FileAccess.get_file_as_string(created_path).contains("templates/empty_level.tscn"), "first native Save As retains inheritance and registers its final path")
	panel.bind_current(); EditorInterface.save_scene(); await frames(15)
	check(panel.visible and panel.references.text.contains("sky_qa_created") and LIBRARY.bound_preset(created_path).resource_path == CUSTOM, "new inherited map binding refreshes references without reopening sky")
	suite.open_tab("关卡"); suite.level_panel.set_mode(1); await frames(10)
	var sky_info: Label = suite.level_panel.get("sky_info")
	check(sky_info != null and sky_info.text.contains("天空流程检查"), "current native level information shows its bound sky")
	suite.open_tab("天空")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sky-structure-capture="):
			preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/ui_motion.gd").enabled = false
			suite.display_adapter.set_user_scale(1.0); suite.window.size = Vector2i(1400, 950)
			panel.open_preset("res://addons/godot_level_editor/resources/sky_presets/builtin/sunset.tres"); panel.set_category("时间与太阳")
			await frames(10); RenderingServer.force_draw(false)
			suite.window.get_texture().get_image().save_png(arg.trim_prefix("--sky-structure-capture=").path_join("binding.png"))
	check(authored_hash.is_empty() or FileAccess.get_sha256(authored) == authored_hash, "migrated author map remains byte identical")
	check(FileAccess.get_sha256(LIBRARY.DEFAULT) == baseline_hash, "workflow never overwrites shipped preset")
	panel.dirty = false
	print(result_prefix, " checks=", checks, " failures=", failures)
	tree.quit(1 if failures else 0)
