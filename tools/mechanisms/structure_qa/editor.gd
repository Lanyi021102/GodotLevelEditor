@tool
extends RefCounted
const BASE := "res://addons/godot_level_editor/scenes/mechanisms/"
const PERSONAL := "res://content/scenes/mechanisms/"
const LEVEL := "res://content/scenes/levels/mechanism_structure_qa.tscn"
const OUTPUT := "res://content/qa/mechanisms/"
const KINDS := ["double_door", "single_door", "pressure_plate", "button", "lift_platform"]
var checks := 0
var failures := 0
var tree: SceneTree
var panel: Control
var module: EditorPlugin
var suite: EditorPlugin
var authored := {}
var source_hashes := {}

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", title)

func frames(count := 12) -> void:
	for i in count: await tree.process_frame

func open_scene(path: String) -> Node:
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	for i in 240:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path:
			await frames()
			return root
		await tree.create_timer(0.03).timeout
	check(false, "open scene " + path)
	return null

func run(host: EditorPlugin) -> void:
	tree = host.get_tree()
	if not Array(OS.get_cmdline_user_args()).any(func(arg: String): return arg in ["--mechanism-structure-baseline", "--mechanism-structure-test", "--mechanism-save-state", "--mechanism-update-reopen"]): return
	tree.create_timer(180, true).timeout.connect(func(): EditorInterface.stop_playing_scene(); tree.quit(2))
	await tree.create_timer(3.0, true).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await frames()
	suite = tree.get_first_node_in_group("godot_level_editor_editor_suite")
	suite.open_tab("机关")
	await frames()
	module = suite.modules.mechanisms; panel = module.panel
	print("QA_USER_DATA=", OS.get_user_data_dir())
	if "--mechanism-update-reopen" in OS.get_cmdline_user_args():
		await update_reopen()
	elif "--mechanism-save-state" in OS.get_cmdline_user_args():
		await save_state()
	elif "--mechanism-structure-baseline" in OS.get_cmdline_user_args():
		await baseline()
	else:
		DirAccess.make_dir_recursive_absolute(PERSONAL)
		DirAccess.make_dir_recursive_absolute(OUTPUT)
		for kind in KINDS: await author_asset(kind)
		await guards()
		await place_and_play()
		for path in source_hashes: check(module.native_guard.pair_hash(path) == source_hashes[path], "plugin source preserved after complete flow: " + str(path.get_file()))
		var result := {"checks": checks, "failures": failures, "authored": authored, "user_data": OS.get_user_data_dir()}
		write(OUTPUT + "editor_result.json", JSON.stringify(result, "\t"))
	print("MECHANISM STRUCTURE RESULT: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)

func baseline() -> void:
	var path := BASE + "button.tscn"
	await open_scene(path)
	var before: String = module.native_guard.pair_hash(path)
	panel.set_component_property(panel.assembly.output_component(), "reset_after", 1.23)
	panel.add_kind("bool")
	panel.save(); await frames(30)
	check(module.native_guard.pair_hash(path) == before, "builtin panel Save must preserve addon scene and graph bytes")
	print("PANEL_SAVE_STATUS=", panel.status.text)
	path = BASE + "single_door.tscn"
	await open_scene(path)
	before = module.native_guard.pair_hash(path)
	panel.set_component_property(panel.assembly.output_component(), "motion_seconds", 1.23)
	panel.add_kind("bool")
	var result := EditorInterface.save_scene(); await frames(30)
	check(module.native_guard.pair_hash(path) == before, "builtin native Save must preserve addon scene and graph bytes")
	print("NATIVE_SAVE_RESULT=", result, " STATUS=", panel.status.text)

func write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content); file.close()

func selected(ids: Array) -> void:
	for child in panel.graph.get_children():
		if child is GraphNode: child.selected = str(child.name) in ids

