@tool
extends RefCounted
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const TASK := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")
const LOGIC := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_logic_graph.gd")
const REF := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_reference.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const GROUPS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func frames(tree: SceneTree, count := 4) -> void:
	for i in count: await tree.process_frame

func focus_pointer(window: Window, point: Vector2, tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless": window.notify_mouse_entered(); return
	window.grab_focus()
	for i in 30:
		if window.has_focus(): break
		await tree.create_timer(0.05, true).timeout
	# macOS warping is relative to the currently focused native window.
	DisplayServer.warp_mouse(Vector2i(window.get_final_transform() * point))
	await tree.create_timer(0.15, true).timeout

func payload(node: Node) -> Dictionary:
	return {"type": "nodes", "nodes": [node.get_path()]}

func show_card(panel: Control, id: String, tree: SceneTree) -> void:
	var card: GraphNode = panel.canvas.get_node(NodePath(id))
	panel.canvas.scroll_offset = card.position_offset * panel.canvas.zoom - Vector2(70, 100)
	await frames(tree)

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(60, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.7, true).timeout
	# The native editor may still be restoring its saved scene tabs after imports.
	for i in 100:
		if not EditorInterface.get_resource_filesystem().is_scanning(): break
		await tree.create_timer(0.1, true).timeout
	await tree.create_timer(1.0, true).timeout
	var path := "res://tools/level_editor/.reference_fixture_%d.tscn" % OS.get_process_id()
	var source := WORLD.new(); source.name = "ReferenceSandbox"; source.start_room_id = ""
	source.topology = GRAPH.new(); source.events = GRAPH.new()
	var group := GROUPS.new_group("npc")
	FACTORY.add_owned(source, group, source)
	var npc := REF.NPC.new(); npc.name = "Guard"; npc.object_id = "guard"
	FACTORY.add_owned(group, npc, source)
	var room := FACTORY.room("hall", "Hall")
	FACTORY.add_owned(source, room, source)
	for child in room.get_children(): child.owner = source
	var region := WORLD.REGION.new(); region.name = "Trigger"; region.object_id = "trigger"
	FACTORY.add_owned(source, region, source)
	var placement := WORLD.PLACE.new(); placement.name = "Door"; placement.object_id = "door"
	placement.component_scene = load("res://addons/godot_level_editor/scenes/mechanisms/single_door.tscn")
	FACTORY.add_owned(source, placement, source)
	check(FACTORY.save_scene(source, path) == OK, "isolated grouped fixture saves")
	source.free()
	EditorInterface.get_resource_filesystem().update_file(path)
	await frames(tree, 8)
	EditorInterface.open_scene_from_path(path)
	for i in 100:
		var current := EditorInterface.get_edited_scene_root()
		if current != null and current.scene_file_path == path: break
		if i % 20 == 19: EditorInterface.open_scene_from_path(path)
		await tree.create_timer(0.05, true).timeout
	var world := EditorInterface.get_edited_scene_root()
	if world == null or world.scene_file_path != path: check(false, "fixture opens"); tree.quit(1); return
	suite.open_tab("任务图")
	suite.show_window()
	suite.display_adapter.restore_geometry(Rect2i(Vector2i.ZERO, Vector2i.ZERO), false)
	var panel: Control = suite.modules.narrative.task_panel
	panel.dirty = false
	var graph := TASK.new(); graph.graph_id = "reference_drop_test"
	graph.nodes = [
		{"id": "remove", "kind": "set_visibility", "label": "移除已击败敌人", "params": {"object": "", "enabled": false}},
		{"id": "interact", "kind": "object_interacted", "params": {"object": "", "once": false}},
		{"id": "npc", "kind": "npc_interact", "params": {"npc": "", "task": "1001001"}},
		{"id": "room", "kind": "room_enter", "params": {"room": "", "once": false}},
		{"id": "actor", "kind": "actor_state", "params": {"actor": "", "key": "ready", "expected": true}},
		{"id": "region", "kind": "region_enter", "params": {"object": "", "once": false}},
		{"id": "door", "kind": "mechanism_interacted", "params": {"mechanism": "", "player_only": true, "once": false}}]
	graph.edges = [{"id": "edge", "from": "interact", "from_port": "then", "to": "remove", "to_port": "run"}]
	for i in graph.nodes.size(): graph.positions[graph.nodes[i].id] = Vector2(50 + (i % 3) * 320, 80 + (i / 3) * 240)
	panel.open_graph(graph); panel.world = world; panel._rebuild()
	await frames(tree)
	for definition in graph.nodes:
		var card: GraphNode = panel.canvas.get_node(NodePath(definition.id))
		var spec := GRAPH.ports(definition.kind)
		check(card.get_input_port_count() == spec.in.size() and card.get_output_port_count() == spec.out.size(), "drop fields preserve named ports: " + str(definition.kind))
	var guard: Node = world.object_by_id("$world/guard")
	var data := payload(guard)
	var remove: Dictionary = graph.node_by_id("remove")
	check(REF.resolve(world, graph, remove, "object", data) == "$world/guard", "native hierarchy payload resolves grouped object to stable world ID")
	check(REF.resolve(world, graph, remove, "object", payload(guard.get_child(0))) == "$world/guard", "model child resolves to its entity root")
	check(REF.resolve(world, graph, graph.node_by_id("room"), "room", payload(world.rooms()[0])) == "hall", "Room resolves to room ID")
	check(REF.resolve(world, graph, graph.node_by_id("npc"), "npc", data) == "guard", "task NPC keeps legacy unscoped ID contract")
	check(REF.resolve(world, LOGIC.new(), graph.node_by_id("npc"), "npc", data) == "$world/guard", "level NPC keeps scoped ID contract")
	check(REF.resolve(world, graph, graph.node_by_id("region"), "object", data).is_empty(), "wrong target type is rejected")
	check(REF.resolve(world, graph, remove, "object", payload(world.get_node("NPCs"))).is_empty(), "management folder is rejected")
	check(REF.resolve(world, graph, remove, "object", {"type": "nodes", "nodes": [guard.get_path(), guard.get_path()]}).is_empty(), "multi-selection cannot overwrite one target")
	check(REF.resolve(world, graph, remove, "object", {"type": "files", "files": ["res://addons/godot_level_editor/scenes/narrative/npc.tscn"]}).is_empty(), "asset file is not a placed scene object")
	var other := WORLD.new(); tree.root.add_child(other)
	var outsider := REF.NPC.new(); outsider.object_id = "guard"; other.add_child(outsider)
	check(REF.resolve(world, graph, remove, "object", payload(outsider)).is_empty(), "same ID in another world is rejected")
	other.free()
	var door_reference := REF.resolve(world, graph, graph.node_by_id("door"), "mechanism", payload(world.object_by_id("$world/door")))
	check(door_reference.begins_with("$world/door::"), "mechanism placement binds its component ID")
	var before := graph.snapshot()
	var target: Control = panel.canvas.get_node("remove/SceneReferences/object")
	check(target._can_drop_data(Vector2.ZERO, data), "card drop area accepts scene hierarchy payload")
	target._drop_data(Vector2.ZERO, data)
	await frames(tree)
	check(graph.node_by_id("remove").params.object == "$world/guard" and panel.selected_id == "remove" and panel.dirty, "drop immediately binds, selects node and marks graph dirty")
	check(graph.edges == before.edges and graph.positions == before.positions, "binding preserves connections and positions")
	var stable := graph.snapshot()
	panel._accept_reference_drop({"type": "nodes", "nodes": [world.get_path()]}, graph, "remove", "object")
	check(graph.snapshot() == stable, "rejected drop preserves existing binding")
	panel._accept_reference_drop(data, TASK.new(), "remove", "object")
	check(graph.snapshot() == stable, "deferred drop from a switched graph is ignored")
	panel.undo.undo()
	check(graph.snapshot() == before, "one undo restores entire previous graph")
	panel.undo.redo()
	check(graph.node_by_id("remove").params.object == "$world/guard", "redo reapplies binding")
	panel.selected_id = "interact"; panel._show_parameters(); await frames(tree)
	check(panel._fields.object is OptionButton and panel._fields.object.item_count > 1, "object dropdown remains available")
	panel._option_field("object", "missing reference test", [""], "$world/missing")
	check(panel._fields.object.get_item_metadata(panel._fields.object.selected) == "$world/missing", "unavailable existing references stay selected instead of silently clearing")
	panel._show_parameters()
	panel._accept_reference_drop(data, graph, "interact", "object")
	panel._accept_reference_drop(data, graph, "npc", "npc")
	panel._accept_reference_drop(payload(world.rooms()[0]), graph, "room", "room")
	panel._accept_reference_drop(data, graph, "actor", "actor")
	panel._accept_reference_drop(payload(world.object_by_id("$world/trigger")), graph, "region", "object")
	panel._accept_reference_drop(payload(world.object_by_id("$world/door")), graph, "door", "mechanism")
	check(graph.validate().is_empty(), "bound interaction, visibility, actor, Room and mechanism graph validates")
	var save_path := "user://reference_drop_roundtrip.tres"
	check(ResourceSaver.save(graph, save_path) == OK, "binding saves as normal graph resource")
	var reopened: Resource = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.semantic_hash() == graph.semantic_hash(), "reopen preserves all stable bindings and edges")
	var mechanism_action := {"id": "request", "kind": "mechanism_action", "params": {"mechanism": "", "action": "press"}}
	var added := graph.snapshot(); added.nodes.append(mechanism_action)
	panel._commit("test component change", graph.snapshot(), added)
	panel._accept_reference_drop(payload(world.object_by_id("$world/door")), graph, "request", "mechanism")
	check(graph.node_by_id("request").params.action == "", "changing component clears incompatible action choices")
	panel.undo.undo()
	check(graph.node_by_id("request").params.action == "press" and graph.node_by_id("request").params.mechanism == "", "component binding and dependent choices undo together")
	panel.undo.undo()
	# Exercise actual native GraphEdit input routing rather than calling the drop handler.
	var unbound := graph.snapshot()
	for definition in unbound.nodes:
		if definition.id == "actor": definition.params.actor = ""
	panel._commit("clear test actor", graph.snapshot(), unbound)
	panel.selected_id = "actor"; panel._rebuild(); await frames(tree)
	await show_card(panel, "actor", tree)
	var actor_target: Control = panel.canvas.get_node("actor/SceneReferences/actor")
	var point := actor_target.get_global_rect().get_center()
	var main := EditorInterface.get_base_control().get_window()
	await focus_pointer(suite.window, point, tree)
	var preview := Label.new(); preview.text = "Guard"
	actor_target.force_drag(data, preview)
	var motion := InputEventMouseMotion.new(); motion.window_id = suite.window.get_window_id(); motion.position = point; motion.global_position = point
	suite.window.push_input(motion, true); await frames(tree)
	if DisplayServer.get_name() != "headless": check(actor_target._highlight, "native drag hover highlights the designated field")
	var click := InputEventMouseButton.new(); click.window_id = suite.window.get_window_id(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = point; click.global_position = point
	suite.window.push_input(click, true); click.pressed = false; suite.window.push_input(click, true)
	await frames(tree)
	check(not suite.window.gui_is_dragging(), "native mouse release completes drag")
	if DisplayServer.get_name() != "headless": check(graph.node_by_id("actor").params.actor == "$world/guard", "native mouse drop binds the actor without Apply")
	# Scene-tree drags originate in the main editor viewport, not the suite window.
	if DisplayServer.get_name() != "headless":
		panel.undo.undo(); await frames(tree)
		await show_card(panel, "actor", tree)
		actor_target = panel.canvas.get_node("actor/SceneReferences/actor")
		point = actor_target.get_global_rect().get_center()
		await focus_pointer(main, Vector2(50, 400), tree)
		var cross_preview := Label.new(); cross_preview.text = "Guard from hierarchy"
		EditorInterface.get_base_control().force_drag(data, cross_preview)
		await focus_pointer(suite.window, point, tree)
		motion = InputEventMouseMotion.new(); motion.window_id = suite.window.get_window_id(); motion.position = point; motion.global_position = point
		suite.window.push_input(motion, true)
		await frames(tree)
		# The source viewport owns completion; the destination supplies the hovered field.
		var source_point: Vector2 = main.get_final_transform().affine_inverse() * (Vector2(suite.window.position) + suite.window.get_final_transform() * point - Vector2(main.position))
		motion.window_id = main.get_window_id(); motion.position = source_point; motion.global_position = source_point
		main.push_input(motion, true)
		await frames(tree)
		check(actor_target._highlight, "hierarchy drag highlights its target across the native window")
		click = InputEventMouseButton.new(); click.window_id = main.get_window_id(); click.button_index = MOUSE_BUTTON_LEFT; click.position = source_point; click.global_position = source_point; click.pressed = false
		main.push_input(click, true)
		await frames(tree)
		check(graph.node_by_id("actor").params.actor == "$world/guard", "main-editor hierarchy drag binds across the native suite window")
	# Capture the real rendered task graph in a fresh native editor process.
	panel.selected_id = "remove"; panel._rebuild(); panel.fit_graph(); await frames(tree, 10)
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var output := "res://docs/level_editor/scene_reference_2026-11-16"
		DirAccess.make_dir_recursive_absolute(output)
		suite.window.get_texture().get_image().save_png(output + "/节点拖放绑定.png")
	panel.dirty = false
	EditorInterface.get_selection().clear()
	EditorInterface.open_scene_from_path("res://content/scenes/main.tscn")
	await frames(tree, 12)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".uid")
	print("SCENE REFERENCE EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
