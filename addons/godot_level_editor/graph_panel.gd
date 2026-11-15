@tool
extends VBoxContainer
const GRAPH := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
const WORLD := preload("res://addons/godot_level_editor/runtime/world.gd")
const PRESENTATION := preload("res://addons/godot_level_editor/node_presentation.gd")
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
	_button(bar, "搜索添加", _show_picker)
	_button(bar, "整理节点", arrange_all)
	_button(bar, "复制", copy_selected)
	_button(bar, "粘贴", paste_selected)
	_button(bar, "删除", delete_selected)
	_button(bar, "撤销", func(): undo.undo())
	_button(bar, "重做", func(): undo.redo())
	_button(bar, "校验并保存", save_graph)
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
	preload("res://addons/godot_level_editor_suite/editor_style.gd").graph_canvas(canvas)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.right_disconnects = true
	canvas.show_arrange_button = false
	canvas.type_names = {1: "空间接口（双向）", 2: "布尔状态", 3: "一次事件", 4: "数值", 5: "对象引用"}
	split.add_child(canvas)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 285
	scroll.add_theme_stylebox_override("panel", preload("res://addons/godot_level_editor_suite/editor_style.gd").bordered(Color.WHITE))
	split.add_child(scroll)
	parameters = VBoxContainer.new()
	parameters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(parameters)
	canvas.connection_request.connect(connect_ports)
	canvas.disconnection_request.connect(disconnect_ports)
	canvas.node_selected.connect(_select_graph_node)
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
	picker.title = "搜索节点"
	picker.min_size = Vector2i(440, 380)
	add_child(picker)
	var list_box := VBoxContainer.new()
	picker.add_child(list_box)
	node_category = OptionButton.new()
	for category_name in ["全部节点", "触发 Trigger", "动作 Action", "判断 Condition", "状态 State", "数据／引用", "延迟／流程"]: node_category.add_item(category_name)
	node_category.item_selected.connect(func(_i: int): _filter_choices())
	list_box.add_child(node_category)
	search = LineEdit.new()
	search.placeholder_text = "按名称搜索"
	list_box.add_child(search)
	choices = ItemList.new()
	choices.custom_minimum_size.y = 280
	list_box.add_child(choices)
	search.text_changed.connect(func(_text: String): _filter_choices())
	picker.confirmed.connect(_add_choice)
	choices.item_activated.connect(func(_i: int): _add_choice(); picker.hide())

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
		status.text = "当前场景需要以关卡世界为根节点。可先打开首版连续世界。"
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
		if n.kind in ["npc_interact", "dialog_completed", "show_dialog", "task_start", "task_complete", "task_accept"]:
			var p: Dictionary = n.get("params", {})
			binding.text = str(p.get("npc", p.get("dialog_id", p.get("task", ""))))
			binding.custom_minimum_size.x = 210
			binding.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		binding.add_theme_color_override("font_color", PRESENTATION.SHARED.MUTED)
		node.add_child(binding)
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

func _filter_choices() -> void:
	choices.clear()
	for kind in GRAPH.labels():
		if (graph.graph_kind == "topology") != (kind == "port"): continue
		if GRAPH.TASK_NODES.DEFINITIONS.has(kind) and not graph.has_method("load_dialogue"): continue
		var label: String = GRAPH.labels()[kind]
		var wanted: String = ["", "trigger", "action", "condition", "state", "data", "flow"][node_category.selected]
		if not wanted.is_empty() and PRESENTATION.category_key(kind) != wanted: continue
		var english: String = GRAPH.TASK_NODES.english_name(kind)
		if search.text.is_empty() or (label + " " + str(kind) + " " + english).to_lower().contains(search.text.to_lower()):
			choices.add_item("【" + PRESENTATION.category_label(PRESENTATION.category_key(kind)) + "】" + label)
			choices.set_item_metadata(choices.item_count - 1, kind)
			choices.set_item_tooltip(choices.item_count - 1, english)
	if choices.item_count > 0: choices.select(0)

func _add_choice() -> void:
	if choices.get_selected_items().is_empty(): return
	var kind: String = choices.get_item_metadata(choices.get_selected_items()[0])
	var params := {}
	match kind:
		"start": params = {}
		"npc_interact": params = {"npc": "receptionist", "task": default_task_id()}
		"dialog_completed": params = {"dialog_id": "reception_intro", "task": default_task_id()}
		"show_dialog": params = {"dialog_id": "reception_intro"}
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

func _select_graph_node(node: Node) -> void:
	if _building or graph == null: return
	selected_id = str(node.name)
	_show_parameters()
	var n := graph.node_by_id(selected_id)
	if is_instance_valid(world) and not n.is_empty() and (n.get("params", {}).has("object") or n.get("params", {}).has("room")):
		var object: Node = world.object_by_id(str(n.params.get("object", "")))
		if n.params.has("room"):
			for room in world.rooms():
				if room.room_id == n.params.room: object = room
		if object != null:
			_syncing = true
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(object)
			EditorInterface.edit_node(object)
			_syncing = false

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
	if p.has("object"):
		var available := [""]
		if is_instance_valid(world):
			for id in world.objects():
				var obj: Node = world.object_by_id(id)
				if (n.kind == "port" and obj.get_script() == WORLD.PORT) or (n.kind in ["goal", "region_enter", "region_exit"] and obj.get_script() == WORLD.REGION) or (n.kind in ["source", "object", "set_switch", "enemy_patrol"] and obj.get_script() == WORLD.PLACE) or (n.kind in ["set_visibility", "object_interacted"] and obj is Node3D): available.append(id)
		_option_field("object", "三维场景对象", available, str(p.object))
		_button(parameters, "在三维视口选中对象", func(): _select_graph_node(canvas.get_node(NodePath(selected_id))); EditorInterface.set_main_screen_editor("3D"))
	if n.kind == "room_enter":
		var room_ids := [""]
		if is_instance_valid(world):
			for room in world.rooms(): room_ids.append(room.room_id)
		_option_field("room", "进入哪个房间？", room_ids, str(p.get("room", "")))
		_bool_field("once", "本次运行只触发一次", p.get("once", false))
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

func _reference_field(_key: String, _value: String) -> bool:
	return false

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
	return "meet_receptionist"
