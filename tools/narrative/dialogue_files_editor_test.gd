@tool
extends EditorPlugin
const PANEL := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/dialogue_panel.gd")
const LIBRARY := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd")
const XLSX := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/xlsx.gd")
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")
const DATA := "res://qa_dialogue_files"
var panel: Control
var checks := 0
var failures := 0
var popups := 0
var capture_dir := ""
var window: Window

func _enter_tree() -> void:
	get_tree().create_timer(60, true).timeout.connect(func(): get_tree().quit(2))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)

func frames(count := 4) -> void:
	for i in count: await get_tree().process_frame

func capture(name_text: String) -> void:
	if capture_dir.is_empty(): return
	await frames()
	await RenderingServer.frame_post_draw
	check(window.get_texture().get_image().save_png(capture_dir + "/" + name_text + ".png") == OK, "native editor render: " + name_text)

func select_file(path: String, mode: String) -> void:
	panel._mode = mode
	panel.file.hide()
	panel.file.file_selected.emit(path)

func fixture(name_text: String) -> Resource:
	var library := LIBRARY.new()
	library.xlsx_path = DATA + "/" + name_text + ".xlsx"
	library.speakers = {"接待员": Color("6699cc")}
	library.next_line_id = 23
	library.groups.assign([{"id": "group_" + name_text, "name": name_text, "comments": [{"id": "comment_" + name_text, "name": "进入", "lines": [
		{"id": "00021", "speaker": "接待员", "text": "你好，\"测试\"。\n第二行", "type": "对白", "duration": 1.5},
		{"id": "00022", "speaker": "接待员", "text": "请继续。", "type": "引导", "duration": 0.0}
	]}]}])
	return library

func snapshot() -> Dictionary:
	return {"library": panel.library, "state": panel._state(), "path": panel.library.xlsx_path,
		"source": panel.library.get_meta("source_path", ""), "counter": panel.library.next_line_id,
		"dirty": panel.dirty, "export_dirty": panel.export_dirty, "undo": panel.undo.get_version()}

func unchanged(before: Dictionary) -> bool:
	return panel.library == before.library and panel._state() == before.state and panel.library.xlsx_path == before.path \
		and panel.library.get_meta("source_path", "") == before.source and panel.library.next_line_id == before.counter \
		and panel.dirty == before.dirty and panel.export_dirty == before.export_dirty and panel.undo.get_version() == before.undo

