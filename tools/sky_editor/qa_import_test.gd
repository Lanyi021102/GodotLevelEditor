@tool
extends RefCounted
const CLEAR := "res://addons/godot_level_editor/resources/sky_presets/builtin/clear.tres"
const NIGHT := "res://addons/godot_level_editor/resources/sky_presets/builtin/night.tres"
var checks := 0
var failures := 0
var serial := 0
var tree: SceneTree
var capture_dir := ""
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)
func frames(count := 3) -> void:
	for i in count: await tree.process_frame
func source_file(label: String) -> String:
	serial += 1
	var image := Image.create(32, 16, false, Image.FORMAT_RGBF)
	image.fill(Color(0.12 + serial * 0.01, 0.4, 0.7))
	var path := "user://qa09_" + label + "_" + str(serial) + ".exr"
	image.save_exr(path)
	return ProjectSettings.globalize_path(path)
func open_clear(panel: Control) -> void:
	panel.stop_preview(); panel.dirty = false; panel.open_preset(CLEAR)
	await frames(2)
func finished(panel: Control) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while panel._importing and Time.get_ticks_msec() < deadline: await tree.process_frame
	check(not panel._importing, "import returns to idle")
	if panel._importing:
		var fs := EditorInterface.get_resource_filesystem()
		print("QA09_WAIT_TIMEOUT inside=", panel.is_inside_tree(), " scanning=", fs.is_scanning(), " importing=", fs.is_importing(), " status=", panel.status.text)
		if panel.has_method("_finish_hdri_import"):
			panel._finish_hdri_import(panel._import_request, "QA 等待超时")
			panel._import_request += 1
		return false
	return not panel._importing
func action_enabled(panel: Control, text: String) -> bool:
	for control in panel.find_children("*", "Button", true, false):
		if control.text == text: return not control.disabled
	return false
func take_capture(suite: EditorPlugin, filename: String) -> void:
	if capture_dir.is_empty(): return
	await frames(2)
	print("QA09_CAPTURE ", filename, " importing=", suite.sky_panel._importing)
	RenderingServer.force_draw(false)
	suite.window.get_texture().get_image().save_png(capture_dir.path_join(filename))
