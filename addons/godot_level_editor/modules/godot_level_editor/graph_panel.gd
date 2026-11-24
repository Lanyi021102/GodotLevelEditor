@tool
extends VBoxContainer
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const PRESENTATION := preload("res://addons/godot_level_editor/modules/godot_level_editor/node_presentation.gd")
const SCENE_REFERENCE := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_reference.gd")
const REFERENCE_DROP := preload("res://addons/godot_level_editor/modules/godot_level_editor/reference_drop.gd")
var plugin: EditorPlugin
var world: Node
var graph: GodotLevelEditorLevelGraph
var undo := UndoRedo.new()
var canvas: GraphEdit
var mode: OptionButton
var status: Label
var parameters: VBoxContainer
var picker: ConfirmationDialog
var search: LineEdit
var choices: ItemList
var node_category: OptionButton
var node_picker: RefCounted
var selected_id := ""
var dirty := false
var _fields: Dictionary = {}
var _move_before: Dictionary = {}
var _clipboard: Dictionary = {}
var _building := false
var _arranging := false
var _syncing := false
var _add_position := Vector2(100, 100)
var _packets: Dictionary = {}
var sessions: OptionButton
var _active_key := ""
var legend: HFlowContainer
var _pulse_deadlines: Dictionary = {}
var _paused_sessions: Dictionary = {}

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HFlowContainer.new()
	add_child(bar)
	_button(bar, "使用当前世界", use_current_world)
	mode = OptionButton.new()
	mode.add_item("房间连接图 · 空间接口")
	mode.add_item("目标事件图 · 布尔 / 事件")
	bar.add_child(mode)
	mode.item_selected.connect(func(_i: int): _switch_graph())
	_button(bar, "添加节点", _show_picker)
	_button(bar, "保存", save_graph)
	_button(bar, "撤销", func(): undo.undo())
	_button(bar, "重做", func(): undo.redo())
	_button(bar, "适合画布", fit_graph)
	_button(bar, "整理节点", arrange_all)
	_button(bar, "复制", copy_selected)
	_button(bar, "粘贴", paste_selected)
	_button(bar, "删除", delete_selected)
	_button(bar, "保存后重载", save_reload)
	legend = HFlowContainer.new()
	legend.name = "NodeCategoryLegend"
	legend.add_theme_constant_override("h_separation", 18)
	add_child(legend)
	legend.hide()
	for key in PRESENTATION.CATEGORIES:
		var item := Label.new()
		item.text = "● " + PRESENTATION.category_label(key)
		item.add_theme_color_override("font_color", PRESENTATION.CATEGORIES[key].color)
		item.tooltip_text = PRESENTATION.HINTS[key]
		legend.add_child(item)
	var direction_hint := Label.new()
	direction_hint.text = "左侧输入 → 右侧输出 · 标题色＝职责，连线色＝类型"
	legend.add_child(direction_hint)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	canvas = GraphEdit.new()
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd").graph_canvas(canvas)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.right_disconnects = true
	canvas.show_arrange_button = false
	canvas.type_names = {1: "空间接口（双向）", 2: "布尔状态", 3: "一次事件", 4: "数值", 5: "对象引用"}
	split.add_child(canvas)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 285
	scroll.add_theme_stylebox_override("panel", preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd").bordered(Color.WHITE))
	split.add_child(scroll)
	parameters = VBoxContainer.new()
	parameters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(parameters)
	canvas.connection_request.connect(connect_ports)
	canvas.disconnection_request.connect(disconnect_ports)
	canvas.node_selected.connect(_select_graph_node)
	canvas.node_deselected.connect(func(node: Node):
		if not _building and selected_id == str(node.name):
			_sync_canvas_selection.call_deferred())
	canvas.delete_nodes_request.connect(func(_ids: Array[StringName]): delete_selected())
	canvas.copy_nodes_request.connect(copy_selected)
	canvas.paste_nodes_request.connect(paste_selected)
	canvas.duplicate_nodes_request.connect(func(): copy_selected(); paste_selected())
	canvas.begin_node_move.connect(func(): _move_before = graph.snapshot() if graph != null else {})
	canvas.end_node_move.connect(_end_move)
	canvas.popup_request.connect(func(at: Vector2): _add_position = (at + canvas.scroll_offset) / canvas.zoom; _show_picker())
	canvas.scroll_offset_changed.connect(func(at: Vector2):
		if not _building and graph != null:
			graph.view_scroll = at
			graph.view_zoom = canvas.zoom)
	var runtime_bar := HBoxContainer.new()
	runtime_bar.hide()
	add_child(runtime_bar)
	var label := Label.new()
	label.text = "运行实例："
	runtime_bar.add_child(label)
	sessions = OptionButton.new()
	sessions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	runtime_bar.add_child(sessions)
	sessions.item_selected.connect(func(i: int): _active_key = str(sessions.get_item_metadata(i)); _update_runtime())
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = ""
	add_child(status)
	picker = ConfirmationDialog.new()
	add_child(picker)
	node_picker = preload("res://addons/godot_level_editor/modules/godot_level_editor/node_picker.gd").new()
	node_picker.build(self, picker)

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)