func _run() -> void:
	# The runner builds a separate minimal editor project; never enable this in the working project.
	if ProjectSettings.get_setting("application/config/name", "") != "DialogueFilesQA":
		push_error("Run this test through tools/narrative/run_dialogue_files_qa.py in its isolated project.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(DATA)
	var protected := {}
	for path in ["res://content/tables/dialogues.xlsx", "res://content/resources/narrative/reception.dialogue.tres"]:
		protected[path] = FileAccess.get_sha256(path)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-capture-dir="): capture_dir = argument.trim_prefix("--qa-capture-dir=")
	panel = PANEL.new()
	var host := PanelContainer.new(); host.theme = STYLE.theme()
	host.add_theme_stylebox_override("panel", STYLE.box(STYLE.BACKGROUND, 0, 12))
	if capture_dir.is_empty(): EditorInterface.get_editor_main_screen().add_child(host)
	else:
		window = Window.new(); window.hide(); window.title = "Dialogue Files QA"; window.force_native = true
		window.size = Vector2i(1200, 760); window.theme = host.theme
		EditorInterface.get_base_control().add_child(window)
		window.add_child(host); window.show()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(panel)
	panel.file.about_to_popup.connect(func(): popups += 1)
	await frames()
	check(panel.library != null and panel.library.validate().is_empty(), "initial workbook loads in the editor")
	var initial: Resource = panel.library
	var imported := fixture("QA_IMPORTED_WORKBOOK")
	check(imported.write_xlsx(imported.xlsx_path).is_empty(), "valid XLSX fixture is written only in the QA project")
	var another := fixture("QA_OTHER_WORKBOOK")
	check(another.write_xlsx(another.xlsx_path).is_empty(), "second XLSX fixture is independent")

	panel._new()
	var draft: Resource = panel.library
	var before_cancel := snapshot()
	panel.save()
	check(panel.file.visible and panel._mode == "save", "new dialogue opens the first-save picker")
	panel.file.hide(); panel.file.canceled.emit()
	check(unchanged(before_cancel), "canceling first save preserves the draft and its IDs")
	var target := DATA + "/new_dialogue.xlsx"
	panel.save()
	var first_popup_count := popups
	select_file(target, "save")
	await frames()
	check(FileAccess.file_exists(target), "QA-03 first Save Dialogues creates the selected XLSX")
	check(panel.library == draft and panel.library.xlsx_path == target and panel.library.get_meta("source_path", "") == target, "first save binds both save paths to the selected file")
	check(not panel.dirty and not panel.export_dirty and not panel.file.visible and popups == first_popup_count, "first save completes without reopening the picker")
	await capture("first_save")
	var saved := LIBRARY.read_xlsx(target)
	check(saved.library != null and saved.library.export_signature() == panel.library.export_signature(), "first-saved XLSX roundtrips the authored content")
	panel.add_line()
	panel.file.hide()
	var second_popup_count := popups
	panel.save()
	await frames()
	saved = LIBRARY.read_xlsx(target)
	check(popups == second_popup_count and not panel.file.visible and not panel.dirty, "second Save Dialogues writes directly without another picker")
	check(saved.library != null and saved.library.groups[0].comments[0].lines.size() == 2, "second save persists subsequent edits")

	panel.dirty = false
	panel._new()
	var before_failure := snapshot()
	select_file(DATA + "/missing_parent/failed.xlsx", "save")
	check(unchanged(before_failure) and not panel.status.text.is_empty(), "failed first save preserves the unbound draft and reports an error")
	check(not FileAccess.file_exists(DATA + "/missing_parent/failed.xlsx"), "failed first save creates no partial target")
	panel.dirty = false
	panel.open_library(initial)
	select_file(imported.xlsx_path, "open")
	check(panel.library.export_signature() == imported.export_signature() and panel.library.groups[0].name == "QA_IMPORTED_WORKBOOK", "QA-04 Open Dialogues loads a valid XLSX through the file callback")
	check(panel.library.xlsx_path == imported.xlsx_path and panel.library.get_meta("source_path", "") == imported.xlsx_path and not panel.dirty, "opening XLSX binds the save target and clean state")
	check(panel.library.groups[0].comments[0].lines[0].id == "00021" and panel.library.groups[0].comments[0].lines[0].text.contains("\n"), "XLSX opening preserves leading-zero IDs and multiline Unicode")
	await capture("open_xlsx")
	var upper_path := DATA + "/UPPER.XLSX"
	DirAccess.copy_absolute(imported.xlsx_path, upper_path)
	select_file(upper_path, "open")
	check(panel.library.xlsx_path == upper_path and panel.library.export_signature() == imported.export_signature(), "XLSX extension dispatch is case insensitive")

	var missing_sheet := DATA + "/wrong_schema.xlsx"
	XLSX.write_book(missing_sheet, {"其他": [["key"], ["value"]]})
	var bad_version := DATA + "/wrong_version.xlsx"
	var sheets: Dictionary = imported.workbook_sheets()
	sheets["配置"][1][1] = "999"
	XLSX.write_book(bad_version, sheets)
	var corrupt := DATA + "/corrupt.xlsx"
	var file := FileAccess.open(corrupt, FileAccess.WRITE); file.store_string("not an OOXML archive"); file.close()
	for bad_path in [missing_sheet, bad_version, corrupt, DATA + "/absent.xlsx", DATA + "/unsupported.csv"]:
		var before_bad := snapshot()
		panel.status.text = ""
		select_file(bad_path, "open")
		check(unchanged(before_bad), "failed open preserves library, flags and undo: " + bad_path.get_file())
		check(not panel.status.text.is_empty(), "failed open has a visible error: " + bad_path.get_file())
		if bad_path == missing_sheet: await capture("open_error_preserves_dialogue")

	panel.add_line()
	var dirty_draft := snapshot()
	select_file(another.xlsx_path, "open")
	check(unchanged(dirty_draft) and panel.status.text.contains("保存"), "file selection cannot replace a draft edited after opening the picker")
	var dirty_popup_count := popups
	panel._open(); panel._new()
	check(unchanged(dirty_draft) and popups == dirty_popup_count, "Open and New retain the existing dirty-draft protection")
	select_file(DATA + "/missing_parent/export.xlsx", "export")
	check(unchanged(dirty_draft) and not panel.status.text.is_empty(), "failed export retains the current save target and draft")
	var export_path := DATA + "/exported.xlsx"
	select_file(export_path, "export")
	check(FileAccess.file_exists(export_path) and panel.library.xlsx_path == export_path and not panel.dirty, "Export Dialogues remains supported")

	var legacy := LIBRARY.new(); legacy.schema_version = 1
	legacy.speakers = {"旧角色": Color("ddaa55")}
	legacy.groups.assign([{"id": "legacy_comment", "name": "旧台本", "lines": [{"id": "legacy_001", "speaker": "旧角色", "text": "旧版对白", "type": "对白"}]}])
	var legacy_path := DATA + "/legacy_v1.tres"
	check(ResourceSaver.save(legacy, legacy_path) == OK, "legacy v1 resource fixture is written")
	var legacy_hash := FileAccess.get_sha256(legacy_path)
	select_file(legacy_path, "open")
	check(panel.library.schema_version == LIBRARY.VERSION and not panel.library.comment_by_id("legacy_comment").is_empty() and panel.library.comment_by_id("legacy_comment").lines[0].id == "legacy_001", "legacy TRES migration preserves comment and dialogue IDs")
	check(panel.dirty and panel.library.xlsx_path.is_empty() and panel.library.get_meta("source_path", "") == legacy_path, "legacy migration requests a new XLSX target instead of the default workbook")
	select_file(DATA + "/legacy_migrated.xlsx", "save")
	saved = LIBRARY.read_xlsx(DATA + "/legacy_migrated.xlsx")
	check(saved.library != null and not saved.library.comment_by_id("legacy_comment").is_empty() and FileAccess.get_sha256(legacy_path) == legacy_hash, "legacy migration saves to XLSX without rewriting TRES")
	var current_legacy := fixture("legacy_v2")
	var current_path := DATA + "/legacy_v2.tres"
	ResourceSaver.save(current_legacy, current_path)
	select_file(current_path, "open")
	check(panel.library.export_signature() == current_legacy.export_signature() and panel.library.xlsx_path.is_empty(), "current-schema TRES remains importable as a legacy authoring source")
	var wrong_resource := DATA + "/other_resource.tres"
	ResourceSaver.save(Resource.new(), wrong_resource)
	var invalid := fixture("invalid"); invalid.schema_version = 999
	var invalid_path := DATA + "/invalid_version.tres"; ResourceSaver.save(invalid, invalid_path)
	var missing_name := fixture("missing_name"); missing_name.groups[0].erase("name")
	var missing_name_path := DATA + "/missing_group_name.tres"; ResourceSaver.save(missing_name, missing_name_path)
	var missing_comment_name := fixture("missing_comment_name"); missing_comment_name.groups[0].comments[0].erase("name")
	var missing_comment_path := DATA + "/missing_comment_name.tres"; ResourceSaver.save(missing_comment_name, missing_comment_path)
	var bad_legacy := LIBRARY.new(); bad_legacy.schema_version = 1; bad_legacy.groups.assign([{"name": "缺少 ID", "lines": []}])
	var bad_legacy_path := DATA + "/invalid_legacy_group.tres"; ResourceSaver.save(bad_legacy, bad_legacy_path)
	var bad_line := LIBRARY.new(); bad_line.schema_version = 1; bad_line.groups.assign([{"id": "legacy", "name": "旧台本", "lines": [12]}])
	var bad_line_path := DATA + "/invalid_legacy_line.tres"; ResourceSaver.save(bad_line, bad_line_path)
	var duplicate := fixture("duplicate"); duplicate.groups[0].comments[0].lines[1].id = "00021"
	var duplicate_path := DATA + "/duplicate_ids.tres"; ResourceSaver.save(duplicate, duplicate_path)
	for bad_path in [wrong_resource, invalid_path, missing_name_path, missing_comment_path, bad_legacy_path, bad_line_path, duplicate_path]:
		var before_bad := snapshot()
		panel.status.text = ""
		select_file(bad_path, "open")
		check(unchanged(before_bad) and not panel.status.text.is_empty(), "invalid TRES reports an error and retains the current library: " + bad_path.get_file())
	for path in protected:
		check(FileAccess.get_sha256(path) == protected[path], "initial project source remains unchanged: " + path)
	panel.dirty = false
	var modes := fixture("dialogue_modes")
	panel.open_library(modes)
	check(panel.table.columns == 4 and panel.table.get_column_title(2) == "对话类型" and panel.table.get_column_title(3) == "对话内容", "dialogue type column is immediately left of the dialogue text")
	check(panel.table.get_root().get_first_child().is_editable(2) and panel.table.get_root().get_first_child().get_range(2) == 0, "legacy rows default to the editable Free Dialogue option")
	panel.table.get_root().get_first_child().select(2)
	panel.table.grab_focus()
	panel.table.edit_selected()
	await frames()
	var mode_popup: PopupMenu
	for child in panel.table.get_children(true):
		if child is PopupMenu and child.visible: mode_popup = child
	check(mode_popup != null, "native dialogue type cell opens its dropdown")
	if mode_popup != null:
		mode_popup.hide()
		mode_popup.id_pressed.emit(mode_popup.get_item_id(1))
		await frames()
	check(panel.current_comment().lines[0].get("dialogue_mode", LIBRARY.MODE_FREE) == LIBRARY.MODE_STATIONARY, "native dropdown reaches the dialogue mode edit callback")
	panel.undo.undo()
	var id: String = panel.current_comment().lines[0].id
	var signature: String = panel.library.export_signature()
	panel.set_dialogue_mode(0, LIBRARY.MODE_STATIONARY)
	check(panel.current_comment().lines[0].dialogue_mode == LIBRARY.MODE_STATIONARY and panel.dirty and panel.library.export_signature() != signature, "changing dialogue mode updates its saved signature and dirty state")
	panel.undo.undo()
	check(panel.current_comment().lines[0].get("dialogue_mode", LIBRARY.MODE_FREE) == LIBRARY.MODE_FREE, "dialogue mode changes support undo")
	panel.undo.redo()
	check(panel.current_comment().lines[0].dialogue_mode == LIBRARY.MODE_STATIONARY and panel.current_comment().lines[0].id == id, "redo restores mode without changing dialogue ID")
	panel.edit_line()
	check(panel.detail_mode.selected == 1 and not panel.detail_duration.editable, "stationary dialogue details disable the automatic timer override")
	panel.detail_mode.select(0)
	panel._update_detail_timing()
	panel._apply_details(); panel.detail_dialog.hide()
	check(panel.current_comment().lines[0].dialogue_mode == LIBRARY.MODE_FREE and panel.detail_duration.editable, "details can change dialogue mode back to Free Dialogue")
	panel.set_dialogue_mode(1, LIBRARY.MODE_STATIONARY)
	var modes_path := DATA + "/dialogue_modes.xlsx"
	select_file(modes_path, "save")
	var mode_book := LIBRARY.read_xlsx(modes_path)
	check(mode_book.library != null and mode_book.library.groups[0].comments[0].lines[1].dialogue_mode == LIBRARY.MODE_STATIONARY, "dialogue mode survives Save Dialogues and XLSX reload")
	await capture("dialogue_modes")
	var extras: Dictionary = XLSX.read_book(modes_path).sheets
	extras["作者备注"] = [["说明"], ["保留这一页"]]
	var rows: Array = extras["对白"]
	rows[0].append("作者批注")
	rows[1].append("第一句的行备注")
	var standalone := []
	standalone.resize(rows[0].size()); standalone.fill(""); standalone[-1] = "独立的作者记录"
	rows.append(standalone)
	XLSX.write_book(modes_path, extras)
	panel.set_dialogue_mode(0, LIBRARY.MODE_STATIONARY)
	var original_hash := FileAccess.get_sha256(modes_path)
	panel.save()
	await frames()
	var conflict := panel.get_node_or_null("WorkbookConflict") as ConfirmationDialog
	check(panel.dirty and FileAccess.get_sha256(modes_path) == original_hash and conflict != null and conflict.visible, "external save keeps both the author's file and the open draft")
	if conflict != null:
		conflict.custom_action.emit(&"reload")
		await frames()
	check(not panel.dirty and panel.library.xlsx_path == modes_path, "explicit reload safely adopts the disk workbook")
	panel.set_dialogue_mode(0, LIBRARY.MODE_STATIONARY)
	var copy_path := DATA + "/with_notes.xlsx"
	check(panel.export_to(copy_path), "Save As with author-owned notes succeeds")
	var again: Dictionary = XLSX.read_book(copy_path).sheets
	check(again.has("作者备注") and again["作者备注"][1][0] == "保留这一页" and again["对白"][1][-1] == "第一句的行备注" and again["对白"][-1][-1] == "独立的作者记录", "copy preserves extra sheets, columns and note-only rows")
	panel.file.hide()
	panel.dirty = false
	host.queue_free()
	await frames()
	if is_instance_valid(window): window.queue_free()
	print("DIALOGUE FILE QA: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
