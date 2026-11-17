@tool
extends RefCounted
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const EVENTS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const BLOCK := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd")
const BOOK := LEVELS.PATH
const FIRST := "res://content/scenes/levels/910001_delete_first.tscn"
const SECOND := "res://content/scenes/levels/910002_delete_second.tscn"
const HOST := "res://content/scenes/qa_delete_host.tscn"
class TrashFailure:
	extends "res://addons/godot_level_editor/modules/godot_level_editor_suite/level_warehouse.gd"
	func _trash_scene(_path: String) -> Error: return ERR_CANT_CREATE
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame
func write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(data); file.close()
func scene(path: String, id: String) -> void:
	var world := WORLD.new(); world.name = "DeleteQA"; world.level_id = id
	var floor := BLOCK.new(); floor.name = "Floor"; floor.object_id = "floor"; floor.size = Vector3(20, 1, 20)
	world.add_child(floor); floor.owner = world
	var packed := PackedScene.new(); packed.pack(world)
	check(ResourceSaver.save(packed, path) == OK, "private scene writes: " + id)
	world.free()
func open_scene(tree: SceneTree, path: String) -> void:
	EditorInterface.get_resource_filesystem().update_file(path)
	await frames(tree)
	EditorInterface.open_scene_from_path(path)
	for attempt in 120:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path: break
		await tree.create_timer(0.03, true).timeout
	await frames(tree)
