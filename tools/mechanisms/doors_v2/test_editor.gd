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
func mouse(curve: Control, pressed: bool, at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new(); event.pressed = pressed; event.button_index = button; event.position = at
	curve._gui_input(event)
func capture(suite: EditorPlugin, file: String) -> void:
	await suite.get_tree().create_timer(0.25, true).timeout
	RenderingServer.force_draw(false)
	suite.window.get_texture().get_image().save_png("res://docs/mechanism_editor/doors_v2_2026-11-16/" + file)

func no_overlap(panel: Control) -> bool:
	var cards: Array[GraphNode] = []
	for child in panel.graph.get_children():
		if child is GraphNode: cards.append(child)
	var valid := true
	for i in cards.size():
		for j in range(i + 1, cards.size()):
			if Rect2(cards[i].position_offset, cards[i].size).intersects(Rect2(cards[j].position_offset, cards[j].size)):
				print("OVERLAP ", cards[i].name, " ", cards[i].size, " @", cards[i].position_offset, " / ", cards[j].name, " ", cards[j].size, " @", cards[j].position_offset)
				valid = false
	return valid

func run(panel: Control, plugin: EditorPlugin) -> void:
	var tree := panel.get_tree(); await frames(tree, 70)
	var suite: EditorPlugin = tree.get_first_node_in_group("godot_level_editor_editor_suite")
	suite.show_window(); suite.window.size = Vector2i(1504, 1050); suite.navigation_buttons["机关"].pressed.emit(); await frames(tree, 20)
	var warehouse: Control = suite.asset_panels["机关"]
	check(warehouse.entries.has("res://addons/godot_level_editor/scenes/mechanisms/single_door.tscn") and warehouse.entries.has("res://addons/godot_level_editor/scenes/mechanisms/double_door.tscn"), "catalog offers the two new doors with direct names")
	warehouse.select_asset("res://addons/godot_level_editor/scenes/mechanisms/double_door.tscn"); await warehouse.enter_edit(); await frames(tree)
	if panel.assembly == null: check(false, "door editor opens"); tree.quit(1); return
	check(panel.assembly.definition.nodes.size() == 7 and panel.graph.has_node("frame/DoorBody") and panel.graph.has_node("leaf/DoorBody"), "door graph exposes fixed frame and rotating leaf as separate nodes")
	check(panel.graph.get_node("close").title == "close" and panel.graph.get_node("moving").title == "moving" and panel.graph.get_node("open").title == "open", "three named states are visible directly on graph cards")
	var curve: Control = panel.graph.get_node("rotate/DoorBody/RotationCurve")
	check(curve != null and curve.custom_minimum_size.y >= 100 and curve.curve.point_count == 2, "rotation node embeds an editable animation curve")
	check(panel.graph.get_node("close").get_meta("runtime_active"), "close state is highlighted before starting preview")
	panel.selected_id = "rotate"; panel._select_graph_node(panel.graph.get_node("rotate")); await frames(tree)
	panel.scene_selection_changed()
	check(panel.selected_id == "rotate", "selecting the animation node retains selection when its shared physical door reports selection")
	var door: Node = panel.assembly.bindings.door
	var at: Vector2 = curve.point_position(Vector2(0.4, 0.7))
	mouse(curve, true, at); mouse(curve, false, at); await frames(tree)
	check(door.motion_curve.point_count == 3 and panel.dirty and is_equal_approx(door.motion_curve.get_point_position(1).y, 0.7), "editing a curve point through its real input handler updates the paired component and dirty status")
	panel._history(false); await frames(tree)
	check(door.motion_curve.point_count == 2, "curve editing supports scene undo")
	panel._history(true); await frames(tree)
	check(door.motion_curve.point_count == 3, "curve editing supports scene redo")
	# Return to the standard smooth curve for consistent preview captures.
	panel._history(false); await frames(tree)
	panel.selected_id = "rotate"; panel._render(); panel._fit_graph(false); await frames(tree)
	check(no_overlap(panel), "all seven door nodes fit without overlap before preview")
	var capture_enabled := "--capture" in OS.get_cmdline_user_args()
	if capture_enabled:
		DirAccess.make_dir_recursive_absolute("res://docs/mechanism_editor/doors_v2_2026-11-16")
		await capture(suite, "双开门_close.png")
		DirAccess.make_dir_recursive_absolute("res://addons/godot_level_editor/resources/mechanisms/whitebox_v1/previews")
		panel._viewport.get_texture().get_image().save_png("res://addons/godot_level_editor/resources/mechanisms/whitebox_v1/previews/double_door.png")
	panel._preview_interact(); await frames(tree, 2)
	# Advance deterministic physics ticks instead of depending on display FPS.
	panel._preview_running = false
	var preview: Node = panel._preview.bindings.door
	panel._preview.step(); preview.advance(preview.motion_seconds * 0.5); panel._preview.step(); panel._display_trace()
	check(preview.get_state() == "moving" and panel.graph.get_node("moving").get_meta("runtime_active") and not panel.graph.get_node("open").get_meta("runtime_active"), "preview shows moving while the leaves are rotating")
	check(panel.graph.get_node("rotate/DoorBody/Pose").text.contains("moving") and panel.graph.get_node("rotate/DoorBody/RotationCurve").progress > 0, "animation card shows the live state, angle and curve playhead")
	check(no_overlap(panel), "runtime values and curve controls do not overlap neighboring state cards")
	if capture_enabled: await capture(suite, "双开门_moving.png")
	preview.advance(2); panel._preview.step(); panel._display_trace()
	check(preview.get_state() == "open" and panel.graph.get_node("open").get_meta("runtime_active") and is_equal_approx(preview.angle_degrees(), 90), "preview highlights open only when both leaves reach ninety degrees")
	if capture_enabled: await capture(suite, "双开门_open.png")
	panel.selected_id = "rotate"; panel._render_details()
	check(panel.details.find_children("*", "SpinBox", true, false).size() > 0 and panel.details.find_children("*", "Button", true, false).size() > 2, "animation parameters expose duration, curve presets and direct open/close preview controls")
	panel.set_component_property(door, "motion_curve", preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/runtime/rotating_door.gd").default_curve(true)); await frames(tree)
	var path := "res://tools/mechanisms/doors_v2/roundtrip_%d.tscn" % OS.get_process_id()
	panel._save_to(path); await frames(tree, 35)
	var loaded: Node = panel.Store.load_pair(path)
	check(loaded != null and is_equal_approx(loaded.get_node("Door").motion_curve.sample(0.25), 0.25) and loaded.definition.nodes.size() == 7, "paired save/reopen preserves the actual editable curve and all state/structure nodes")
	if loaded != null: loaded.free()
	panel._filter_kinds("")
	var offered: Array = []
	for i in panel._kinds.item_count: offered.append(str(panel._kinds.get_item_metadata(i)))
	check("single_door" in offered and "double_door" in offered and "sliding_door" not in offered and "hinged_door" not in offered, "new door choices default to the two requested specifications")
	panel._filter_kinds("sliding_door")
	check(panel._kinds.item_count == 0, "removed door types are absent from the creation palette even when searched")
	warehouse.select_asset("res://addons/godot_level_editor/scenes/mechanisms/single_door.tscn"); await warehouse.enter_edit(); await frames(tree)
	check(panel.assembly.bindings.door.leaf_count() == 1 and panel.assembly.bindings.door.door_dimensions() == Vector2(2, 3), "single-door catalog entry opens with the distinct one-leaf two-by-three geometry")
	panel.selected_id = "rotate"; panel._render(); panel._fit_graph(false); await frames(tree)
	if capture_enabled:
		await capture(suite, "单开门_close.png")
		panel._viewport.get_texture().get_image().save_png("res://addons/godot_level_editor/resources/mechanisms/whitebox_v1/previews/single_door.png")
	var before_nodes: int = panel.assembly.definition.nodes.size()
	var before_objects: int = panel.assembly.bindings.size()
	panel.add_kind("double_door"); await frames(tree)
	check(panel.assembly.definition.nodes.size() == before_nodes + 7 and panel.assembly.bindings.size() == before_objects + 1 and panel.Store.validate(panel.assembly).is_empty(), "adding either door specification creates a complete wired seven-node blueprint automatically")
	panel._history(false); await frames(tree)
	check(panel.assembly.definition.nodes.size() == before_nodes and panel.assembly.bindings.size() == before_objects, "adding the full door blueprint undoes as one scene action")
	print("ROTATING DOORS EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
