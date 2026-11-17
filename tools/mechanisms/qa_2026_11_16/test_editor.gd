@tool
extends RefCounted
var directory := "res://tools/mechanisms/qa_2026_11_16/generated_%d" % OS.get_process_id()
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/factory.gd")
const STORE := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd")
var checks := 0
var failures := 0
var serial := 0

func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", title)

func frames(tree: SceneTree, count := 20) -> void:
	for index in count: await tree.process_frame

func write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value); file.close()

func fixture(panel: Control, name_: String) -> String:
	serial += 1
	var path := directory + "/%s_%d.tscn" % [name_, serial]
	var root := FACTORY.sample()
	check(STORE.save_pair(root, path).ok, "create isolated paired fixture " + name_)
	root.free()
	EditorInterface.get_resource_filesystem().scan()
	await frames(panel.get_tree(), 30)
	EditorInterface.open_scene_from_path(path)
	await frames(panel.get_tree(), 45)
	check(panel.assembly == EditorInterface.get_edited_scene_root() and panel.assembly.scene_file_path == path, "bind real editor fixture " + name_)
	return path

func select(panel: Control, ids: Array) -> void:
	for child in panel.graph.get_children():
		if child is GraphNode: child.selected = str(child.name) in ids

func run(panel: Control, plugin: EditorPlugin) -> void:
	var tree := panel.get_tree()
	await frames(tree, 70)
	DirAccess.make_dir_recursive_absolute(directory)
	await fixture(panel, "clipboard")
	panel.add_kind("bool"); var source_id: String = panel.selected_id
	select(panel, [source_id]); panel.graph.copy_nodes_request.emit()
	panel._change_parameter("value", true)
	panel.graph.paste_nodes_request.emit()
	check(not panel.assembly.definition.nodes.back().params.value, "QA-05 clipboard preserves false captured before source edits")
	select(panel, [source_id]); panel.graph.copy_nodes_request.emit()
	panel.graph.delete_nodes_request.emit([source_id])
	var count: int = panel.assembly.definition.nodes.size()
	panel.graph.paste_nodes_request.emit()
	check(panel.assembly.definition.nodes.size() == count + 1 and panel.assembly.definition.nodes.back().params.value, "QA-05 clipboard survives deleting its source")
	panel.add_kind("button"); var button_node: String = panel.selected_id
	var button_id: String = panel.assembly.definition.find_node(button_node).params.object_id
	var button: Node3D = panel.assembly.bindings[button_id]
	button.locked = true; button.reset_after = 2.0
	button.transition_rules.assign([{"from": "idle", "action": "interact", "to": "pressed"}])
	var marker := Marker3D.new(); marker.name = "AuthoredMarker"; marker.position = Vector3(0.4, 0.5, 0.6)
	button.add_child(marker); marker.owner = panel.assembly
	panel.add_kind("state_changed"); var event_id: String = panel.selected_id
	panel._change_parameter("object_id", button_id)
	select(panel, [button_node, event_id]); panel.graph.copy_nodes_request.emit()
	button.locked = false; button.reset_after = 9; marker.position = Vector3.ONE
	panel._delete_nodes([button_node, event_id]); button.free(); panel.assembly.configure()
	panel.graph.paste_nodes_request.emit()
	var copied_node: Dictionary = panel.assembly.definition.nodes[-2]
	var copied_event: Dictionary = panel.assembly.definition.nodes[-1]
	var copied: Node = panel.assembly.bindings[copied_node.params.object_id]
	check(copied_node.params.object_id != button_id and copied_event.params.object_id == copied_node.params.object_id, "QA-05 pasted component and event share one new stable binding")
	check(copied.locked and copied.reset_after == 2.0 and copied.transition_rules[0].action == "interact", "QA-05 component snapshot preserves exported configuration")
	check(copied.has_node("AuthoredMarker") and copied.get_node("AuthoredMarker").position == Vector3(0.4, 0.5, 0.6), "QA-05 component snapshot preserves authored child nodes after deleting original object")
	var copied_id: String = copied_node.id
	panel._history(false)
	check(panel.assembly.definition.find_node(copied_id).is_empty(), "QA-05 paste supports undo")
	panel._history(true)
	check(not panel.assembly.definition.find_node(copied_id).is_empty(), "QA-05 paste supports redo")
	select(panel, ["lever_state", "plate_state", "both", "door_target"])
	panel.graph.copy_nodes_request.emit()
	var edge_count: int = panel.assembly.definition.edges.size()
	panel.graph.paste_nodes_request.emit()
	var graph_copy: Array = panel.assembly.definition.nodes.slice(-4)
	var new_ids: Array = graph_copy.map(func(entry: Dictionary): return entry.id)
	var new_edges: Array = panel.assembly.definition.edges.slice(-3)
	check(panel.assembly.definition.edges.size() == edge_count + 3 and new_edges.all(func(edge: Dictionary): return edge.from in new_ids and edge.to in new_ids), "QA-05 clipboard preserves internal edges and remaps both endpoints")
	await fixture(panel, "cross_scene_paste")
	panel.graph.paste_nodes_request.emit()
	check(panel.assembly.definition.nodes.size() == 8 and panel.assembly.bindings.size() == 6 and STORE.validate(panel.assembly).is_empty(), "QA-05 captured nodes, components and edges paste into another scene")
	# Native serialization must reject conflicts even if the panel is no longer active.
	var conflict_path: String = await fixture(panel, "scene_conflict")
	panel.add_kind("bool")
	var scene_text := FileAccess.get_file_as_string(conflict_path)
	scene_text = scene_text.replace("instance_id =", "metadata/qa_external = \"keep scene sentinel\"\ninstance_id =")
	write(conflict_path, scene_text)
	var before: String = plugin.native_guard.pair_hash(conflict_path)
	var native_result := EditorInterface.save_scene()
	await frames(tree)
	check(plugin.native_guard.pair_hash(conflict_path) == before and FileAccess.get_file_as_string(conflict_path).contains("keep scene sentinel"), "QA-01 actual native save preserves externally modified scene and graph bytes")
	check(panel.dirty and plugin.native_guard.blocked.has(conflict_path) and not plugin._get_unsaved_status(conflict_path).is_empty(), "QA-01 rejected native save retains dirty status and visible reason")
	check(conflict_path in EditorInterface.get_unsaved_scenes(), "QA-01 native editor still marks rejected scene unsaved after returning")
	print("NATIVE_REJECT_RESULT=", native_result, " (saver handled rejection without writing)")
	panel.save_before_editor()
	check(plugin.native_guard.pair_hash(conflict_path) == before, "QA-01 panel save also preserves conflict bytes")
	var graph_conflict_path: String = await fixture(panel, "graph_conflict")
	panel.add_kind("bool")
	var graph_path := graph_conflict_path.get_basename() + ".graph.tres"
	write(graph_path, FileAccess.get_file_as_string(graph_path).replace("display_name =", "metadata/qa_external = \"keep graph sentinel\"\ndisplay_name ="))
	before = plugin.native_guard.pair_hash(graph_conflict_path)
	EditorInterface.save_scene(); await frames(tree)
	check(plugin.native_guard.pair_hash(graph_conflict_path) == before and FileAccess.get_file_as_string(graph_path).contains("keep graph sentinel"), "QA-01 native scene and external-resource save preserve conflicting graph bytes")
	var invalid_path: String = await fixture(panel, "invalid")
	panel.add_kind("delay"); var delay_id: String = panel.selected_id
	check(not STORE.validate(panel.assembly).is_empty(), "QA-01 invalid fixture contains the real unconnected delay input")
	before = plugin.native_guard.pair_hash(invalid_path)
	EditorInterface.save_scene(); await frames(tree)
	check(plugin.native_guard.pair_hash(invalid_path) == before and panel.dirty, "QA-01 actual native save writes neither file for invalid graph")
	var disk: Node = STORE.load_pair(invalid_path)
	check(disk != null and disk.definition.find_node(delay_id).is_empty(), "QA-01 rejected invalid draft leaves the previous valid pair loadable")
	if disk != null: disk.free()
	var conflict_hash: String = plugin.native_guard.pair_hash(conflict_path)
	var graph_conflict_hash: String = plugin.native_guard.pair_hash(graph_conflict_path)
	EditorInterface.save_all_scenes(); await frames(tree, 25)
	check(plugin.native_guard.pair_hash(invalid_path) == before and plugin.native_guard.pair_hash(conflict_path) == conflict_hash and plugin.native_guard.pair_hash(graph_conflict_path) == graph_conflict_hash, "QA-01 native Save All preserves invalid and conflicting scene/graph pairs across open tabs")
	EditorInterface.open_scene_from_path(invalid_path); await frames(tree)
	panel._delete_nodes([delay_id])
	panel.add_kind("bool"); var valid_id: String = panel.selected_id
	EditorInterface.save_scene(); await frames(tree)
	disk = STORE.load_pair(invalid_path)
	var external: Resource = ResourceLoader.load(invalid_path.get_basename() + ".graph.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(disk != null and not disk.definition.find_node(valid_id).is_empty() and external.nodes == disk.definition.nodes, "QA-01 corrected native save updates the paired external graph")
	check(not FileAccess.get_file_as_string(invalid_path).contains("nodes =") and panel.assembly.definition.resource_path == invalid_path.get_basename() + ".graph.tres" and not panel.dirty, "QA-01 native save keeps one external authoring graph and clears dirty state")
	if disk != null: disk.free()
	# Explicit reload acknowledges the external version; an ordinary tab switch must not.
	EditorInterface.open_scene_from_path(conflict_path); await frames(tree)
	check(plugin.native_guard.conflict(conflict_path), "QA-01 switching tabs retains the original conflict baseline")
	panel._reload_current(); await frames(tree, 35)
	check(not plugin.native_guard.conflict(conflict_path) and not plugin.native_guard.blocked.has(conflict_path), "QA-01 explicit reload accepts the disk version and clears the refusal")
	panel.add_kind("bool"); var after_reload: String = panel.selected_id
	EditorInterface.save_scene(); await frames(tree)
	disk = STORE.load_pair(conflict_path)
	check(disk != null and disk.has_meta("qa_external") and not disk.definition.find_node(after_reload).is_empty(), "QA-01 native save after reload preserves external metadata and new edits")
	if disk != null: disk.free()
	var save_as_path := directory + "/native_save_as.tscn"
	panel.add_kind("bool")
	EditorInterface.save_scene_as(save_as_path); await frames(tree, 35)
	disk = STORE.load_pair(save_as_path)
	check(disk != null and FileAccess.file_exists(save_as_path.get_basename() + ".graph.tres"), "QA-01 native Save As creates a valid paired scene and graph")
	if disk != null: disk.free()
	panel.add_kind("delay")
	var invalid_as_path := directory + "/invalid_save_as.tscn"
	EditorInterface.save_scene_as(invalid_as_path); await frames(tree, 25)
	check(not FileAccess.file_exists(invalid_as_path) and not FileAccess.file_exists(invalid_as_path.get_basename() + ".graph.tres"), "QA-01 invalid native Save As creates neither file")
	print("MECHANISM QA EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