func author_asset(kind: String) -> void:
	var path := BASE + kind + ".tscn"
	source_hashes[path] = module.native_guard.pair_hash(path)
	var catalog: Control = suite.asset_panels["机关"]
	catalog.select_asset(path); await catalog.enter_edit(); await frames()
	check(panel.assembly != null and panel.assembly.scene_file_path == path, kind + ": catalog enters the native builtin scene")
	if panel.assembly == null or panel.assembly.scene_file_path != path: return
	var original_count: int = panel.assembly.definition.nodes.size()
	var component: Node = panel.assembly.output_component()
	if kind in ["single_door", "double_door"]:
		check(component.leaf_count() == (1 if kind == "single_door" else 2) and component.door_dimensions() == Vector2(2 if kind == "single_door" else 4, 3), kind + ": correct frame dimensions and hinged leaf count")
	var key: String = "motion_seconds" if kind in ["single_door", "double_door", "lift_platform"] else ("reset_after" if kind == "button" else "release_delay")
	var old_value: float = component.get(key)
	var value := 1.1 if key == "motion_seconds" else 0.4
	panel.set_component_property(component, key, value)
	panel._history(false)
	check(is_equal_approx(component.get(key), old_value), kind + ": parameter supports native Undo")
	panel._history(true)
	check(is_equal_approx(component.get(key), value), kind + ": parameter supports native Redo")
	panel.add_kind("bool"); var bool_id: String = panel.selected_id
	panel._change_parameter("value", true)
	panel.add_kind("not"); var not_id: String = panel.selected_id
	panel.graph.connection_request.emit(bool_id, 0, not_id, 0)
	check(panel.assembly.definition.edges.any(func(e: Dictionary): return e.from == bool_id and e.to == not_id), kind + ": typed graph connection edits the actual definition")
	panel.graph.disconnection_request.emit(bool_id, 0, not_id, 0); panel._history(false)
	check(panel.assembly.definition.edges.any(func(e: Dictionary): return e.from == bool_id and e.to == not_id), kind + ": disconnect can be undone")
	selected([bool_id, not_id]); panel.graph.copy_nodes_request.emit()
	panel.graph.paste_nodes_request.emit()
	check(panel.assembly.definition.nodes.size() == original_count + 4, kind + ": copy/paste duplicates selected nodes and internal binding")
	panel._history(false)
	check(panel.assembly.definition.nodes.size() == original_count + 2, kind + ": paste can be undone")
	if kind in ["single_door", "double_door"]:
		var curve := Curve.new(); curve.add_point(Vector2.ZERO); curve.add_point(Vector2(0.5, 0.25)); curve.add_point(Vector2.ONE)
		var control: Control = panel.graph.get_node("rotate/DoorBody/RotationCurve")
		control.curve_edited.emit(curve)
		await frames()
		check(is_equal_approx(component.motion_curve.sample(0.5), 0.25), kind + ": node curve editor changes the physical door curve")
		panel._refresh_preview(); panel._preview_running = false
		panel._preview.bindings.door.perform_action("open"); panel._preview.bindings.door.advance(0.55); panel._preview.step(); panel._display_trace()
		check(panel._preview.bindings.door.get_state() == "moving" and is_equal_approx(panel._preview.bindings.door.angle_degrees(), 22.5) and component.get_state() == "close", kind + ": preview shows real curve angle without modifying source state")
		check(panel.graph.get_node("moving").get_meta("runtime_active"), kind + ": moving state is visible in its graph node")
	panel.add_kind("set_property"); var property_id: String = panel.selected_id
	panel._change_parameter("object_id", component.object_id)
	check(panel.assembly.definition.find_node(property_id).params.object_id == component.object_id, kind + ": property node explicitly binds the current physical component")
	panel._select_graph_node(panel.graph.get_node(property_id)); await frames(); panel.scene_selection_changed()
	check(panel.selected_id == property_id, kind + ": property-node selection remains on the chosen node")
	var component_node: String = panel.assembly.definition.nodes.filter(func(entry: Dictionary): return entry.kind == kind)[0].id
	selected([component_node, property_id]); panel.graph.copy_nodes_request.emit(); panel.graph.paste_nodes_request.emit()
	var copied: Dictionary = panel.assembly.definition.nodes[-2]
	var copied_property: Dictionary = panel.assembly.definition.nodes[-1]
	check(panel.assembly.bindings.size() == 2 and copied.params.object_id != component.object_id and copied_property.params.object_id == copied.params.object_id, kind + ": physical component copy gets a new ID and remaps its property binding")
	panel._history(false)
	check(panel.assembly.bindings.size() == 1, kind + ": undo removes the copied physical component and bindings")
	panel._history(false)
	panel._history(false)
	check(panel.Store.validate(panel.assembly).is_empty(), kind + ": edited graph and component validate")
	panel.save(); await frames()
	check(panel._save_dialog.visible and panel._save_dialog.current_path.begins_with(PERSONAL), kind + ": Save builtin offers a personal content path")
	check(module.native_guard.pair_hash(path) == source_hashes[path] and panel.dirty, kind + ": Save builtin preserves shipped bytes and draft")
	var personal := PERSONAL + "qa_" + kind + ".tscn"
	panel._save_dialog.hide(); panel._save_dialog.file_selected.emit(personal); await frames(30)
	check(panel.assembly != null and panel.assembly.scene_file_path == personal and FileAccess.file_exists(personal.get_basename() + ".graph.tres"), kind + ": Save As writes and activates a personal scene/graph pair")
	print("SAVE_AS_STATE ", kind, " open=", EditorInterface.get_open_scenes(), " unsaved=", EditorInterface.get_unsaved_scenes(), " panel_dirty=", panel.dirty)
	check(personal in EditorInterface.get_open_scenes() and not personal in EditorInterface.get_unsaved_scenes() and not path in EditorInterface.get_unsaved_scenes(), kind + ": Save As opens a real personal tab and leaves both copies clean")
	authored[kind] = personal
	EditorInterface.close_scene(); await frames()
	check(not panel.dirty, kind + ": returning to the builtin tab does not create a spurious dirty view")
	check(not personal in EditorInterface.get_open_scenes(), kind + ": native Close Scene closes the saved personal asset")
	await open_scene(personal)
	check(panel.assembly.definition.nodes.size() == original_count + 2 and is_equal_approx(panel.assembly.output_component().get(key), value), kind + ": close/reopen retains nodes and component parameters")
	check(panel.assembly.definition.find_node(bool_id).params.value and panel.assembly.definition.edges.any(func(e: Dictionary): return e.from == bool_id and e.to == not_id), kind + ": close/reopen retains values and typed connections")
	if kind in ["single_door", "double_door"]:
		check(is_equal_approx(panel.assembly.output_component().motion_curve.sample(0.5), 0.25), kind + ": close/reopen retains the custom curve")
	panel.selected_id = bool_id; panel._change_parameter("value", false)
	panel.save(); await frames()
	var reopened: Node = panel.Store.load_pair(personal)
	check(reopened != null and not reopened.definition.find_node(bool_id).params.value, kind + ": subsequent Save updates the personal copy")
	if reopened != null: reopened.free()
	check(module.native_guard.pair_hash(path) == source_hashes[path], kind + ": personal edits never write the builtin")
	if DisplayServer.get_name() != "headless" and kind == "single_door":
		panel.selected_id = "rotate"; panel._render(); panel._fit_graph(false); await frames()
		RenderingServer.force_draw(false); suite.window.get_texture().get_image().save_png(OUTPUT + "personal_door.png")
	EditorInterface.close_scene(); await frames()
	check(not panel.dirty, kind + ": final close returns to a clean builtin source")