func confirm(panel: Control) -> void:
	panel.delete_dialog.get_ok_button().pressed.emit()
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	if not str(ProjectSettings.get_setting("application/config/name")).begins_with("QA-Preview-"):
		push_error("Deletion QA must run in the disposable runner project"); tree.quit(2); return
	tree.create_timer(75, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.7, true).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await tree.create_timer(0.1, true).timeout
	await tree.create_timer(0.5, true).timeout
	var output := "user://delete_evidence"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="): output = arg.trim_prefix("--qa-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var original_events := FileAccess.get_file_as_bytes(EVENTS.PATH)
	var original_levels := FileAccess.get_file_as_bytes(LEVELS.PATH)
	var events := EVENTS.new(); events.save_book(EVENTS.PATH)
	scene(FIRST, "910001"); scene(SECOND, "910002")
	var catalog := LEVELS.new()
	catalog.levels.assign([
		{"level_id":"910001", "name":"delete_first", "display_name":"待删除关卡", "scene_path":FIRST, "notes":"first", "preview_path":""},
		{"level_id":"910002", "name":"delete_second", "display_name":"保留关卡", "scene_path":SECOND, "notes":"second", "preview_path":""}])
	catalog.next_id = 910003
	check(catalog.save_book(BOOK).is_empty(), "private level workbook writes")
	var panel: Control = suite.level_panel; panel.workbook_path = BOOK; panel.reload_catalog(); panel.select_level("910001")
	var changed := [0]; panel.levels_changed.connect(func(): changed[0] += 1)
	var book_hash := FileAccess.get_sha256(BOOK)
	var first_hash := FileAccess.get_sha256(FIRST)
	suite.show_window(); suite.open_tab("关卡"); panel.set_mode(0)
	panel._ask_delete()
	await frames(tree)
	check(panel.delete_dialog.visible and panel.delete_dialog.dialog_text.contains("待删除关卡") and panel.delete_dialog.dialog_text.contains(FIRST) and panel.delete_dialog.dialog_text.contains("废纸篓"), "confirmation names the level and exact scene deletion")
	check(panel.delete_dialog.get_cancel_button().has_focus() and panel.delete_dialog.ok_button_text == "删除关卡", "confirmation defaults focus to cancel and uses a specific delete action")
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		panel.delete_dialog.get_texture().get_image().save_png(output.path_join("confirmation.png"))
	panel.delete_dialog.get_cancel_button().pressed.emit()
	await frames(tree, 2)
	check(not panel.delete_dialog.visible and panel._delete_target.is_empty() and panel.selected_level_id == "910001" and FileAccess.get_sha256(BOOK) == book_hash and FileAccess.get_sha256(FIRST) == first_hash and changed[0] == 0, "cancel changes no scene, catalog, selection, or deletion signal")
	var event := events.add_event(); events.add_task(str(event.event_id), "910001"); events.save_book(EVENTS.PATH)
	panel.delete_selected("910001", FIRST)
	check(FileAccess.get_sha256(BOOK) == book_hash and FileAccess.get_sha256(FIRST) == first_hash and panel.status.text.contains("引用"), "task references prevent scene and catalog deletion")
	write(EVENTS.PATH, "broken workbook".to_utf8_buffer()); panel.delete_selected("910001", FIRST)
	check(FileAccess.get_sha256(BOOK) == book_hash and FileAccess.file_exists(FIRST) and panel.status.text.contains("无法检查任务引用"), "unreadable event workbook fails closed")
	EVENTS.new().save_book(EVENTS.PATH)
	write(HOST, ("[gd_scene load_steps=2 format=3]\n[ext_resource type=\"PackedScene\" path=\"" + FIRST + "\" id=\"1\"]\n[node name=\"Dependent\" instance=ExtResource(\"1\")]\n").to_utf8_buffer())
	panel.delete_selected("910001", FIRST)
	check(FileAccess.file_exists(FIRST) and FileAccess.get_sha256(BOOK) == book_hash and panel.status.text.contains(HOST), "explicit scene references prevent deletion and identify the dependent")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HOST))
	var blocked := BOOK + ".tmp"; DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked))
	panel.delete_selected("910001", FIRST)
	check(FileAccess.file_exists(FIRST) and LEVELS.load_book(BOOK).catalog.levels.size() == 2 and panel.status.text.contains("未删除"), "failed workbook write leaves the scene and catalog intact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
	var failure := TrashFailure.new(); failure.workbook_path = BOOK; failure.catalog = LEVELS.load_book(BOOK).catalog; failure.status = Label.new(); failure.add_child(failure.status)
	failure.delete_selected("910001", FIRST)
	check(FileAccess.get_sha256(FIRST) == first_hash and LEVELS.load_book(BOOK).catalog.levels.size() == 2 and failure.catalog.levels.size() == 2 and failure.status.text.contains("未删除"), "failed file deletion rolls the workbook back and keeps the scene")
	failure.free()
	# A stale confirmation may never delete a newly assigned scene path.
	panel._ask_delete()
	var latest: Resource = LEVELS.load_book(BOOK).catalog
	latest.by_id("910001").scene_path = SECOND
	latest.by_id("910002").scene_path = FIRST
	latest.save_book(BOOK)
	confirm(panel)
	check(FileAccess.file_exists(FIRST) and FileAccess.file_exists(SECOND) and panel.status.text.contains("路径已变化"), "changed target path invalidates an already open confirmation")
	catalog.save_book(BOOK); panel.reload_catalog(); panel.select_level("910001")
	await open_scene(tree, FIRST)
	check(FIRST in EditorInterface.get_open_scenes(), "deletion fixture is open in the native scene editor")
	# Simulate a window kept open through a tool-script reload.
	panel.delete_dialog.confirmed.disconnect(panel._confirm_delete)
	panel.delete_dialog.confirmed.connect(panel.delete_selected)
	panel._ask_delete(); panel.select_level("910002")
	latest = LEVELS.load_book(BOOK).catalog; latest.by_id("910002").notes = "updated during confirmation"; latest.save_book(BOOK)
	suite.level_preview.workbook_path = BOOK
	suite.level_preview.request(FIRST)
	confirm(panel)
	await frames(tree, 8)
	if suite.level_preview.is_busy(): await suite.level_preview.idle
	check(not FileAccess.file_exists(FIRST) and FileAccess.file_exists(SECOND) and LEVELS.load_book(BOOK).catalog.by_id("910001").is_empty(), "confirm deletes the frozen target even if the selected card changes")
	check(not FIRST in EditorInterface.get_open_scenes() and changed[0] == 1 and LEVELS.load_book(BOOK).catalog.by_id("910002").notes == "updated during confirmation", "native scene closes and the latest unrelated metadata survives")
	check(FileAccess.file_exists("user://level_archive/910001.json") and not FileAccess.file_exists("res://content/resources/level_previews/910001.png"), "metadata is archived and queued thumbnail generation cannot recreate the deleted level")
	panel.delete_dialog.confirmed.disconnect(panel.delete_selected)
	panel.delete_dialog.confirmed.connect(panel._confirm_delete)
	await open_scene(tree, SECOND)
	var root := EditorInterface.get_edited_scene_root()
	root.get_node("Floor").size = Vector3(30, 1, 20); EditorInterface.mark_scene_as_unsaved()
	await frames(tree, 2)
	panel.delete_selected("910002", SECOND)
	await frames(tree)
	check(FileAccess.file_exists(SECOND) and not LEVELS.load_book(BOOK).catalog.by_id("910002").is_empty() and panel.status.text.contains("先保存或关闭"), "unsaved native scene blocks deletion without discarding its edits")
	EditorInterface.save_scene_as(SECOND, false)
	await frames(tree)
	panel.select_level("910002"); panel._ask_delete(); confirm(panel)
	await frames(tree, 8)
	if suite.level_preview.is_busy(): await suite.level_preview.idle
	check(not FileAccess.file_exists(SECOND) and LEVELS.load_book(BOOK).catalog.levels.is_empty() and not SECOND in EditorInterface.get_open_scenes() and changed[0] == 2, "after saving, confirmation deletes the scene file and its catalog record")
	write(LEVELS.PATH, original_levels); write(EVENTS.PATH, original_events)
	print("LEVEL DELETE TEST: ", checks, " checks, ", failures, " failures")
	tree.quit(0 if failures == 0 else 1)
