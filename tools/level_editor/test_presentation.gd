extends Node
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const PANEL := preload("res://addons/godot_level_editor/modules/godot_level_editor/graph_panel.gd")
const PRESENTATION := preload("res://addons/godot_level_editor/modules/godot_level_editor/node_presentation.gd")
var passed := 0
var failed := 0
func check(value: bool, title: String) -> void:
	if value: passed += 1
	else: failed += 1
	print("[PASS] " if value else "[FAIL] ", title)
func _ready() -> void:
	var panel := PANEL.new()
	add_child(panel)
	var graph := GRAPH.new()
	graph.graph_id = "presentation_only"
	for kind in GRAPH.PORTS:
		graph.nodes.append({"id": kind, "kind": kind, "label": GRAPH.display_label({"kind": kind}), "params": {}})
	var original := graph.snapshot()
	panel.open_graph(graph)
	await get_tree().process_frame
	var colors := {"condition": Color("976b36"), "trigger": Color("2b6535"), "state": Color("2b7278"), "action": Color("244568"), "data": Color("747c86"), "flow": Color("a56637")}
	for n in graph.nodes:
		var node: GraphNode = panel.canvas.get_node(n.id)
		var spec: Dictionary = GRAPH.PORTS[n.kind]
		var input_keys: Array = spec.in.keys()
		var output_keys: Array = spec.out.keys()
		var category := PRESENTATION.category_key(n.kind)
		var ports_ok := node.get_input_port_count() == input_keys.size() and node.get_output_port_count() == output_keys.size()
		for i in input_keys.size():
			ports_ok = ports_ok and node.get_input_port_slot(i) == i and node.get_input_port_type(i) == panel._port_type(spec.in[input_keys[i]]) and node.get_input_port_color(i) == panel._port_color(spec.in[input_keys[i]])
		for i in output_keys.size():
			ports_ok = ports_ok and node.get_output_port_slot(i) == i and node.get_output_port_type(i) == panel._port_type(spec.out[output_keys[i]]) and node.get_output_port_color(i) == panel._port_color(spec.out[output_keys[i]])
		check(ports_ok, n.kind + " preserves enabled connection indices, order, types and colors")
		check(node.get_node_or_null("PortDirections") == null, n.kind + " omits the redundant direction row without shifting ports")
		check(node.title == GRAPH.display_label(n) and node.get_theme_stylebox("titlebar").bg_color == colors[category] and node.get_theme_stylebox("titlebar_selected").bg_color == colors[category], n.kind + " keeps exact role color when selected")
		var row_ok := true
		for i in maxi(input_keys.size(), output_keys.size()):
			var row: HBoxContainer = node.get_child(i)
			row_ok = row_ok and row.get_node("OutputLabel").horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and not row.tooltip_text.is_empty()
		check(row_ok, n.kind + " aligns port names to the correct edge and retains hover hints")
	check(graph.snapshot() == original, "building and styling every node leaves all serialized graph data unchanged")
	check(not panel.legend.visible, "canvas omits persistent classification explanations")
	check(PRESENTATION.category_key("source") == "state" and PRESENTATION.category_key("latch") == "state" and PRESENTATION.category_key("goal") == "trigger", "continuous state and remembered state stay distinct from one-shot completion events")
	var packet := {"graph_id": graph.graph_id, "topology_id": "other", "world_id": "test", "values": {"source": true}, "persistent": {}, "local": {}, "reasons": {"source": "真实门已开启", "set_switch": "成功执行开关指令"}, "counts": {"set_switch": 1}}
	panel.receive_runtime("7:/instance", packet)
	var source: GraphNode = panel.canvas.get_node("source")
	var action: GraphNode = panel.canvas.get_node("set_switch")
	check(source.get_meta("runtime_active") and source.get_node("Runtime").text.contains("● 实际状态：是") and source.get_node("Runtime").text.contains("真实门已开启"), "actual value and reason drive a green activity indicator")
	check(action.get_meta("runtime_active") and action.get_node("Runtime").text.contains("执行 1 次"), "execution count changes produce an activity pulse without implying success")
	check(not action.get_node("Runtime").text.contains("实际状态：否") and action.get_node("Runtime").text.contains("成功执行开关指令"), "one-shot actions show actual executions and reason instead of a false continuous-state value")
	var source_fill: Color = source.get_theme_stylebox("panel").bg_color
	var title_color: Color = source.get_theme_stylebox("titlebar").bg_color
	source.selected = true
	panel.set_session_paused(7, true)
	check(source.get_theme_stylebox("titlebar_selected").bg_color == title_color and source.get_theme_stylebox("panel_selected").border_color == PRESENTATION.SHARED.ACTIVE and source.get_node("Runtime").text.contains("已暂停"), "selected paused nodes preserve category fill and mark activity on the border")
	packet.restored = true
	packet.values.source = false
	packet.counts.set_switch = 0
	panel.receive_runtime("7:/instance", packet)
	check(not source.get_meta("runtime_active") and not action.get_meta("runtime_active") and source.get_node("Runtime").text.contains("已恢复快照") and source.get_node("Runtime").text.contains("否"), "rewind refreshes actual values and clears obsolete execution pulses")
	check(source.get_theme_stylebox("titlebar").bg_color == title_color and source.get_theme_stylebox("panel").bg_color == source_fill, "rewind never recolors the category title or body")
	panel.clear_session(7)
	check(not source.get_node("Runtime").visible and not source.get_meta("runtime_active"), "stopping a session clears activity without changing the node role")
	check(graph.snapshot() == original, "selection, runtime display, pause and rewind never mutate graph resources")
	panel.queue_free()
	await get_tree().process_frame
	print("NODE PRESENTATION: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
