@tool
extends RefCounted
const TASK := preload("res://addons/godot_level_editor_narrative/runtime/task_definition.gd")
const SPEC := preload("res://addons/godot_level_editor_narrative/runtime/task_nodes.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)
func frames(tree: SceneTree, count := 3) -> void:
	for i in count: await tree.process_frame
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	suite._make_visible(true)
	suite.open_tab("任务图")
	suite.window.size = Vector2i(1504, 1000)
	await frames(tree, 8)
	var panel: Control = suite.modules.narrative.task_panel
	var original: Resource = panel.graph
	var original_dirty: bool = panel.dirty
	var original_binding: String = panel.bound_task_id
	var original_hash: String = original.semantic_hash()
	var graph := TASK.new()
	graph.graph_id = "all_task_nodes_editor_test"
	for kind in SPEC.DEFINITIONS:
		var p := SPEC.defaults(kind)
		if kind == "run_subgraph": p.graph_path = "res://resources/narrative/reception.task.tres"
		if kind == "task_fail": p.task = "1001001"
		graph.nodes.append({"id": "node_" + str(kind), "kind": kind, "params": p})
		graph.positions["node_" + str(kind)] = Vector2((graph.nodes.size() % 6) * 330, floori(graph.nodes.size() / 6.0) * 270)
	panel.dirty = false
	panel.open_graph(graph)
	await frames(tree)
	for n in graph.nodes:
		var card: GraphNode = panel.canvas.get_node(NodePath(n.id))
		check(card.get_input_port_count() == SPEC.PORTS[n.kind].in.size() and card.get_output_port_count() == SPEC.PORTS[n.kind].out.size(), "named typed ports render: " + str(n.kind))
		panel.selected_id = n.id
		panel._show_parameters()
		var editable := true
		for key in n.params:
			if not panel._fields.has(key): editable = false
		check(editable, "all authoring parameters are editable: " + str(n.kind))
	panel.search.text = "Equipped"
	panel._filter_choices()
	check(panel.choices.item_count == 2, "node search accepts English names")
	panel.search.text = "Inventory"
	panel._filter_choices()
	check(panel.choices.item_count == 2, "reused inventory query is searchable by its English name")
	panel.search.text = "并行"
	panel._filter_choices()
	check(panel.choices.item_count == 1, "node search accepts Chinese names")
	var count: int = graph.nodes.size()
	panel._add_choice()
	check(graph.nodes.size() == count + 1, "palette creates a configured flow node")
	panel.undo.undo()
	check(graph.nodes.size() == count, "new node creation supports undo")
	panel.undo.redo()
	check(graph.nodes.size() == count + 1, "new node creation supports redo")
	panel.selected_id = "node_timer"
	panel._show_parameters()
	panel._fields.seconds.value = 12.5
	panel._apply_parameters()
	check(graph.node_by_id("node_timer").params.seconds == 12.5, "flow parameters apply from the inspector")
	panel.undo.undo()
	check(graph.node_by_id("node_timer").params.seconds == 30.0, "parameter editing supports undo")
	# A complete small graph exercises native persistence and actual viewport layout.
	panel.dirty = false
	var example: Resource = load("res://resources/narrative/examples/generic_access.task.tres").duplicate(true)
	panel.open_graph(example)
	panel.bound_task_id = ""
	await frames(tree)
	check(example.validate().is_empty(), "delivered generic access example validates")
	var path := "user://task_nodes_editor_roundtrip.tres"
	check(ResourceSaver.save(example, path) == OK, "new nodes save in native graph resources")
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded != null and loaded.semantic_hash() == example.semantic_hash(), "save/reopen preserves all node parameters and named edges")
	panel.selected_id = "wear"
	panel._show_parameters()
	await frames(tree, 3)
	suite.window.size = Vector2i(1504, 1000)
	await frames(tree, 3)
	panel.fit_graph()
	await frames(tree, 8)
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var output := "res://docs/narrative_editor/task_nodes_2026-11-15"
		DirAccess.make_dir_recursive_absolute(output)
		suite.window.get_texture().get_image().save_png(output + "/任务节点.png")
		check(panel.canvas.size.x > 700 and panel.parameters.size.x > 200, "rendered graph retains usable canvas and parameter width")
	panel.dirty = false
	panel.open_graph(original)
	panel.bound_task_id = original_binding
	panel.dirty = original_dirty
	check(original.semantic_hash() == original_hash, "editor validation preserves the user's original graph")
	print("TASK NODES EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
