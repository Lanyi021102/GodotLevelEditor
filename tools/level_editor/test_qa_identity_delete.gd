@tool
extends RefCounted
## Runs only in a disposable project prepared by run_qa_identity_delete.py.
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const GROUPS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const EVENTS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const XLSX := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/xlsx.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func frames(tree: SceneTree, count := 8) -> void:
	for i in count: await tree.process_frame

func world(name_text: String) -> Node3D:
	var result: Node3D = WORLD.new(); result.name = name_text; result.start_room_id = ""
	result.topology = GRAPH.new(); result.topology.graph_id = name_text + "_topology"; result.topology.graph_kind = "topology"
	result.events = GRAPH.new(); result.events.graph_id = name_text + "_events"
	return result

func assembly(parent: Node, root: Node, object_id: String, instance_id: String) -> Node3D:
	var node: Node3D = load("res://addons/godot_level_editor/scenes/mechanisms/single_door.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	node.name = object_id.to_pascal_case(); node.object_id = object_id; node.instance_id = instance_id
	FACTORY.add_owned(parent, node, root)
	return node

func component_ids(node: Node) -> Dictionary:
	var result := {}
	for child in node.find_children("*", "Node3D", true, false):
		if child.get("object_id") is String: result[str(node.get_path_to(child))] = child.get("object_id")
	return result

func open_scene(editor: EditorPlugin, path: String) -> Node:
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	for i in 100:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path:
			await editor.get_tree().create_timer(0.25, true).timeout
			return root
		await editor.get_tree().create_timer(0.05, true).timeout
	return null

func native_duplicate(editor: EditorPlugin, original: Node) -> Node:
	var edited := EditorInterface.get_edited_scene_root()
	if not is_instance_valid(original) or not original.is_inside_tree() or edited == null or not edited.is_ancestor_of(original):
		push_error("QA harness: fixture is not the active edited scene"); return null
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(original); EditorInterface.edit_node(original)
	await editor.get_tree().create_timer(0.15, true).timeout
	if EditorInterface.get_edited_scene_root() != edited or not original.is_inside_tree():
		push_error("QA harness: editor startup changed the active scene"); return null
	var docks := EditorInterface.get_base_control().find_children("*", "SceneTreeDock", true, false)
	if docks.is_empty(): return null
	var dock: Node = docks[0]
	for scene_tree in dock.find_children("*", "Tree", true, false):
		if scene_tree.get_selected() != null and "SceneTreeEditor" in str(scene_tree.get_parent().get_class()):
			print("QA native context selection=", scene_tree.get_selected().get_text(0))
			scene_tree.item_mouse_selected.emit(Vector2(200, 200), MOUSE_BUTTON_RIGHT)
	await editor.get_tree().process_frame
	var dispatched := false
	for popup in dock.find_children("*", "PopupMenu", true, false):
		for i in popup.item_count:
			if popup.get_item_text(i) in ["Duplicate", "复制"]:
				print("QA native Duplicate popup=", popup.get_path(), " id=", popup.get_item_id(i))
				popup.id_pressed.emit(popup.get_item_id(i)); popup.hide(); dispatched = true; break
		if dispatched: break
	await editor.get_tree().create_timer(0.25, true).timeout
	var selected := EditorInterface.get_selection().get_selected_nodes()
	return selected[0] if dispatched and selected.size() == 1 and selected[0] != original else null

func duplicate_case(editor: EditorPlugin, root: Node, original: Node, reference: String) -> void:
	var old_object: String = original.object_id; var old_instance: String = original.instance_id
	var local_ids := component_ids(original)
	var copy: Node = await native_duplicate(editor, original)
	check(copy != null, "QA-02 native SceneTreeDock Duplicate creates " + reference)
	if copy == null: return
	var copy_id: String = copy.object_id; var copy_instance: String = copy.instance_id
	print("QA identities original=", old_object, "/", old_instance, " copy=", copy_id, "/", copy_instance)
	var scope: String = reference.get_slice("/", 0)
	check(copy_id != old_object and copy_instance != old_instance, "QA-02 duplicate gets independent object_id and instance_id")
	check(original.object_id == old_object and original.instance_id == old_instance, "QA-02 original IDs are unchanged")
	check(root.object_by_id(reference) == original and root.object_by_id(scope + "/" + copy_id) == copy, "QA-02 original and new world references resolve to their own instances")
	check(component_ids(copy) == local_ids, "QA-02 assembly-local component IDs and graph bindings are preserved")
	check(root.validate().is_empty(), "QA-02 duplicated world validates")
	var manager := editor.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(root))
	check(history.undo(), "QA-02 native duplicate supports Undo")
	await frames(editor.get_tree())
	check(copy.get_parent() == null and root.object_by_id(reference) == original, "QA-02 Undo removes only the duplicate")
	check(history.redo(), "QA-02 native duplicate supports Redo")
	await frames(editor.get_tree())
	check(copy.object_id == copy_id and copy.instance_id == copy_instance and root.object_by_id(reference) == original, "QA-02 Redo preserves generated IDs and the original reference")
	EditorInterface.save_scene_as(root.scene_file_path, false)
	var fresh: Node = ResourceLoader.load(root.scene_file_path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var old_disk: Node = fresh.object_by_id(reference)
	var copy_disk: Node = fresh.object_by_id(scope + "/" + copy_id)
	check(old_disk != null and copy_disk != null and old_disk != copy_disk and old_disk.instance_id == old_instance and copy_disk.instance_id == copy_instance and fresh.validate().is_empty(), "QA-02 saved/reopened references and both IDs stay independent")
	fresh.free()

func legacy_duplicates(editor: EditorPlugin, directory: String) -> void:
	var source := world("ExistingDuplicates")
	assembly(source, source, "existing", "first_instance"); assembly(source, source, "existing", "second_instance")
	# Give the nodes unique names, while deliberately preserving duplicate stored IDs.
	var path := directory + "/existing_duplicates.tscn"
	FACTORY.save_scene(source, path); source.free()
	var root: Node = await open_scene(editor, path)
	check(root != null, "QA-02 opens pre-existing duplicate data without migrating IDs")
	if root == null: return
	var values: Array = GROUPS.contents(root).map(func(node: Node): return node.get("object_id"))
	check(values.count("existing") == 2, "QA-02 loading does not automatically renumber existing user objects")
	check("对象 ID 重复：$world/existing" in root.validate(), "QA-02 validation explicitly reports existing world-scope duplicate IDs")
	check(root.object_by_id("$world/existing") == null and not root.objects().has("$world/existing"), "QA-02 ambiguous stored references cannot silently target the last duplicate")
	EditorInterface.save_scene_as(path, false)
	var saved: Node = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	check(GROUPS.contents(saved).filter(func(node: Node): return node.get("object_id") == "existing").size() == 2, "QA-02 saving does not rewrite pre-existing duplicate IDs")
	saved.free()
	var scoped := world("ScopedObjects")
	for room_id in ["one", "two"]:
		var room: Node3D = FACTORY.ROOM.new(); room.room_id = room_id; room.uses_topology = false; FACTORY.add_owned(scoped, room, scoped)
		assembly(room, scoped, "same_local_id", room_id + "_instance")
	check(scoped.validate().is_empty() and scoped.object_by_id("one/same_local_id") != scoped.object_by_id("two/same_local_id"), "QA-02 identical local IDs in different Rooms remain valid")
	var first_room: Node = scoped.rooms()[0]
	assembly(first_room, scoped, "same_local_id", "duplicate_instance")
	check(not scoped.validate().is_empty() and scoped.object_by_id("one/same_local_id") == null and scoped.object_by_id("two/same_local_id") != null, "QA-02 Room duplicates are rejected without affecting other scopes")
	scoped.free()

func store(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(bytes); file.close()

func delete_guard(editor: EditorPlugin, directory: String) -> void:
	var suite: Node = editor.get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
	var panel: Control = suite.level_panel
	var original_catalog: Resource = panel.catalog; var original_path: String = panel.workbook_path
	var event_bytes := FileAccess.get_file_as_bytes(EVENTS.PATH)
	var level_path := directory + "/levels_guard.xlsx"
	var level_bytes := FileAccess.get_file_as_bytes(LEVELS.PATH)
	store(level_path, level_bytes)
	var catalog := EVENTS.new(); var event := catalog.add_event(); catalog.add_task(str(event.event_id), "1")
	check(catalog.save_book(EVENTS.PATH).is_empty(), "QA-10 fixture writes only the isolated project event workbook")
	var good_events := FileAccess.get_file_as_bytes(EVENTS.PATH)
	var emissions := [0]
	var changed := func(): emissions[0] += 1
	panel.levels_changed.connect(changed)
	for mode in ["referenced", "missing", "corrupt", "schema"]:
		store(level_path, level_bytes); store(EVENTS.PATH, good_events)
		panel.catalog = LEVELS.load_book(level_path).catalog; panel.workbook_path = level_path; panel.selected_level_id = "1"; panel.status.text = ""
		var before: Array = panel.catalog.levels.duplicate(true)
		var digest := FileAccess.get_sha256(level_path)
		var changes: int = emissions[0]
		var archive := "user://level_archive/1.json"
		if FileAccess.file_exists(archive): DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
		if mode == "missing": DirAccess.remove_absolute(ProjectSettings.globalize_path(EVENTS.PATH))
		elif mode == "corrupt": store(EVENTS.PATH, "not an XLSX file".to_utf8_buffer())
		elif mode == "schema":
			var sheets := catalog.sheets(); sheets["配置"][1][1] = "999"; XLSX.write_book(EVENTS.PATH, sheets)
		panel.delete_selected()
		check(panel.catalog.levels == before and FileAccess.get_sha256(level_path) == digest, "QA-10 " + mode + " input leaves memory and disk catalog unchanged")
		check(panel.selected_level_id == "1" and emissions[0] == changes and not FileAccess.file_exists(archive), "QA-10 " + mode + " input does not change selection, emit deletion, or archive")
		check(panel.status.text.contains("引用") if mode == "referenced" else panel.status.text.contains("无法检查任务引用") and panel.status.text.contains("未删除"), "QA-10 " + mode + " input displays the actual dependency-check result")
	store(level_path, level_bytes); store(EVENTS.PATH, good_events)
	panel.catalog = LEVELS.load_book(level_path).catalog; panel.workbook_path = level_path; panel.selected_level_id = "2"; panel.status.text = ""
	var scene_path := "res://content/scenes/levels/qa_delete_guard.tscn"
	store(scene_path, FileAccess.get_file_as_bytes(str(panel.catalog.by_id("2").scene_path)))
	panel.catalog.by_id("2").scene_path = scene_path
	check(panel.catalog.save_book(level_path).is_empty(), "QA-10 deletion uses a dedicated disposable level scene")
	var before_changes: int = emissions[0]
	panel.delete_selected()
	check(panel.catalog.by_id("2").is_empty() and LEVELS.load_book(level_path).catalog.by_id("2").is_empty() and emissions[0] == before_changes + 1, "QA-10 valid unreferenced levels can still be removed normally")
	check(not FileAccess.file_exists(scene_path), "QA-10 confirmed deletion also removes the dedicated level scene")
	panel.levels_changed.disconnect(changed)
	store(EVENTS.PATH, event_bytes); panel.catalog = original_catalog; panel.workbook_path = original_path

func run(editor: EditorPlugin) -> void:
	var tree := editor.get_tree()
	if not str(ProjectSettings.get_setting("application/config/name")).begins_with("QA-Level-"):
		push_error("QA test requires run_qa_identity_delete.py and a disposable project/user directory"); tree.quit(2); return
	tree.create_timer(55, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.7 if DisplayServer.get_name() == "headless" else 5.0, true).timeout
	for i in 100:
		if not EditorInterface.get_resource_filesystem().is_scanning(): break
		await tree.create_timer(0.1, true).timeout
	var directory := "res://qa_level_fixtures"
	DirAccess.make_dir_recursive_absolute(directory)
	var source := world("NativeIdentity")
	assembly(source, source, "root_assembly", "root_instance")
	var group := GROUPS.new_group("mechanism"); FACTORY.add_owned(source, group, source)
	assembly(group, source, "group_assembly", "group_instance")
	var room: Node3D = FACTORY.ROOM.new(); room.name = "Room"; room.room_id = "room"; room.uses_topology = false; FACTORY.add_owned(source, room, source)
	var nested := GROUPS.new_group("mechanism"); FACTORY.add_owned(room, nested, source)
	assembly(nested, source, "room_assembly", "room_instance")
	var path := directory + "/native_identity.tscn"
	FACTORY.save_scene(source, path); source.free()
	var root: Node = await open_scene(editor, path)
	check(root != null, "QA-02 fixture opens in the real Godot editor")
	if root == null: tree.quit(1); return
	for reference in ["$world/root_assembly", "$world/group_assembly", "room/room_assembly"]:
		var original: Node = root.object_by_id(reference)
		await duplicate_case(editor, root, original, reference)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-capture="):
			await tree.create_timer(0.2, true).timeout
			RenderingServer.force_draw(false)
			var captured := EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--qa-capture="))
			check(captured == OK, "QA-02 native SceneTreeDock and duplicate IDs render in the real editor")
	await legacy_duplicates(editor, directory)
	await delete_guard(editor, directory)
	print("QA LEVEL FIXES: %d checks, %d failures; user data=%s" % [checks, failures, OS.get_user_data_dir()])
	tree.quit(1 if failures else 0)