func guards() -> void:
	var builtin := BASE + "button.tscn"
	await open_scene(builtin)
	panel.add_kind("bool")
	EditorInterface.save_scene(); await frames()
	check(module.native_guard.pair_hash(builtin) == source_hashes[builtin] and panel.dirty and builtin in EditorInterface.get_unsaved_scenes(), "native Save protects addon bytes and keeps the builtin draft unsaved")
	var graph_path := BASE + "button.graph.tres"
	ResourceSaver.save(panel.assembly.definition, graph_path); await frames()
	check(module.native_guard.pair_hash(builtin) == source_hashes[builtin], "native graph resource save also protects addon bytes")
	var bypass := "res://content/../addons/godot_level_editor/scenes/mechanisms/button.tscn"
	check(not panel.Store.save_pair(panel.assembly, bypass).ok and module.native_guard.pair_hash(builtin) == source_hashes[builtin], "Store rejects normalized paths that lead into addons")
	check(not panel.Store.save_pair(panel.assembly, "res://ADDONS/godot_level_editor/scenes/mechanisms/button.tscn").ok and module.native_guard.pair_hash(builtin) == source_hashes[builtin], "Store rejects mixed-case addon paths on case-insensitive filesystems")
	ResourceSaver.save(panel.assembly.definition, "res://ADDONS/godot_level_editor/scenes/mechanisms/button.graph.tres"); await frames()
	check(module.native_guard.pair_hash(builtin) == source_hashes[builtin], "native resource save rejects mixed-case addon paths")
	var rejected_path := BASE + "qa_forbidden.tscn"
	EditorInterface.save_scene_as(rejected_path, false); await frames()
	check(not FileAccess.file_exists(rejected_path) and not FileAccess.file_exists(rejected_path.get_basename() + ".graph.tres") and panel.dirty, "native Save As cannot create author works inside addons")
	panel._save_to(PERSONAL + "qa_guard_recovery.tscn"); await frames()
	check(panel.assembly.scene_file_path == PERSONAL + "qa_guard_recovery.tscn" and not panel.dirty, "rejected native Save As can recover by saving the draft under content")
	check(module._get_unsaved_status("").is_empty(), "successful personal recovery clears stale builtin rejection warnings")
	if not module._get_unsaved_status("").is_empty(): print("RECOVERY_STALE_STATUS ", module._get_unsaved_status(""), " blocked=", module.native_guard.blocked)
	panel.add_kind("not")
	check(not panel.Store.validate(panel.assembly).is_empty(), "unconnected required data input is invalid before saving")
	var personal: String = panel.assembly.scene_file_path
	var before: String = module.native_guard.pair_hash(personal)
	EditorInterface.save_scene(); await frames()
	check(module.native_guard.pair_hash(personal) == before and panel.dirty and personal in EditorInterface.get_unsaved_scenes(), "native save of invalid graph preserves the existing personal pair and draft")
	panel._history(false); panel.save(); await frames()
	check(not panel.dirty and not module.native_guard.blocked.has(personal), "fixing the invalid input permits a normal personal save")
	var external := personal.get_basename() + ".graph.tres"
	write(external, FileAccess.get_file_as_string(external) + "\n; external QA edit\n")
	before = module.native_guard.pair_hash(personal)
	panel.add_kind("bool")
	EditorInterface.save_scene(); await frames()
	check(module.native_guard.pair_hash(personal) == before and panel.dirty, "native save conflict preserves externally modified personal files")
	var recovery := PERSONAL + "qa_conflict_copy.tscn"
	panel._save_to(recovery); await frames()
	check(FileAccess.file_exists(recovery) and module.native_guard.pair_hash(personal) == before and panel.assembly.scene_file_path == recovery, "conflicting draft can be saved separately without overwriting the original")
	EditorInterface.close_scene(); await frames()