func run(suite: EditorPlugin) -> void:
	tree = suite.get_tree()
	tree.create_timer(150).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(4).timeout
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await tree.process_frame
	print("QA09_USER_DATA ", OS.get_user_data_dir())
	check(OS.get_user_data_dir().replace("\\", "/").contains("CodexQA/GodotLevelEditor/"), "user data is isolated from the real project's saves")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa09-capture="): capture_dir = arg.trim_prefix("--qa09-capture=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	suite.open_tab("天空")
	var panel: Control = suite.sky_panel
	await open_clear(panel)
	var clear_hash := FileAccess.get_sha256(CLEAR)
	var night_hash := FileAccess.get_sha256(NIGHT)
	var original: Resource = panel.draft
	panel.import_hdri(source_file("switch"))
	check(panel._importing, "real EXR import suspends while filesystem scans")
	panel.open_preset(NIGHT)
	check(panel.draft == original and panel.selected_path == CLEAR, "QA-09: switching cannot replace importing draft")
	if OS.get_cmdline_user_args().has("--qa09-baseline"):
		await finished(panel)
		check(original.hdri != null, "QA-09: result belongs to initiating draft")
		check(not (panel.selected_path == NIGHT and panel.draft.hdri != null), "QA-09: night draft is not contaminated")
		print("QA09_BASELINE_RESULT checks=", checks, " failures=", failures)
		tree.quit(1 if failures else 0); return
	check(not action_enabled(panel, "新建") and not action_enabled(panel, "复制") and not action_enabled(panel, "还原") and not action_enabled(panel, "保存预设") and not action_enabled(panel, "导入 HDRI"), "target-changing buttons visibly disabled while importing")
	check(panel.items.is_item_disabled(0), "preset library selection disabled while importing")
	panel.reload_library()
	check(panel.items.is_item_disabled(0), "library refresh keeps import lock")
	panel.new_preset(); check(panel.draft == original and panel.selected_path == CLEAR and not panel.dirty, "new preset blocked during import")
	panel.duplicate_preset(); check(panel.draft == original and panel.selected_path == CLEAR and not panel.dirty, "duplicate blocked during import")
	panel.change("sun_energy", 3.7)
	panel.discard(); check(panel.draft == original and panel.dirty and panel.draft.sun_energy == 3.7, "discard preserves importing draft and existing edits")
	var save_path := "res://content/resources/sky_presets/custom/qa09_inflight.tres"
	panel._save_to(save_path); check(not FileAccess.file_exists(save_path) and panel.dirty, "file-dialog save callback blocked during import")
	panel.save(); panel.save_as(); panel.save_external()
	check(panel.selected_path == CLEAR and not panel.save_dialog.visible and panel.dirty, "save, save-as and native external-save do not change import target")
	panel.bind_current(); check(panel._importing and panel.status.text.contains("导入"), "binding blocked while preset import is pending")
	await take_capture(suite, "import_locked.png")
	await finished(panel)
	check(panel.draft == original and original.hdri != null and original.sky_mode == 1 and panel.dirty, "successful import writes only initiating draft")
	check(is_equal_approx(original.sun_energy, 3.7), "other parameter edits during import survive")
	check(action_enabled(panel, "新建") and action_enabled(panel, "保存预设") and action_enabled(panel, "导入 HDRI") and not panel.items.is_item_disabled(0), "successful import unlocks controls")
	panel.undo.undo(); check(original.hdri == null and original.sky_mode == 0, "import undo remains attached to original draft")
	panel.undo.redo(); check(original.hdri != null and original.sky_mode == 1, "import redo restores correct HDRI")
	await take_capture(suite, "import_completed.png")
	await open_clear(panel)
	var first_path := source_file("first_request")
	panel.import_hdri(first_path); panel.import_hdri(source_file("blocked_second"))
	await finished(panel)
	check(panel.draft.hdri != null and panel.draft.hdri.resource_path.get_file().begins_with(first_path.get_file().get_basename()), "second import cannot replace active request")

	# Use a real editor world; only transient previews are applied in the isolated copy.
	EditorInterface.open_scene_from_path("res://content/scenes/levels/whitebox_world.tscn")
	await tree.create_timer(0.4).timeout
	await open_clear(panel); panel.start_preview()
	check(panel.preview_active, "preview is active before testing end-preview during import")
	panel.import_hdri(source_file("stop_preview")); panel.stop_preview()
	check(panel._importing and not panel.preview_active, "ending preview leaves import owned by same draft")
	await finished(panel)
	check(panel.draft.hdri != null and not panel.preview_active, "completed import does not restart ended preview")
	await open_clear(panel); panel.start_preview(); panel.import_hdri(source_file("close_window"))
	suite._hide_window()
	check(not suite.window.visible and not panel.preview_active and panel._importing, "closing workspace hides preview without redirecting import")
	await finished(panel)
	check(panel.draft.hdri != null and not suite.window.visible and not panel.preview_active, "import completion neither reopens window nor restarts preview")
	suite.show_window()

	# Guard the completion path as well as today's UI actions.
	await open_clear(panel); original = panel.draft
	panel.import_hdri(source_file("identity_guard"))
	panel.draft = load(NIGHT).copy_preset(); panel.selected_path = NIGHT; panel.dirty = false; panel.undo.clear_history(); panel._build_fields()
	await finished(panel)
	check(panel.draft.hdri == null and panel.draft.sky_mode == 0 and not panel.dirty and original.hdri == null and panel.status.text.contains("取消"), "unexpected draft replacement cancels stale completion")
	check(action_enabled(panel, "新建"), "stale completion releases import lock")

	# Leaving the tree cancels the old request. It must not unlock or overwrite a newer one.
	await open_clear(panel); panel.import_hdri(source_file("old_request"))
	var parent := panel.get_parent(); var index := panel.get_index()
	parent.remove_child(panel)
	check(not panel._importing, "leaving tree clears import state")
	parent.add_child(panel); parent.move_child(panel, index)
	suite.open_tab("天空")
	var new_path := source_file("new_request")
	panel.import_hdri(new_path)
	await frames(1)
	check(panel._importing, "late cancelled callback cannot unlock newer request")
	await finished(panel)
	check(panel.draft.hdri != null and panel.draft.hdri.resource_path.get_file().begins_with(new_path.get_file().get_basename()), "new request survives cancelled predecessor")

	for kind in ["extension", "missing", "empty", "malformed"]:
		await open_clear(panel); original = panel.draft
		var bad_path := ProjectSettings.globalize_path("user://qa09_" + kind + (".png" if kind == "extension" else ".exr"))
		if kind in ["empty", "malformed"]:
			var file := FileAccess.open(bad_path, FileAccess.WRITE)
			if kind == "malformed": file.store_string("not an EXR image")
			file.close()
		print("QA09_EXPECTED_BAD_INPUT_BEGIN ", kind)
		await panel.import_hdri(bad_path)
		print("QA09_EXPECTED_BAD_INPUT_END ", kind)
		check(not panel._importing and panel.draft == original and original.hdri == null and not panel.dirty, kind + " input restores idle without mutating draft")
		check(action_enabled(panel, "新建") and action_enabled(panel, "导入 HDRI"), kind + " input unlocks controls")
		panel.new_preset(); check(panel.draft != original, kind + " failure allows a new draft immediately")
		await frames(2)
	await open_clear(panel); panel.import_hdri(source_file("after_errors")); await finished(panel)
	check(panel.draft.hdri != null, "valid import works after bad inputs")

	var fault: Control = load("res://tools/sky_editor/qa_import_failure_panel.gd").new(); fault.suite = suite; suite.tabs.add_child(fault)
	await frames(2)
	fault.import_hdri("user://qa09_injected_failure.exr")
	check(fault._importing, "asynchronous failure injection reaches suspended state")
	await finished(fault)
	check(fault.status.text.contains("QA 异步导入失败") and fault.draft.hdri == null and action_enabled(fault, "新建"), "asynchronous failure unlocks controls and preserves draft")
	fault.new_preset(); check(fault.dirty, "new draft works after asynchronous failure")
	fault.undo.free(); fault.queue_free(); await frames()
	await open_clear(panel)
	check(FileAccess.get_sha256(CLEAR) == clear_hash and FileAccess.get_sha256(NIGHT) == night_hash, "built-in preset files stay byte-identical")
	print("QA09_IMPORT_RESULT checks=", checks, " failures=", failures)
	tree.quit(1 if failures else 0)
