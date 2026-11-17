@tool
extends RefCounted
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(panel: Control, count := 5) -> void:
	for _i in count: await panel.get_tree().process_frame
func run(panel: Control, plugin: EditorPlugin) -> void:
	var test_path := "res://tools/mechanisms/.canvas_test_%s.tscn" % Time.get_ticks_usec()
	var fixture_path := "res://tools/mechanisms/.canvas_fixture_%s.tscn" % OS.get_process_id()
	var fixture: Node3D = panel.Factory.sample()
	check(panel.Store.save_pair(fixture, fixture_path).ok, "create isolated compatibility graph fixture")
	fixture.free()
	await frames(panel, 30)
	EditorInterface.open_scene_from_path(fixture_path)
	await frames(panel, 25)
	(panel.get_tree().get_first_node_in_group("godot_level_editor_editor_suite").open_tab("机关") if panel.get_tree().get_first_node_in_group("godot_level_editor_editor_suite") != null else EditorInterface.set_main_screen_editor("机关蓝图"))
	await frames(panel, 10)
	if not is_instance_valid(panel.assembly):
		check(false, "editor binds assembly scene")
		panel.get_tree().quit(1)
		return
	check(panel.graph.get_connection_list().size() == 3, "GraphEdit renders executable sample connections")
	var left: GraphNode = panel.graph.get_node("lever_state")
	var middle: GraphNode = panel.graph.get_node("both")
	var right: GraphNode = panel.graph.get_node("door_target")
	check(left.position_offset.x + left.size.x < middle.position_offset.x and middle.position_offset.x + middle.size.x < right.position_offset.x, "default node layout leaves visible space for connecting wires")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mechanism-capture="):
			panel._fit_graph(false)
			panel.selected_id = "lever_state"
			panel._select_graph_node(panel.graph.get_node("lever_state"))
			panel._toggle_preview()
			panel._preview_interact()
			panel.plate_button.button_pressed = true
			await panel.get_tree().create_timer(1.1).timeout
			await RenderingServer.frame_post_draw
			panel.get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--mechanism-capture="))
			panel._preview_running = false
			panel._refresh_preview()
	var root: Node3D = panel.assembly
	var count: int = root.definition.nodes.size()
	panel._search.text = "AND"
	panel._filter_kinds("AND")
	check(panel._kinds.item_count == 1, "search filters node palette")
	panel.add_kind("bool")
	check(root.definition.nodes.size() == count + 1, "add node updates executable definition")
	var added: String = panel.selected_id
	panel._history(false)
	check(root.definition.nodes.size() == count, "undo add node")
	panel._history(true)
	check(root.definition.nodes.size() == count + 1, "redo add node")
	panel._change_parameter("value", true)
	check(root.definition.find_node(added).params.value, "parameter edit changes executable value")
	panel._history(false)
	check(not root.definition.find_node(added).params.value, "undo parameter edit")
	panel._history(true)
	var before_wire: Array = root.definition.edges.duplicate(true)
	panel.graph.connection_request.emit(added, 0, "door_target", 0)
	check(root.definition.edges.back().from == added and panel.graph.get_connection_list().size() == 3, "port drag replaces door driver in executable graph")
	panel._history(false)
	check(root.definition.edges == before_wire, "undo wire replacement restores all original endpoints")
	panel._history(true)
	panel.graph.disconnection_request.emit(added, 0, "door_target", 0)
	check(root.definition.edges.size() == 2, "port disconnection changes definition")
	panel._history(false)
	check(root.definition.edges.size() == 3, "undo disconnection")
	panel.selected_id = "lever_state"
	panel._select_graph_node(panel.graph.get_node("lever_state"))
	check(EditorInterface.get_selection().get_selected_nodes().back() == root.bindings.lever, "graph node selects linked 3D object")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(root.bindings.door)
	panel.scene_selection_changed()
	check(panel.selected_id == "door_target", "3D scene selection selects corresponding graph node")
	var before: Resource = root.definition.duplicate(true)
	panel._moving_before = before
	panel.graph.get_node("door_target").position_offset += Vector2(80, 50)
	panel._end_move()
	check(root.definition.positions.door_target == before.positions.door_target + Vector2(80, 50), "drag changes layout only")
	panel._history(false)
	check(root.definition.positions.door_target == before.positions.door_target, "undo graph layout")
	panel._duplicate_nodes(["lever_state"])
	var copied: Dictionary = root.definition.nodes.back()
	check(copied.id != "lever_state" and copied.params.object_id != "lever" and root.bindings.size() == 4, "copy allocates new node and scene object IDs")
	check(root.bindings[copied.params.object_id].object_id == copied.params.object_id, "copied graph node is bound to actual copied scene object")
	panel._history(false)
	check(root.bindings.size() == 3 and root.get_child_count() == 3, "undo copy removes copied scene object")
	panel._history(true)
	check(root.bindings.size() == 4 and root.get_child_count() == 4, "redo copy restores same scene binding")
	panel._history(false)
	panel.graph.delete_nodes_request.emit([StringName(added)])
	check(root.definition.find_node(added).is_empty() and root.definition.edges.size() == 2, "delete graph node removes incident executable edges")
	panel._history(false)
	check(not root.definition.find_node(added).is_empty() and root.definition.edges.size() == 3, "undo node deletion restores edges")
	panel._preview_running = true
	await frames(panel, 20)
	check(panel._preview.bindings.door.is_open() or panel._preview.bindings.door._command, "isolated preview executes edited graph")
	check(not root.bindings.door.is_powered(), "preview leaves authored scene runtime state unchanged")
	panel._preview_running = false
	panel.graph.zoom = 0.8
	panel.graph.scroll_offset = Vector2(90, 110)
	panel._view_changed()
	panel._new_file = false
	panel._save_to(test_path)
	await frames(panel, 90)
	check(not panel.dirty and panel.assembly.scene_file_path == test_path, "save and reopen independent scene+graph pair")
	check(is_equal_approx(panel.assembly.definition.view_zoom, 0.8) and panel.assembly.definition.view_offset == Vector2(90, 110), "reload retains canvas zoom/pan")
	check(panel.assembly.definition.find_node(added).get("params", {}).get("value", false), "reload retains node parameters and wire endpoints")
	# Let the native editor finish layout/teardown between closing and reopening tabs.
	await frames(panel, 3)
	EditorInterface.close_scene()
	await frames(panel, 3)
	EditorInterface.open_scene_from_path(test_path)
	await frames(panel, 30)
	check(panel.assembly.definition.find_node(added).get("params", {}).get("value", false), "close and reopen preserves graph and scene bindings")
	var trace := {"door_target": {"value": true, "reason": "测试运行结果", "frame": 42}}
	panel.receive_runtime("1:sample", {"session": 1, "instance": "/root/TestMechanism", "definition_id": panel.assembly.definition.definition_id, "trace": trace, "frame": 42, "pending": 0})
	panel.selected_runtime = "1:sample"
	panel._display_trace()
	check(panel.graph.get_node("door_target").get_meta("runtime_active", false) and panel.runtime_label.text.contains("42"), "actual-instance debug packet highlights graph state")
	panel.clear_session(1)
	check(panel.runtime_packets.is_empty(), "ending debug session clears runtime instances")
	EditorInterface.play_custom_scene(fixture_path)
	await panel.get_tree().create_timer(3.0).timeout
	check(not panel.runtime_packets.is_empty(), "running scene sends actual EngineDebugger state packets")
	EditorInterface.stop_playing_scene()
	await panel.get_tree().create_timer(0.5).timeout
	check(panel.runtime_packets.is_empty(), "stopping game clears actual runtime session")
	panel._reload_current()
	await frames(panel, 25)
	check(panel.assembly.definition.find_node(added).get("params", {}).get("value", false) and not panel.dirty, "explicit reload restores valid pair")
	panel.selected_id = "lever_state"
	panel._select_graph_node(panel.graph.get_node("lever_state"))
	panel._preview_running = true
	panel._preview_interact()
	panel._preview_plate = true
	panel._update_preview_plate()
	await frames(panel, 15)
	print("MECHANISM CANVAS: %d passed / %d failed" % [passed, failed])
	panel.get_tree().quit(1 if failed else 0)
