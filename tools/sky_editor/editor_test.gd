@tool
extends RefCounted
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)
func frames(tree: SceneTree, count := 4) -> void:
	for i in count: await tree.process_frame
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(100).timeout.connect(func(): tree.quit(2))
	# Workspace construction precedes Godot's restoration of its active scene tab.
	await tree.create_timer(5.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await tree.process_frame
	var panel: Control = suite.sky_panel
	var original_scene := EditorInterface.get_edited_scene_root().scene_file_path if EditorInterface.get_edited_scene_root() != null else ""
	var source_path := "res://content/scenes/levels/whitebox_world.tscn"
	var original_bytes := FileAccess.get_file_as_bytes(source_path)
	var scene_path := source_path
	suite.open_tab("天空"); await frames(tree, 8)
	check(suite.navigation_buttons.has("天空") and suite.tabs.get_tab_count() >= 8, "sky editor integrated in unified window")
	check(panel.items.item_count >= 8 and panel.fields.has("cloud_height") and not panel.fields.has("cloud_sea"), "preset library and cloud-height controls without cloud-sea feature")
	panel.open_preset("res://addons/godot_level_editor/resources/sky_presets/builtin/clear.tres")
	panel.change("sun_mode", 0)
	var previous_elevation: float = panel.draft.elevation
	panel.change("elevation", 23)
	check(panel.draft.elevation == 23 and panel.dirty, "parameter editing tracks dirty draft")
	panel.open_preset(panel.selected_path)
	check(panel.draft.elevation == 23 and panel.dirty, "reselecting current preset preserves unsaved edits")
	panel.undo.undo(); check(is_equal_approx(panel.draft.elevation, previous_elevation), "parameter undo")
	panel.undo.redo(); check(panel.draft.elevation == 23, "parameter redo")
	panel.open_preset("res://addons/godot_level_editor/resources/sky_presets/builtin/night.tres")
	check(panel.selected_path.ends_with("clear.tres"), "unsaved draft protected when switching")
	panel.change("weather", 2)
	check(panel.draft.cloud_coverage == 1.0 and panel.draft.sun_energy == 0.4, "weather shortcut updates actual parameters")
	panel.undo.undo(); check(panel.draft.cloud_coverage == 0.25, "weather shortcut undoes as a group")
	panel.change("sun_mode", 1)
	check(not panel.fields.elevation.editable and panel.fields.hour.editable, "time and manual angle controls are mutually exclusive")
	panel.dirty = false; panel.open_preset(panel.LIBRARY.DEFAULT)
	EditorInterface.open_scene_from_path(scene_path)
	var open_deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < open_deadline:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == scene_path: break
		await tree.process_frame
	await frames(tree, 10)
	var world: Node = panel.current_world()
	if world == null:
		check(false, "editable world is available"); tree.quit(1); return
	var original_binding: Resource = world.sky_preset
	world.sky_preset = null; world.refresh_sky(); await frames(tree)
	check(world != null and world.sky_preset == null, "legacy level retains existing lighting until bound")
	panel.start_preview(); await frames(tree)
	check(panel.preview_active and world.sky_preset == null and world.sky_runtime.active_preset != null, "temporary preview leaves level binding unchanged")
	var packed := PackedScene.new(); packed.pack(world); ResourceSaver.save(packed, "user://sky_preview_test.tscn")
	check(not FileAccess.get_file_as_string("user://sky_preview_test.tscn").contains("SkyRuntime"), "saving during preview excludes generated nodes")
	panel.stop_preview(); await frames(tree)
	check(world.sky_runtime.active_preset == null, "ending preview restores legacy level")
	panel._preview_variant("neutral"); check(world.sky_runtime.active_preset != null and world.sky_runtime.active_preset.display_name == "中性白盒", "neutral inspection mode")
	if OS.get_cmdline_user_args().has("--capture"):
		DirAccess.make_dir_recursive_absolute("res://docs/sky_editor/validation")
		await frames(tree, 12); RenderingServer.force_draw(false)
		EditorInterface.get_editor_viewport_3d(0).get_texture().get_image().save_png("res://docs/sky_editor/validation/native_neutral.png")
		panel.open_preset("res://addons/godot_level_editor/resources/sky_presets/builtin/clear.tres"); panel.start_preview()
		await frames(tree, 12); RenderingServer.force_draw(false)
		EditorInterface.get_editor_viewport_3d(0).get_texture().get_image().save_png("res://docs/sky_editor/validation/native_preview.png")
	panel.stop_preview()
	var fixture := "res://content/resources/sky_presets/custom/.sky_test_" + str(OS.get_process_id()) + ".tres"
	DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	panel.duplicate_preset(); panel.change("display_name", "天空集成测试"); panel._save_to(fixture)
	check(not panel.dirty and FileAccess.file_exists(fixture), "custom preset saved as native resource")
	panel.bind_current(); await frames(tree)
	check(world.sky_preset != null and world.sky_preset.resource_path == fixture, "saved profile binds to world root")
	var history := suite.get_undo_redo(); var undo := history.get_history_undo_redo(history.get_object_history_id(world))
	undo.undo(); await frames(tree); check(world.sky_preset == null, "binding integrates with scene undo")
	undo.redo(); await frames(tree); check(world.sky_preset.resource_path == fixture, "binding redo")
	packed = PackedScene.new(); packed.pack(world); ResourceSaver.save(packed, "user://sky_bound_test.tscn")
	var restored: Node = load("user://sky_bound_test.tscn").instantiate()
	check(restored.sky_preset.resource_path == fixture, "binding survives scene save and reopen")
	restored.free()
	undo.undo(); await frames(tree)
	var warehouse: Control = suite.level_panel
	warehouse.select_level("1"); warehouse.show_form(true)
	check(warehouse.sky_picker != null and warehouse.sky_picker.item_count >= 9, "level information exposes sky binding picker")
	warehouse.form.hide()
	warehouse.show_form(false)
	check(str(warehouse.sky_picker.get_item_metadata(warehouse.sky_picker.selected)) == panel.LIBRARY.DEFAULT, "new level information defaults to the V2 sky preset")
	warehouse.form.hide()
	var image := Image.create(32, 16, false, Image.FORMAT_RGBF); image.fill(Color(0.25, 0.4, 0.8))
	var source := "user://sky_import_test.exr"; image.save_exr(source)
	await panel.import_hdri(ProjectSettings.globalize_path(source)); await frames(tree)
	check(panel.draft.sky_mode == 1 and panel.draft.hdri != null and panel.draft.hdri.resource_path.begins_with("res://content/assets/sky_hdri/"), "external EXR imported into portable project directory")
	var imported_path: String = panel.draft.hdri.resource_path
	panel._save_to(fixture)
	var saved_hdri: Resource = ResourceLoader.load(fixture, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved_hdri.hdri != null and saved_hdri.hdri.get_width() == 32 and saved_hdri.hdri.resource_path == imported_path, "saved HDRI preset retains portable texture reference after reload")
	panel.start_preview(); check(world.sky_runtime.environment.sky.sky_material is PanoramaSkyMaterial, "imported EXR renders in real preview environment")
	panel.stop_preview(); panel.dirty = false; panel.open_preset(panel.LIBRARY.DEFAULT)
	panel.duplicate_preset(); panel.change("display_name", "sky_external_save_test"); panel.save_external()
	var external_path: String = panel.selected_path
	check(not panel.dirty and external_path.begins_with(panel.LIBRARY.DIRECTORY + "/custom/") and FileAccess.file_exists(external_path), "native save-all saves new drafts as custom resources without modifying built-ins")
	panel.open_preset(panel.LIBRARY.DEFAULT)
	if OS.get_cmdline_user_args().has("--capture"):
		suite.window.size = Vector2i(1504, 1000); suite.open_tab("天空"); await frames(tree, 10)
		RenderingServer.force_draw(false)
		DirAccess.make_dir_recursive_absolute("res://docs/sky_editor/validation")
		suite.window.get_texture().get_image().save_png("res://docs/sky_editor/validation/editor.png")
		suite.window.size = Vector2i(1100, 760); await frames(tree, 10)
		check(panel.get_global_rect().end.x <= suite.window.size.x and panel.form.get_global_rect().end.x <= suite.window.size.x, "sky editor fits minimum window width")
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png("res://docs/sky_editor/validation/editor_narrow.png")
	check(FileAccess.get_file_as_bytes(source_path) == original_bytes, "user level file remains byte-identical after tests")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture + ".uid"))
	for path in [external_path, imported_path, imported_path + ".import"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	panel.reload_library()
	world.sky_preset = original_binding
	world.refresh_sky()
	if not original_scene.is_empty(): EditorInterface.open_scene_from_path(original_scene)
	await frames(tree, 8)
	print("SKY_EDITOR_RESULT checks=", checks, " failures=", failures)
	tree.quit(1 if failures else 0)