func place_and_play() -> void:
	if not KINDS.all(func(kind: String): return authored.has(kind)):
		check(false, "all five authored assets are available before native placement")
		return
	DirAccess.make_dir_recursive_absolute(LEVEL.get_base_dir())
	write(LEVEL, '[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://addons/godot_level_editor/templates/empty_level.tscn" id="base"]\n[node name="MechanismFlow" instance=ExtResource("base")]\n')
	var level := await open_scene(LEVEL)
	check(level != null and level.scene_file_path == LEVEL, "native inherited blank level opens under content")
	if level == null: return
	for index in KINDS.size():
		var kind: String = KINDS[index]
		var instance: Node3D = load(authored[kind]).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		instance.name = kind; instance.instance_id = panel.Schema.uid("assembly")
		instance.object_id = "qa_" + kind; instance.position = Vector3(-8 + index * 4, 0, -2)
		level.add_child(instance); instance.owner = level
		check(instance.scene_file_path == authored[kind] and instance.bindings.size() == 1, kind + ": native placement instances the personal standalone asset")
	var probe := Node.new(); probe.name = "RuntimeProbe"; probe.set_script(load("res://tools/mechanisms/structure_qa/runtime.gd")); level.add_child(probe); probe.owner = level
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene(); await frames()
	check(FileAccess.get_file_as_string(LEVEL).contains('instance=ExtResource("base")') or FileAccess.get_file_as_string(LEVEL).contains("templates/empty_level.tscn"), "native Save retains inherited template linkage")
	check(not str(level.level_id).is_empty(), "native level Save assigns a stable level ID")
	var book: Dictionary = load("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	check(book.catalog != null and str(book.catalog.by_id(str(level.level_id)).get("scene_path", "")) == LEVEL, "native placement level is registered for task binding")
	EditorInterface.close_scene(); await frames(); level = await open_scene(LEVEL)
	check(KINDS.all(func(kind: String): return level.has_node(kind)), "native close/reopen keeps all five placed personal instances")
	await play_f6()

func play_f6() -> void:
	var result_path := OUTPUT + "f6_result.json"
	if FileAccess.file_exists(result_path): DirAccess.remove_absolute(result_path)
	EditorInterface.play_current_scene()
	for i in 500:
		if FileAccess.file_exists(result_path): break
		await tree.create_timer(0.1, true).timeout
	check(FileAccess.file_exists(result_path), "actual editor F6 runtime returns a completion report")
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path))
		check(int(result.failures) == 0 and int(result.checks) >= 20, "actual F6 player interaction, occupancy, door curves and lift round trip pass")
	EditorInterface.stop_playing_scene(); await tree.create_timer(0.5, true).timeout

