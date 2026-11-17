@tool
extends RefCounted
var checks := 0
var failures := 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", title)
func frames(tree: SceneTree, count := 15) -> void:
	for i in count: await tree.process_frame
func run(panel: Control, plugin: EditorPlugin) -> void:
	var tree := panel.get_tree(); await frames(tree, 70)
	var suite: EditorPlugin = tree.get_first_node_in_group("godot_level_editor_editor_suite")
	suite.show_window(); suite.navigation_buttons["机关"].pressed.emit(); await frames(tree)
	var catalog: Control = suite.asset_panels["机关"]; catalog.reload_catalog()
	check(catalog.entries.size() == 5 and panel.Schema.COMPONENT_KINDS.all(func(kind: String): return catalog.entries.has("res://addons/godot_level_editor/scenes/mechanisms/" + kind + ".tscn")), "My Mechanisms lists exactly five standalone assets")
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://docs/mechanism_editor/independent_2026-11-16")
		await tree.create_timer(0.3, true).timeout; RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png("res://docs/mechanism_editor/independent_2026-11-16/五种独立机关.png")
	for kind in ["lever", "terminal", "sliding_door", "hinged_door", "toggle_switch"]:
		panel._filter_kinds(kind)
		check(panel._kinds.item_count == 0, kind + " cannot be created through node search")
	catalog.select_asset("res://addons/godot_level_editor/scenes/mechanisms/single_door.tscn"); await catalog.enter_edit(); await frames(tree)
	check(panel.assembly != null and panel.assembly.bindings.size() == 1, "single door opens independently from the catalog")
	for kind in ["set_property", "perform_action", "state_is", "state_changed"]:
		panel.add_kind(kind); var id: String = panel.selected_id
		panel._select_graph_node(panel.graph.get_node(id)); await frames(tree); panel.scene_selection_changed()
		check(panel.selected_id == id and panel.graph.get_node(id).selected, kind + " selection remains on the requested graph node")
		panel._history(false)
	var before: int = panel.assembly.definition.nodes.size(); panel.add_kind("terminal")
	check(panel.assembly.definition.nodes.size() == before, "removed component type is rejected by the add-node entry point")
	panel._refresh_preview(); panel.selected_id = "rotate"; panel._preview_interact(); panel._preview_running = false
	panel._preview.step(); panel._preview.bindings.door.advance(2); panel._preview.step(); panel._display_trace()
	check(panel._preview.bindings.door.get_state() == "open" and panel.assembly.bindings.door.get_state() == "close", "self interaction opens only the preview copy of the independent door")
	var empty_path := "res://addons/godot_level_editor/scenes/mechanisms/cleanup_empty_%d.tscn" % OS.get_process_id()
	catalog._opening = true; catalog.create_asset(empty_path); catalog._opening = false
	var empty: Node = panel.Store.load_pair(empty_path)
	check(empty != null and empty.definition.nodes.is_empty() and empty.bindings.is_empty(), "New Mechanism creates an empty editable graph instead of a coupled preset")
	if empty != null: empty.free()
	await frames(tree, 30)
	for file in [empty_path, empty_path.get_basename() + ".graph.tres"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	catalog.reload_catalog()
	check(catalog.entries.size() == 5, "removing the isolated test asset restores the five-item catalog")
	var saved := "res://tools/mechanisms/independent_v1/roundtrip_%d.tscn" % OS.get_process_id()
	panel._save_to(saved); await frames(tree, 30)
	var loaded: Node = panel.Store.load_pair(saved)
	check(loaded != null and loaded.bindings.size() == 1, "save and reopen retains the standalone component and its own graph")
	if loaded != null: loaded.free()
	print("INDEPENDENT MECHANISMS EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