func use_current_world() -> void:
	if dirty:
		status.text = "请先保存当前图，或撤销修改，再切换世界。"
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.get_script() != WORLD:
		status.text = "请在“关卡 → 我的关卡”中打开目标关卡场景。"
		return
	world = root
	_switch_graph()

func _switch_graph() -> void:
	if not is_instance_valid(world):
		return
	if dirty:
		mode.select(0 if graph == world.topology else 1)
		status.text = "请先保存当前图，再切换。"
		return
	open_graph(world.topology if mode.selected == 0 else world.events)

func open_graph(source: GodotLevelEditorLevelGraph) -> void:
	if source == null:
		return
	if dirty and source != graph:
		status.text = "当前图有未保存修改。"
		return
	graph = source
	undo.clear_history()
	dirty = false
	selected_id = ""
	_rebuild()
	status.text = ""

func _port_type(value: String) -> int:
	return {"space": 1, "bool": 2, "event": 3, "number": 4, "object": 5}.get(value, 0)

func _port_color(value: String) -> Color:
	return {"space": Color("5485a5"), "bool": Color("438b80"), "event": Color("244b74"), "number": Color("b8874a"), "object": Color("777e88")}.get(value, Color.WHITE)

func _rebuild() -> void:
	if canvas == null:
		return
	_building = true
	canvas.clear_connections()
	for node in canvas.get_children():
		if node is GraphNode:
			node.free()
	if graph == null:
		_building = false
		return
	for n in graph.nodes:
		if GRAPH.ports(n.kind).is_empty():
			continue
		var node := GraphNode.new()
		node.name = n.id
		node.title = GRAPH.display_label(n)
		PRESENTATION.apply(node, n.kind)
		node.position_offset = graph.positions.get(n.id, Vector2.ZERO)
		node.custom_minimum_size.x = 235
		canvas.add_child(node)
		for title_label in node.get_titlebar_hbox().get_children():
			if title_label is Label:
				var font: Font = title_label.get_theme_font("font")
				var font_size: int = title_label.get_theme_font_size("font_size")
				node.custom_minimum_size.x = clampf(font.get_string_size(node.title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 64, 235, 560)
		var inp: Dictionary = GRAPH.ports(n.kind).in
		var out: Dictionary = GRAPH.ports(n.kind).out
		var inputs := inp.keys()
		var outputs := out.keys()
		# This heading has no enabled slots. GraphEdit port indices still enumerate
		# only actual inputs/outputs in the original definition order.
		for i in maxi(inputs.size(), outputs.size()):
			var left: String = str(inputs[i]) if i < inputs.size() else ""
			var right: String = str(outputs[i]) if i < outputs.size() else ""
			var input_text := str(GRAPH.PORT_LABELS.get(left, left)) if left != "" else ""
			var output_text := str(GRAPH.PORT_LABELS.get(right, right)) if right != "" else ""
			if n.kind in ["parallel", "wait_all", "wait_any"]:
				if left in ["a", "b", "c", "d"]: input_text = "分支 " + left.to_upper()
				if right in ["a", "b", "c", "d"]: output_text = "分支 " + right.to_upper()
			var hint := ("输入 %s：%s\n" % [left, GRAPH.TYPE_LABELS[inp[left]]] if left != "" else "") + ("输出 %s：%s\n" % [right, GRAPH.TYPE_LABELS[out[right]]] if right != "" else "") + "事件表示发生一次；是／否表示持续条件。相同类型才能连接。空间接口为双向连接。"
			var row := PRESENTATION.port_row(input_text, output_text, hint)
			node.add_child(row)
			node.set_slot(i, left != "", _port_type(inp.get(left, "")), _port_color(inp.get(left, "")), right != "", _port_type(out.get(right, "")), _port_color(out.get(right, "")))
		var binding := Label.new()
		binding.text = _friendly("object", str(n.get("params", {}).get("object", n.get("params", {}).get("room", n.get("params", {}).get("key", "")))))
		if n.kind in ["npc_interact", "dialog_completed", "show_dialog", "task_start", "task_complete", "task_accept", "play_performance"]:
			var p: Dictionary = n.get("params", {})
			binding.text = str(p.get("npc", p.get("dialog_id", p.get("task", ""))))
			if n.kind == "play_performance":
				var names := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sequence.gd").choices(world)
				binding.text = str(names.get(p.get("performance", ""), "请选择演出"))
			binding.custom_minimum_size.x = 210
			binding.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		binding.add_theme_color_override("font_color", PRESENTATION.SHARED.MUTED)
		var reference_keys := SCENE_REFERENCE.keys(n)
		if reference_keys.is_empty(): node.add_child(binding)
		else:
			var references := VBoxContainer.new()
			references.name = "SceneReferences"
			node.add_child(references)
			for key in reference_keys: references.add_child(_reference_drop(n, key))
			if reference_keys.has("actor") and n.params.has("key"): references.add_child(binding)
			else: binding.free()
		var runtime := Label.new()
		runtime.name = "Runtime"
		runtime.text = ""
		runtime.hide()
		runtime.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		runtime.custom_minimum_size = Vector2(210, 58)
		runtime.max_lines_visible = 5
		node.add_child(runtime)
		node.selected = n.id == selected_id
	for e in graph.edges:
		var a := graph.node_by_id(e.from)
		var b := graph.node_by_id(e.to)
		if a.is_empty() or b.is_empty() or GRAPH.ports(a.kind).is_empty() or GRAPH.ports(b.kind).is_empty(): continue
		var ap: int = GRAPH.ports(a.kind).out.keys().find(e.from_port)
		var bp: int = GRAPH.ports(b.kind).in.keys().find(e.to_port)
		if ap >= 0 and bp >= 0:
			canvas.connect_node(e.from, ap, e.to, bp)
	canvas.scroll_offset = graph.view_scroll
	canvas.zoom = graph.view_zoom
	_building = false
	_show_parameters()
	_refresh_sessions()
	_update_runtime()

func _commit(name_text: String, before: Dictionary, after: Dictionary) -> void:
	if before == after: return
	undo.create_action(name_text)
	undo.add_do_method(_apply.bind(graph, after))
	undo.add_undo_method(_apply.bind(graph, before))
	undo.commit_action()

func _apply(target: GodotLevelEditorLevelGraph, state: Dictionary) -> void:
	target.apply_snapshot(state)
	dirty = true
	if target == graph: _rebuild()

func connect_ports(a: StringName, ap: int, b: StringName, bp: int) -> void:
	if graph == null: return
	var source := graph.node_by_id(str(a))
	var target := graph.node_by_id(str(b))
	if source.is_empty() or target.is_empty(): return
	var from_ports: Dictionary = GRAPH.ports(source.kind).out
	var to_ports: Dictionary = GRAPH.ports(target.kind).in
	if ap >= from_ports.size() or bp >= to_ports.size(): return
	var fp: String = from_ports.keys()[ap]
	var tp: String = to_ports.keys()[bp]
	if from_ports[fp] != to_ports[tp]:
		status.text = "端口类型不匹配；事件与布尔值需要显式转换节点。"
		return
	var before := graph.snapshot()
	var after := graph.snapshot()
	after.edges.append({"id": GRAPH.fresh_id("edge"), "from": str(a), "from_port": fp, "to": str(b), "to_port": tp})
	var trial: GodotLevelEditorLevelGraph = graph.duplicate(true)
	trial.apply_snapshot(after)
	var errors := trial.validate()
	if not errors.is_empty():
		status.text = "; ".join(errors)
		return
	_commit("连接节点", before, after)

func disconnect_ports(a: StringName, ap: int, b: StringName, bp: int) -> void:
	if graph == null: return
	var source := graph.node_by_id(str(a))
	var target := graph.node_by_id(str(b))
	if source.is_empty() or target.is_empty(): return
	var fp: String = GRAPH.ports(source.kind).out.keys()[ap]
	var tp: String = GRAPH.ports(target.kind).in.keys()[bp]
	var after := graph.snapshot()
	for i in range(after.edges.size() - 1, -1, -1):
		var edge: Dictionary = after.edges[i]
		if edge.from == str(a) and edge.to == str(b) and edge.from_port == fp and edge.to_port == tp:
			after.edges.remove_at(i)
	_commit("断开节点", graph.snapshot(), after)

func _end_move() -> void:
	if _arranging: return
	if graph == null or _move_before.is_empty(): return
	var after := graph.snapshot()
	for node in canvas.get_children():
		if node is GraphNode: after.positions[str(node.name)] = node.position_offset
	_commit("移动图节点", _move_before, after)
	_move_before = {}

func _selected() -> Array[String]:
	var ids: Array[String] = []
	for node in canvas.get_children():
		if node is GraphNode and node.selected: ids.append(str(node.name))
	return ids

func copy_selected() -> void:
	if graph == null: return
	_clipboard = {"nodes": [], "edges": [], "positions": {}, "kind": graph.graph_kind}
	var ids := _selected()
	for n in graph.nodes:
		if ids.has(n.id):
			_clipboard.nodes.append(n.duplicate(true))
			_clipboard.positions[n.id] = graph.positions.get(n.id, Vector2.ZERO)
	for e in graph.edges:
		if ids.has(e.from) and ids.has(e.to): _clipboard.edges.append(e.duplicate(true))

func paste_selected() -> void:
	if graph == null or _clipboard.is_empty() or _clipboard.kind != graph.graph_kind: return
	var after := graph.snapshot()
	var remap := {}
	for source in _clipboard.nodes:
		var n: Dictionary = source.duplicate(true)
		var id := GRAPH.fresh_id()
		remap[n.id] = id
		after.positions[id] = _clipboard.positions.get(n.id, Vector2.ZERO) + Vector2(50, 50)
		n.id = id
		if n.kind == "port": n.params.object = "" # Explicitly rebind a copied spatial endpoint.
		after.nodes.append(n)
	for source in _clipboard.edges:
		var e: Dictionary = source.duplicate(true)
		e.id = GRAPH.fresh_id("edge")
		e.from = remap[e.from]
		e.to = remap[e.to]
		after.edges.append(e)
	_commit("粘贴节点（新 ID）", graph.snapshot(), after)

func delete_selected() -> void:
	if graph == null: return
	var ids := _selected()
	var after := graph.snapshot()
	after.nodes = after.nodes.filter(func(n: Dictionary): return not ids.has(n.id))
	after.edges = after.edges.filter(func(e: Dictionary): return not ids.has(e.from) and not ids.has(e.to))
	for id in ids: after.positions.erase(id)
	selected_id = ""
	_commit("删除节点及连线", graph.snapshot(), after)

func _show_picker() -> void:
	if graph == null: return
	search.text = ""
	node_category.select(0)
	_filter_choices()
	picker.popup_centered()
	search.grab_focus()

func _can_offer_node(_kind: String) -> bool:
	return true

func _filter_choices() -> void:
	if node_picker != null: node_picker.filter()

func _add_choice() -> void:
	if choices.get_selected_items().is_empty(): return
	var kind: String = choices.get_item_metadata(choices.get_selected_items()[0])
	if not GRAPH.labels().has(kind): return
	var params := {}
	match kind:
		"start": params = {}
		"npc_interact": params = {"npc": "", "task": default_task_id()}
		"dialog_completed": params = {"dialog_id": "", "task": default_task_id()}
		"show_dialog": params = {"dialog_id": ""}
		"play_performance": params = {"performance": ""}
		"task_start", "task_complete": params = {"task": default_task_id()}
		"region_enter": params = {"object": "", "once": false}
		"room_enter": params = {"room": "", "once": false}
		"event_received": params = {"key": "新事件", "once": false}
		"emit_event": params = {"key": "新事件"}
		"set_switch", "set_visibility": params = {"object": "", "enabled": true}
		"enemy_patrol": params = {"object": ""}
		"kill_player": params = {"reason": "关卡事件"}
		"player_state": params = {"state": "alive"}
		"has_item": params = {"key": "key"}
		"source": params = {"object": "", "query": "powered"}
		"goal": params = {"object": "", "persistent": true}
		"port": params = {"object": ""}
		"object": params = {"object": ""}
		"read_state": params = {"query": "powered"}
		"number": params = {"value": 1.0}
		"latch": params = {"persistent": true}
		"constant": params = {"value": false}
		"unlock": params = {"link": ""}
		"objective": params = {"text": "新目标"}
	if GRAPH.TASK_NODES.DEFINITIONS.has(kind): params = GRAPH.TASK_NODES.defaults(kind)
	if kind == "task_fail": params.task = default_task_id()
	if kind == "has_item": params = {"key": "key", "actor": "", "amount": 1}
	params = _node_parameters(kind, params)
	if is_instance_valid(world):
		var selected := EditorInterface.get_selection().get_selected_nodes()
		if selected.size() == 1:
			if params.has("room") and selected[0].get_script() == WORLD.ROOM: params.room = selected[0].room_id
			if params.has("object"):
				for reference in world.objects():
					if world.object_by_id(reference) == selected[0]: params.object = reference
	var after := graph.snapshot()
	var id := GRAPH.fresh_id()
	after.nodes.append({"id": id, "kind": kind, "label": GRAPH.labels()[kind], "params": params})
	after.positions[id] = _add_position
	selected_id = id
	_commit("添加节点", graph.snapshot(), after)

func _node_parameters(_kind: String, params: Dictionary) -> Dictionary:
	return params

func _sync_canvas_selection() -> void:
	if not is_instance_valid(canvas): return
	var current := canvas.get_node_or_null(NodePath(selected_id)) if not selected_id.is_empty() else null
	if current is GraphNode and current.selected: return
	selected_id = ""
	for card in canvas.get_children():
		if card is GraphNode and card.selected:
			selected_id = str(card.name)
			break
	_show_parameters()

func _select_graph_node(node: Node) -> void:
	if _building or graph == null: return
	selected_id = str(node.name)
	_show_parameters()
	var n := graph.node_by_id(selected_id)
	if not is_instance_valid(world) or n.is_empty(): return
	for key in SCENE_REFERENCE.keys(n):
		var ref := str(n.params.get(key, ""))
		if ref.is_empty(): continue
		var object: Node = SCENE_REFERENCE.choices(world, graph, n, key).get(ref)
		if object != null:
			_syncing = true
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(object)
			EditorInterface.edit_node(object)
			_syncing = false
			break

func focus_object(object: Node) -> void:
	if _syncing or graph == null or not is_instance_valid(world): return
	var object_id := ""
	for id in world.objects():
		if world.object_by_id(id) == object: object_id = id
	for n in graph.nodes:
		if (n.get("params", {}).get("object", "") == object_id and not object_id.is_empty()) or (object.get_script() == WORLD.ROOM and n.get("params", {}).get("room", "") == object.room_id):
			selected_id = n.id
			for node in canvas.get_children():
				if node is GraphNode: node.selected = str(node.name) == selected_id
			canvas.scroll_offset = graph.positions.get(selected_id, Vector2.ZERO) * canvas.zoom - canvas.size * 0.35
			_show_parameters()
			return

func _show_parameters() -> void:
	for child in parameters.get_children(): child.queue_free()
	_fields.clear()
	if graph == null: return
	var n := graph.node_by_id(selected_id)
	if n.is_empty(): return
	var title := Label.new()
	title.text = GRAPH.display_label(n)
	title.tooltip_text = str(n.id)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parameters.add_child(title)
	_text_field("label", "显示名称", GRAPH.display_label(n))
	var p: Dictionary = n.get("params", {})
	for field_key in ["task", "npc", "dialog_id"]:
		if p.has(field_key) and not _reference_field(field_key, str(p[field_key])): _text_field(field_key, {"task": "任务 ID", "npc": "NPC 对象 ID", "dialog_id": "Comment／对白 ID"}[field_key], str(p[field_key]))
	if p.has("performance"):
		var names := {"": "请选择演出"}
		names.merge(preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sequence.gd").choices(world))
		var current := str(p.performance)
		if not current.is_empty() and not names.has(current): names[current] = "未找到演出"
		_option_field("performance", "演出", names.keys(), current)
		for index in _fields.performance.item_count:
			_fields.performance.set_item_text(index, names[_fields.performance.get_item_metadata(index)])
	if p.has("object"):
		var available := [""] + SCENE_REFERENCE.choices(world, graph, n, "object").keys()
		_option_field("object", "三维场景对象", available, str(p.object))
		_button(parameters, "在三维视口选中对象", func(): _select_graph_node(canvas.get_node(NodePath(selected_id))); EditorInterface.set_main_screen_editor("3D"))
	if n.kind in ["room_enter", "room_exit", "room_active"]:
		var room_ids := [""]
		if is_instance_valid(world):
			for room in world.rooms(): room_ids.append(room.room_id)
		_option_field("room", "Room", room_ids, str(p.get("room", "")))
		if n.kind == "room_active": _bool_field("expected", "期望已激活", p.get("expected", true))
		else: _bool_field("once", "本次运行只触发一次", p.get("once", false))
	if n.kind in ["event_received", "emit_event", "has_item"]:
		_text_field("key", "道具名称／标识" if n.kind == "has_item" else "事件名称", str(p.get("key", "")))
	if n.kind in ["event_received", "region_enter"]: _bool_field("once", "本次运行只触发一次", p.get("once", false))
	if n.kind in ["set_switch", "set_visibility"]: _bool_field("enabled", "打开开关" if n.kind == "set_switch" else "显示物件", p.get("enabled", true))
	if n.kind == "kill_player":
		_text_field("reason", "击杀原因", str(p.get("reason", "关卡事件")))
		var hint := Label.new()
		hint.text = "调用玩家关卡接口。未接入时从“失败”端口继续，原因显示在节点下方。"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parameters.add_child(hint)
	if n.kind == "player_state": _option_field("state", "检测哪种状态？", ["alive", "crouching", "moving", "on_floor"], str(p.get("state", "alive")))
	if n.kind == "unlock":
		var links := [""]
		if is_instance_valid(world) and world.topology != null:
			for edge in world.topology.edges: links.append(edge.id)
		_option_field("link", "控制空间连线", links, str(p.get("link", "")))
	if n.kind in ["source", "read_state"]: _option_field("query", "状态读取（布尔）", ["powered", "open"], str(p.get("query", "powered")))
	if n.kind in ["goal", "latch"]: _bool_field("persistent", "作为世界永久进度", p.get("persistent", true))
	if n.kind == "constant": _bool_field("value", "布尔值", p.get("value", false))
	if n.kind == "number":
		var field := SpinBox.new()
		field.min_value = -1000000
		field.max_value = 1000000
		field.step = 0.1
		field.value = float(p.get("value", 0))
		parameters.add_child(field)
		_fields["value"] = field
	if n.kind == "objective": _text_field("text", "目标文字", str(p.get("text", "")))
	if GRAPH.TASK_NODES.DEFINITIONS.has(n.kind) or n.kind == "has_item":
		for key in p:
			if _fields.has(key) or key == "object": continue
			var caption: String = GRAPH.TASK_NODES.FIELD_LABELS.get(key, key)
			if key == "actor":
				var ids: Array = [""]
				if is_instance_valid(world): ids.append_array(world.objects().keys())
				if not str(p[key]).is_empty() and not ids.has(p[key]): ids.append(p[key])
				_option_field(key, caption, ids, str(p[key]))
				_fields[key].set_item_text(0, "玩家")
			elif key in ["type", "status", "operator"]:
				_option_field(key, caption, {"type": ["bool", "number"], "status": ["active", "completed", "failed"], "operator": ["==", "!=", ">", ">=", "<", "<="]}[key], str(p[key]))
			elif p[key] is bool: _bool_field(key, caption, p[key])
			elif p[key] is float or p[key] is int:
				var label := Label.new()
				label.text = caption
				parameters.add_child(label)
				var field := SpinBox.new()
				field.min_value = -1000000
				field.max_value = 1000000
				field.step = 1.0 if p[key] is int else 0.1
				field.value = p[key]
				parameters.add_child(field)
				_fields[key] = field
			else: _text_field(key, caption, str(p[key]))
	_button(parameters, "应用参数", _apply_parameters)

func _reference_field(key: String, value: String) -> bool:
	if key == "dialog_id" and graph.has_method("load_dialogue"):
		var result: Dictionary = graph.call("load_dialogue")
		var names := {"": "请选择对白"}
		if result.get("library") != null:
			for group in result.library.groups:
				for comment in group.comments:
					names[comment.id] = str(group.name) + " › " + str(comment.name)
					if graph.node_by_id(selected_id).kind == "dialog_completed":
						for line in comment.lines: names[line.id] = str(comment.name) + " › " + str(line.text).left(32)
		if not value.is_empty() and not names.has(value): names[value] = "未找到　" + value
		_option_field(key, "对白段落或单句" if graph.node_by_id(selected_id).kind == "dialog_completed" else "对白段落", names.keys(), value)
		for i in _fields[key].item_count:
			_fields[key].set_item_text(i, names[_fields[key].get_item_metadata(i)])
		return true
	if key == "npc":
		_option_field(key, "NPC 对象", [""] + SCENE_REFERENCE.choices(world, graph, graph.node_by_id(selected_id), key).keys(), value)
		return true
	return false

func _reference_drop(definition: Dictionary, key: String) -> Control:
	var target := REFERENCE_DROP.new()
	target.name = key
	var current := str(definition.params.get(key, ""))
	var display := _friendly(key, current)
	if current.is_empty() and key == "actor": display = "玩家（拖入可替换）"
	target.setup(SCENE_REFERENCE.CAPTIONS[key], display, _resolve_reference_drop.bind(graph, str(definition.id), key), _accept_reference_drop.bind(graph, str(definition.id), key))
	return target

func _resolve_reference_drop(data: Variant, source: Resource, id: String, key: String) -> String:
	if source != graph or not is_instance_valid(world): return ""
	var root := EditorInterface.get_edited_scene_root()
	if root == null or (root != world and not root.is_ancestor_of(world)): return ""
	var definition := graph.node_by_id(id)
	if definition.is_empty(): return ""
	return SCENE_REFERENCE.resolve(world, graph, definition, key, data)

func _accept_reference_drop(data: Variant, source: Resource, id: String, key: String) -> void:
	var reference := _resolve_reference_drop(data, source, id, key)
	if reference.is_empty(): return
	selected_id = id
	var after := graph.snapshot()
	for definition in after.nodes:
		if definition.id != id: continue
		definition.params[key] = reference
		if key == "mechanism":
			for description in SCENE_REFERENCE.ACCESS.descriptions(world):
				if description.reference != reference: continue
				for dependent in ["state", "from_state", "to_state", "action"]:
					if not definition.params.has(dependent): continue
					var available: Array = description.actions if dependent == "action" else description.requestable if definition.kind == "mechanism_request_state" and dependent == "state" else description.states
					if not available.has(definition.params[dependent]): definition.params[dependent] = ""
	var before := graph.snapshot()
	if before == after: _rebuild()
	else: _commit("拖入绑定" + str(SCENE_REFERENCE.CAPTIONS[key]), before, after)
	status.text = "已绑定：" + _friendly(key, reference)

func _text_field(key: String, label_text: String, value: String) -> void:
	var label := Label.new()
	label.text = label_text
	parameters.add_child(label)
	var field := LineEdit.new()
	field.text = value
	parameters.add_child(field)
	_fields[key] = field

func _bool_field(key: String, text: String, value: bool) -> void:
	var field := CheckBox.new()
	field.text = text
	field.button_pressed = value
	parameters.add_child(field)
	_fields[key] = field

func _option_field(key: String, text: String, options: Array, current: String) -> void:
	# A missing world must not silently clear an existing serialized reference.
	if SCENE_REFERENCE.CAPTIONS.has(key) and not current.is_empty() and not options.has(current):
		options = options.duplicate()
		options.append(current)
	var label := Label.new()
	label.text = text
	parameters.add_child(label)
	var field := OptionButton.new()
	for option in options:
		field.add_item(_friendly(key, str(option)) if str(option) != "" else "请选择")
		field.set_item_metadata(field.item_count - 1, str(option))
		if str(option) == current: field.select(field.item_count - 1)
	parameters.add_child(field)
	_fields[key] = field
	if SCENE_REFERENCE.CAPTIONS.has(key):
		parameters.add_child(_reference_drop(graph.node_by_id(selected_id), key))

func _friendly(key: String, value: String) -> String:
	var names := {"alive": "存活", "crouching": "潜行／蹲下", "moving": "正在移动", "clone": "是分身", "on_floor": "站在地面", "powered": "机关已开启／供电", "open": "门已完全打开"}
	if names.has(value): return names[value]
	if is_instance_valid(world):
		if key == "room" or not value.contains("/"):
			for room in world.rooms():
				if room.room_id == value: return room.display_name
		if key == "link" and world.topology != null:
			for edge in world.topology.edges:
				if edge.id == value:
					return _friendly("object", str(world.topology.node_by_id(edge.from).params.object)) + " ↔ " + _friendly("object", str(world.topology.node_by_id(edge.to).params.object))
		var obj: Node = world.object_by_id(value)
		if obj != null:
			var parent := obj.get_parent()
			return (str(parent.get("display_name")) if parent.get("display_name") is String else "世界") + " · " + str(obj.name)
	return value

func _apply_parameters() -> void:
	if selected_id.is_empty(): return
	var after := graph.snapshot()
	for n in after.nodes:
		if n.id != selected_id: continue
		for key in _fields:
			var field: Control = _fields[key]
			var value: Variant
			if field is CheckBox: value = field.button_pressed
			elif field is SpinBox: value = field.value
			elif field is OptionButton: value = field.get_item_metadata(field.selected)
			elif field.has_method("value"): value = field.value()
			else: value = field.text
			if key == "label": n.label = value
			else: n.params[key] = int(value) if n.params.get(key) is int else value
	_commit("编辑节点参数", graph.snapshot(), after)

func save_graph() -> bool:
	if graph == null: return false
	var errors := graph.validate()
	if is_instance_valid(world): errors.append_array(world.validate())
	if not errors.is_empty():
		status.text = "未保存：" + "; ".join(errors)
		return false
	if graph.resource_path.is_empty():
		status.text = "图需要先指定 .tres 路径。"
		return false
	graph.view_scroll = canvas.scroll_offset
	graph.view_zoom = canvas.zoom
	var err := ResourceSaver.save(graph, graph.resource_path)
	if err != OK:
		status.text = "保存失败：" + error_string(err)
		return false
	dirty = false
	status.text = "已保存：" + graph.resource_path
	return true

func save_reload() -> void:
	if not save_graph(): return
	var fresh: GodotLevelEditorLevelGraph = ResourceLoader.load(graph.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if fresh == null or not fresh.validate().is_empty():
		status.text = "磁盘重载校验失败。"
		return
	graph.apply_snapshot(fresh.snapshot())
	_rebuild()
	status.text = "已从磁盘重载，节点、连线、参数与排版保持有效。"

func receive_runtime(key: String, packet: Dictionary) -> void:
	var previous: Dictionary = _packets.get(key, {})
	var pulses: Dictionary = _pulse_deadlines.get(key, {})
	if packet.get("restored", false):
		pulses.clear()
	else:
		for id in packet.get("counts", {}):
			if int(packet.counts[id]) > int(previous.get("counts", {}).get(id, 0)): pulses[id] = Time.get_ticks_msec() + 1000
	_pulse_deadlines[key] = pulses
	_packets[key] = packet
	_refresh_sessions()
	_update_runtime()

func remove_runtime(key: String) -> void:
	_packets.erase(key)
	_pulse_deadlines.erase(key)
	_refresh_sessions()
	_update_runtime()

func clear_session(session: int) -> void:
	for key in _packets.keys():
		if str(key).begins_with(str(session) + ":"):
			_packets.erase(key)
			_pulse_deadlines.erase(key)
	_paused_sessions.erase(session)
	_refresh_sessions()
	_update_runtime()

func set_session_paused(session: int, paused: bool) -> void:
	_paused_sessions[session] = paused
	_update_runtime()

func _process(_delta: float) -> void:
	var changed := false
	for key in _pulse_deadlines:
		if _paused_sessions.get(int(str(key).get_slice(":", 0)), false): continue
		var pulses: Dictionary = _pulse_deadlines[key]
		for id in pulses.keys():
			if Time.get_ticks_msec() >= int(pulses[id]): pulses.erase(id); changed = true
	if changed: _update_runtime()

func _refresh_sessions() -> void:
	sessions.clear()
	var visible_keys := []
	for key in _packets:
		var packet: Dictionary = _packets[key]
		if graph == null or (packet.graph_id != graph.graph_id and packet.topology_id != graph.graph_id): continue
		if is_instance_valid(world) and packet.world_id != world.world_id: continue
		sessions.add_item(str(key))
		visible_keys.append(key)
		sessions.set_item_metadata(sessions.item_count - 1, key)
		if key == _active_key: sessions.select(sessions.item_count - 1)
	sessions.get_parent().visible = sessions.item_count > 0
	if sessions.item_count == 0:
		_active_key = ""
	elif not visible_keys.has(_active_key):
		_active_key = str(sessions.get_item_metadata(0))

func _update_runtime() -> void:
	if canvas == null: return
	var packet: Dictionary = _packets.get(_active_key, {})
	for node in canvas.get_children():
		if not node is GraphNode: continue
		var label: Label = node.get_node("Runtime")
		var id := str(node.name)
		label.text = ""
		label.visible = not packet.is_empty()
		var active := false
		if not packet.is_empty():
			var definition := graph.node_by_id(id)
			var output_types: Array = GRAPH.ports(str(definition.get("kind", ""))).get("out", {}).values()
			var continuous: bool = definition.get("kind") == "port" or output_types.has("bool") or output_types.has("number") or output_types.has("object")
			var value: Variant = packet.values.get(id, packet.persistent.get(id, packet.local.get(id, "执行 %d 次" % int(packet.get("counts", {}).get(id, 0)))))
			var display_value := ("是" if value else "否") if value is bool else str(value)
			var recent: bool = _pulse_deadlines.get(_active_key, {}).has(id)
			active = (continuous and value is bool and value) or recent
			label.text = ("● " if active else "") + ("实际状态：%s" % display_value if continuous else "执行 %d 次" % int(packet.get("counts", {}).get(id, 0)))
			if continuous and packet.get("counts", {}).has(id): label.text += " · 执行 %d 次" % int(packet.counts[id])
			if definition.get("kind") == "branch" and packet.local.has("$branch:" + id): label.text += " · 最近条件" + ("成立" if packet.local["$branch:" + id] else "不成立")
			label.text += "\n" + str(packet.reasons.get(id, ""))
			if _paused_sessions.get(int(_active_key.get_slice(":", 0)), false): label.text += "\n已暂停 · 保留最近实际状态"
			if packet.get("restored", false): label.text += "\n已恢复快照"
			var revision: String = str(packet.get("event_revision" if graph.graph_kind == "events" else "topology_revision", graph.semantic_hash()))
			if revision != graph.semantic_hash(): label.text += "\n当前编辑图已改动；显示启动时定义"
		label.tooltip_text = label.text
		PRESENTATION.show_runtime(node, active)
		node.reset_size.call_deferred()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event.ctrl_pressed or event.meta_pressed:
		if event.keycode == KEY_Z:
			if event.shift_pressed: undo.redo()
			else: undo.undo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S:
			save_graph()
			get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if get_meta("godot_level_editor_reparenting", false): return
	undo.clear_history()
	undo.free()

func arrange_all() -> void:
	if graph == null or _arranging: return
	_arranging = true
	var target := graph
	await get_tree().process_frame
	await get_tree().process_frame
	if target != graph:
		_arranging = false
		return
	var before := graph.snapshot()
	var selected := _selected()
	_arranging = true
	_building = true
	for node in canvas.get_children():
		if node is GraphNode: node.selected = true
	canvas.arrange_nodes()
	await get_tree().process_frame
	var after := graph.snapshot()
	for node in canvas.get_children():
		if node is GraphNode:
			after.positions[str(node.name)] = node.position_offset
			node.selected = selected.has(str(node.name))
	_building = false
	_arranging = false
	_move_before = {}
	_commit("整理节点排版", before, after)

func default_task_id() -> String:
	return ""

func fit_graph() -> void:
	if graph == null or graph.nodes.is_empty(): return
	await get_tree().process_frame
	var bounds := Rect2()
	var first := true
	for card in canvas.get_children():
		if not card is GraphNode: continue
		var rect := Rect2(card.position_offset, card.size)
		bounds = rect if first else bounds.merge(rect)
		first = false
	if first: return
	canvas.zoom = clampf(minf((canvas.size.x - 80) / bounds.size.x, (canvas.size.y - 120) / bounds.size.y), canvas.zoom_min, 1.0)
	canvas.scroll_offset = bounds.position * canvas.zoom - Vector2(40, 80)