func update_reopen() -> void:
	for kind in KINDS:
		var path := PERSONAL + "qa_" + str(kind) + ".tscn"
		authored[kind] = path
		var root := await open_scene(path)
		check(root != null and panel.Store.validate(root).is_empty() and root.bindings.size() == 1, str(kind) + ": plugin update preserves loadable personal scene, graph and component")
		if kind in ["single_door", "double_door"]:
			check(is_equal_approx(root.output_component().motion_curve.sample(0.5), 0.25), str(kind) + ": plugin update preserves authored curve")
		check(not panel.dirty, str(kind) + ": reopening after update does not mark an untouched asset dirty")
		EditorInterface.close_scene(); await frames()
	var level := await open_scene(LEVEL)
	check(level != null and level.validate().is_empty(), "personal inherited level remains valid after replacing the installed plugin")
	await play_f6()

func save_state() -> void:
	DirAccess.make_dir_recursive_absolute(PERSONAL)
	await open_scene(BASE + "button.tscn")
	panel.add_kind("bool")
	panel._save_to(PERSONAL + "qa_save_state.tscn"); await frames(30)
	print("SAVE_STATE open=", EditorInterface.get_open_scenes(), " unsaved=", EditorInterface.get_unsaved_scenes(), " dirty=", panel.dirty, " path=", panel.assembly.scene_file_path)
	panel.add_kind("not")
	var path: String = panel.assembly.scene_file_path
	var before: String = module.native_guard.pair_hash(path)
	print("INVALID_BEFORE ", panel.Store.validate(panel.assembly), " hash=", before, " guard=", module.native_guard.registered.get_ref())
	EditorInterface.save_scene(); await frames(30)
	print("INVALID_AFTER hash=", module.native_guard.pair_hash(path), " dirty=", panel.dirty, " unsaved=", EditorInterface.get_unsaved_scenes(), " blocked=", module.native_guard.blocked, " status=", panel.status.text)
	check(before == module.native_guard.pair_hash(path), "native invalid save preserves paired files")
