@tool
extends VBoxContainer
signal definition_saved(path: String)
signal definition_opened(path: String)
signal focus_guard_requested
signal bind_guard_requested
signal create_route_requested

const Presentation := preload("res://addons/godot_level_editor/modules/enemy_editor/graph/node_presentation.gd")
const Template := preload("res://addons/godot_level_editor/modules/enemy_editor/runtime/guard_template.gd")
const Store := preload("res://addons/godot_level_editor/modules/enemy_editor/definition_store.gd")
const TEMPLATE_PATH := "res://addons/godot_level_editor/modules/enemy_editor/runtime/legacy_guard.tres"
const EVENT_LABELS := ["感知更新", "每帧思考", "听到噪音", "收到求援"]
const FACT_LABELS := ["看见目标", "有最后位置", "警觉值", "剩余时间"]
const OP_LABELS := ["等于", "不等于", "大于", "大于等于", "小于", "小于等于"]

var scene_validator: Callable
var definition: EnemyDefinition
var file_path := ""
var file_hash := ""
var dirty := false
var history := UndoRedo.new()
var selected_state := "patrol"
var selected_edge := ""
var graph: GraphEdit
var status: Label
var path_label: Label
var details: VBoxContainer
var edge_details: VBoxContainer
var edge_list: ItemList
var params: VBoxContainer
var tabs: TabContainer
var instances: OptionButton
var runtime_label: Label
var runtime: Dictionary = {}
var selected_instance := ""
var open_dialog: EditorFileDialog
var save_dialog: EditorFileDialog
var discard_dialog: ConfirmationDialog
var pending_action: Callable
var _drag_before: EnemyDefinition
var _saved_signature := ""
var search_dialog: ConfirmationDialog
var search_edit: LineEdit
var search_results: ItemList
var scene_label: Label
var _rebuilding := false
var _paused_sessions: Dictionary = {}
var _clipboard: Array[Dictionary] = []
var _clipboard_edges: Array[Dictionary] = []
var library_actions: Array[Button] = []
var workspaces: TabContainer
var appearance_panel: Control
var npc_scene_dialog: EditorFileDialog
var behavior_controls: Array[Control] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HFlowContainer.new()
	add_child(bar)
	library_actions.append(_button(bar, "守卫模板", func(): _guard_discard(_new_template)))
	library_actions.append(_button(bar, "打开", func(): _guard_discard(func(): open_dialog.popup_centered_ratio(0.65))))
	_button(bar, "重载", func():
		if not file_path.is_empty(): _guard_discard(func(): _load(file_path)))
	_button(bar, "保存", save)
	_button(bar, "另存为", func(): save_dialog.popup_centered_ratio(0.65))
	_button(bar, "撤销", func(): history.undo())
	_button(bar, "重做", func(): history.redo())
	_button(bar, "验证", _validate)
	_button(bar, "生成 NPC 素材…", _choose_npc_scene)
	behavior_controls.append(_button(bar, "+ 搜索节点", _show_search))
	behavior_controls.append(_button(bar, "复制", _copy_selected))
	behavior_controls.append(_button(bar, "粘贴", _paste_selected))
	path_label = Label.new()
	path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(path_label)
	var scene_bar := HFlowContainer.new()
	add_child(scene_bar)
	behavior_controls.append(scene_bar)
	_button(scene_bar, "绑定到所选守卫", func(): bind_guard_requested.emit())
	_button(scene_bar, "定位三维守卫", func(): focus_guard_requested.emit())
	_button(scene_bar, "创建巡逻路点", func(): create_route_requested.emit())
	scene_label = _label(scene_bar, "")
	var debug_bar := HBoxContainer.new()
	add_child(debug_bar)
	behavior_controls.append(debug_bar)
	_label(debug_bar, "运行实例")
	instances = OptionButton.new()
	instances.custom_minimum_size.x = 280
	debug_bar.add_child(instances)
	instances.item_selected.connect(func(index: int):
		selected_instance = str(instances.get_item_metadata(index))
		_highlight())
	runtime_label = _label(debug_bar, "")
	runtime_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	runtime_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	Presentation.add_legend(self)
	workspaces = TabContainer.new()
	workspaces.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(workspaces)
	appearance_panel = preload("res://addons/godot_level_editor/modules/enemy_editor/appearance_panel.gd").new()
	appearance_panel.name = "模型与动画"
	appearance_panel.appearance_changed.connect(_set_appearance)
	appearance_panel.operation_error.connect(func(message: String): status.text = message)
	workspaces.add_child(appearance_panel)
	var split := HSplitContainer.new()
	split.name = "行为图"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspaces.add_child(split)
	workspaces.tab_changed.connect(func(index: int):
		for control in behavior_controls: control.visible = index == 1)
	graph = GraphEdit.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size = Vector2(480, 440)
	graph.right_disconnects = true
	graph.add_valid_left_disconnect_type(0)
	graph.add_valid_right_disconnect_type(0)
	graph.show_arrange_button = false
	graph.connection_request.connect(_connect_nodes)
	graph.disconnection_request.connect(_disconnect_nodes)
	graph.delete_nodes_request.connect(_delete_nodes)
	graph.popup_request.connect(func(_position: Vector2): _show_search())
	graph.scroll_offset_changed.connect(func(_offset: Vector2): _capture_view())
	graph.gui_input.connect(_graph_input)
	graph.begin_node_move.connect(func(): _drag_before = definition.duplicate(true))
	graph.end_node_move.connect(_end_move)
	split.add_child(graph)
	tabs = TabContainer.new()
	tabs.custom_minimum_size.x = 330
	split.add_child(tabs)
	details = _tab("状态")
	var edge_tab := _tab("转换")
	edge_list = ItemList.new()
	edge_list.custom_minimum_size.y = 170
	edge_tab.add_child(edge_list)
	edge_list.item_selected.connect(func(index: int):
		selected_edge = str(edge_list.get_item_metadata(index))
		_render_edge())
	edge_details = VBoxContainer.new()
	edge_tab.add_child(edge_details)
	params = _tab("感知")
	status = _label(self, "")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	open_dialog = EditorFileDialog.new()
	open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	open_dialog.add_filter("*.tres", "敌人定义")
	open_dialog.file_selected.connect(_load)
	add_child(open_dialog)
	save_dialog = EditorFileDialog.new()
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	save_dialog.add_filter("*.tres", "敌人定义")
	save_dialog.current_path = "res://content/resources/enemies/my_npc.tres"
	save_dialog.file_selected.connect(_save_to)
	add_child(save_dialog)
	npc_scene_dialog = EditorFileDialog.new()
	npc_scene_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	npc_scene_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	npc_scene_dialog.add_filter("*.tscn", "NPC 场景")
	npc_scene_dialog.file_selected.connect(create_npc_scene)
	add_child(npc_scene_dialog)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.dialog_text = "有未保存修改。继续将丢弃这些修改。"
	discard_dialog.confirmed.connect(func():
		if pending_action.is_valid(): pending_action.call())
	add_child(discard_dialog)
	search_dialog = ConfirmationDialog.new()
	search_dialog.title = "搜索行为节点"
	search_dialog.ok_button_text = "添加节点"
	var search_box := VBoxContainer.new()
	search_dialog.add_child(search_box)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "搜索：巡逻 / 调查 / 追逐 / 停留"
	search_box.add_child(search_edit)
	search_results = ItemList.new()
	search_results.custom_minimum_size = Vector2(320, 180)
	search_box.add_child(search_results)
	search_edit.text_changed.connect(func(_value: String): _search_nodes())
	search_results.item_activated.connect(func(_index: int): _add_search_result())
	search_dialog.confirmed.connect(_add_search_result)
	add_child(search_dialog)
	_new_template()
	for control in behavior_controls: control.hide()

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Node, title: String) -> Label:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	return label

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _text(parent: Node, title: String, value: String, callback: Callable) -> LineEdit:
	_label(parent, title)
	var edit := LineEdit.new()
	edit.text = value
	parent.add_child(edit)
	edit.text_submitted.connect(func(text: String): callback.call(text))
	edit.focus_exited.connect(func(): callback.call(edit.text))
	return edit

func _number(parent: Node, title: String, value: float, callback: Callable, minimum := 0.0, step := 0.1) -> SpinBox:
	_label(parent, title)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = 100000
	spin.step = step
	spin.value = value
	parent.add_child(spin)
	spin.value_changed.connect(callback)
	return spin

func _choice(parent: Node, title: String, values: Array, value: String, callback: Callable, labels: Array = []) -> OptionButton:
	_label(parent, title)
	var select := OptionButton.new()
	for i in values.size():
		select.add_item(str(labels[i]) if labels.size() == values.size() else str(values[i]))
	select.select(maxi(values.find(value), 0))
	parent.add_child(select)
	select.item_selected.connect(func(index: int): callback.call(values[index]))
	return select

func _guard_discard(action: Callable) -> void:
	get_viewport().gui_release_focus()
	if dirty:
		pending_action = action
		discard_dialog.popup_centered()
	else:
		action.call()

func request_open(path: String) -> void:
	if path != file_path:
		_guard_discard(func(): _load(path))

func _new_template() -> void:
	definition = Template.create()
	file_path = ""
	file_hash = ""
	history.clear_history()
	selected_state = definition.initial_state
	selected_edge = ""
	_saved_signature = _signature()
	_refresh()
	status.text = ""

func _load(path: String) -> void:
	var loaded := Store.load_definition(path)
	if loaded == null:
		status.text = "打开失败：请选择 EnemyDefinition .tres。"
		return
	if not loaded.validate().is_empty():
		status.text = "打开失败：" + "；".join(loaded.validate())
		return
	definition = loaded
	file_path = path
	file_hash = FileAccess.get_sha256(path)
	_saved_signature = _signature()
	history.clear_history()
	selected_state = definition.initial_state
	selected_edge = ""
	_refresh()
	# GraphEdit stores view values at engine precision; opening is not an edit.
	definition.layout.scroll = graph.scroll_offset
	definition.layout.zoom = graph.zoom
	_saved_signature = _signature()
	_update_dirty()
	_validate()
	definition_opened.emit(path)

func save() -> void:
	get_viewport().gui_release_focus()
	if file_path.is_empty():
		save_dialog.popup_centered_ratio(0.65)
	else:
		_save_to(file_path)

func _save_to(path: String) -> void:
	get_viewport().gui_release_focus()
	_capture_view()
	if scene_validator.is_valid():
		var binding_errors: PackedStringArray = scene_validator.call()
		if not binding_errors.is_empty():
			status.text = "场景绑定无效：" + "；".join(binding_errors)
			return
	var result := Store.save_definition(definition, path, file_hash if path == file_path else "")
	if result != OK:
		status.text = "保存失败：文件已被其他编辑修改，请重载或另存。" if result == ERR_BUSY else "保存失败（%s）：%s" % [error_string(result), "；".join(definition.validate())]
		return
	file_path = path
	file_hash = FileAccess.get_sha256(path)
	_saved_signature = _signature()
	_update_dirty()
	status.text = "已保存：" + path
	definition_saved.emit(path)

func _signature() -> String:
	return _definition_signature(definition)

func _definition_signature(value: EnemyDefinition) -> String:
	return var_to_str([value.display_name, value.initial_state, value.states, value.transitions, value.parameters, value.layout, value.appearance.signature() if value.appearance != null else ""])

func _set_appearance(value: Resource) -> void:
	var before := definition.duplicate(true) as EnemyDefinition
	definition.appearance = value
	_record(before, "修改 NPC 模型与动画")
	status.text = "未保存"

func _choose_npc_scene() -> void:
	if file_path.is_empty() or dirty:
		status.text = "请先保存当前 NPC，再生成素材。"
		return
	npc_scene_dialog.current_path = "res://addons/godot_level_editor/scenes/npcs/" + file_path.get_file().get_basename() + ".tscn"
	npc_scene_dialog.popup_centered_ratio(0.65)

func create_npc_scene(path: String) -> bool:
	if file_path.is_empty() or dirty: status.text = "请先保存当前 NPC。"; return false
	if not path.begins_with("res://") or not path.ends_with(".tscn"): status.text = "请保存为项目内的 .tscn 场景。"; return false
	if FileAccess.file_exists(path): status.text = "同名场景已存在，请另选文件名。"; return false
	var root := preload("res://addons/godot_level_editor/modules/enemy_editor/runtime/npc_actor.tscn").instantiate()
	root.name = definition.display_name.validate_node_name()
	root.enemy_definition = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if definition.appearance != null:
		var model_root := root.get_node("ModelRoot")
		model_root.set_script(preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd"))
		model_root.npc_definition = root.enemy_definition
	var packed := PackedScene.new()
	var result := packed.pack(root)
	root.free()
	if result == OK: result = ResourceSaver.save(packed, path)
	if result != OK: status.text = "生成 NPC 素材失败：" + error_string(result); return false
	EditorInterface.get_resource_filesystem().scan()
	status.text = "已生成 NPC 素材：" + path
	return true

func _update_dirty() -> void:
	dirty = _signature() != _saved_signature
	path_label.text = ("● " if dirty else "") + (file_path if not file_path.is_empty() else "未保存模板")

func _record(before: EnemyDefinition, title := "编辑敌人") -> void:
	if _definition_signature(before) == _signature():
		return
	history.create_action(title)
	history.add_do_method(_apply_snapshot.bind(definition.duplicate(true)))
	history.add_undo_method(_apply_snapshot.bind(before))
	history.commit_action(false)
	_update_dirty()
	_render_graph()
	_render_edges()

func _apply_snapshot(snapshot: EnemyDefinition) -> void:
	definition = snapshot.duplicate(true)
	_refresh()

func _refresh() -> void:
	_update_dirty()
	appearance_panel.bind(definition.appearance, file_path)
	_render_graph()
	_render_state()
	_render_edges()
	_render_edge()
	_render_parameters()

func _render_graph() -> void:
	_rebuilding = true
	graph.clear_connections()
	for child in graph.get_children():
		if child is GraphNode:
			graph.remove_child(child)
			child.queue_free()
	for s in definition.states:
		var node := GraphNode.new()
		node.name = "s_" + str(s.id)
		node.title = Presentation.title(str(s.label), s.id == definition.initial_state, false, "")
		Presentation.apply_state(node)
		node.position_offset = definition.layout.nodes.get(s.id, Vector2.ZERO)
		node.custom_minimum_size.x = 290
		Presentation.add_ports(node)
		var label := Label.new()
		label.name = "DefinitionParameters"
		label.add_theme_font_size_override("font_size", 16)
		label.text = "%s · [状态转换]\n%s · %.1f m/s · %.1f s" % [s.id, s.behavior, s.speed, s.duration]
		label.add_theme_color_override("font_color", Presentation.TEXT)
		node.add_child(label)
		var value := Label.new()
		value.name = "RuntimeValue"
		node.add_child(value)
		var metrics := Label.new()
		metrics.name = "RuntimeMetrics"
		metrics.add_theme_color_override("font_color", Presentation.TEXT)
		node.add_child(metrics)
		node.node_selected.connect(func():
			get_viewport().gui_release_focus()
			selected_state = str(s.id)
			tabs.current_tab = 0
			_render_state())
		graph.add_child(node)
	for t in definition.transitions:
		var from := "s_" + str(t.from)
		var to := "s_" + str(t.to)
		if not graph.is_node_connected(from, 0, to, 0): graph.connect_node(from, 0, to, 0)
	graph.scroll_offset = definition.layout.scroll
	graph.zoom = float(definition.layout.zoom)
	_rebuilding = false
	_highlight()

func _render_state() -> void:
	_clear(details)
	var s := definition.state_by_id(selected_state)
	if s.is_empty():
		_label(details, "点击画布节点编辑；拖动端口创建转换。")
		return
	_label(details, "状态 ID：" + selected_state)
	_text(details, "显示名称（回车应用）", s.label, func(value: String): _set_state("label", value))
	_choice(details, "行为", EnemyDefinition.BEHAVIORS, s.behavior, func(value: String): _set_state("behavior", value), ["巡逻路点", "前往最后位置", "追踪目标", "原地停留"])
	_number(details, "移动速度 m/s", s.speed, func(value: float): _set_state("speed", value))
	_number(details, "进入时计时 s", s.duration, func(value: float): _set_state("duration", value))
	_number(details, "到位张望 °/s", s.scan_degrees, func(value: float): _set_state("scan_degrees", value))
	_button(details, "设为初始状态", func():
		var before: EnemyDefinition = definition.duplicate(true)
		definition.initial_state = selected_state
		_record(before))
	_button(details, "删除状态及相关转换", func(): _delete_nodes(["s_" + selected_state]))

func _set_state(key: String, value: Variant) -> void:
	var s := definition.state_by_id(selected_state)
	if s.is_empty() or s.get(key) == value: return
	var before: EnemyDefinition = definition.duplicate(true)
	s[key] = value
	_record(before)

func add_state() -> void:
	var before: EnemyDefinition = definition.duplicate(true)
	var id := _unique_id("state", definition.states)
	var entry := Template._state(id, "新状态", "idle", 0.0, 1.0, 0.0, Vector2.ZERO)
	entry.erase("position")
	definition.states.append(entry)
	definition.layout.nodes[id] = graph.scroll_offset / graph.zoom + Vector2(160, 180)
	selected_state = id
	_record(before, "添加状态")
	_render_state()

func _unique_id(prefix: String, entries: Array[Dictionary]) -> String:
	var count := 1
	var ids: Array = entries.map(func(entry: Dictionary): return entry.id)
	while ids.has(prefix + str(count)): count += 1
	return prefix + str(count)

func _delete_nodes(names: Array) -> void:
	var ids: Array[String] = []
	for node_name in names: ids.append(str(node_name).trim_prefix("s_"))
	if ids.has(definition.initial_state):
		status.text = "不能删除初始状态；请先指定另一个初始状态。"
		return
	var before: EnemyDefinition = definition.duplicate(true)
	for id in ids: definition.layout.nodes.erase(id)
	definition.states = definition.states.filter(func(s: Dictionary): return not ids.has(str(s.id)))
	definition.transitions = definition.transitions.filter(func(t: Dictionary): return not ids.has(str(t.from)) and not ids.has(str(t.to)))
	_record(before, "删除状态")
	_render_state()
	_render_edge()

func _end_move() -> void:
	for child in graph.get_children():
		if child is GraphNode:
			definition.layout.nodes[str(child.name).trim_prefix("s_")] = child.position_offset
	if _drag_before != null: _record(_drag_before, "移动节点")
	_drag_before = null

func _connect_nodes(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
	var a := str(from).trim_prefix("s_")
	var b := str(to).trim_prefix("s_")
	if definition.state_by_id(a).is_empty() or definition.state_by_id(b).is_empty(): return
	var before: EnemyDefinition = definition.duplicate(true)
	selected_edge = _unique_id("edge", definition.transitions)
	definition.transitions.append(Template._edge(selected_edge, a, b, "tick", 10, [Template._c("timer", "le", 0.0)]))
	_record(before, "添加转换")
	tabs.current_tab = 1
	_render_edge()

func _disconnect_nodes(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
	var before: EnemyDefinition = definition.duplicate(true)
	definition.transitions = definition.transitions.filter(func(t: Dictionary): return not ("s_" + str(t.from) == str(from) and "s_" + str(t.to) == str(to)))
	_record(before, "断开状态转换")
	_render_edge()
	status.text = "已断开连线并删除该连线的转换规则；可撤销。"

func _render_edges() -> void:
	edge_list.clear()
	for t in definition.transitions:
		var index := edge_list.add_item("%s → %s  [%s P%s]" % [t.from, t.to, EVENT_LABELS[EnemyDefinition.EVENTS.find(t.event)], t.priority])
		edge_list.set_item_metadata(index, t.id)
		if t.id == selected_edge: edge_list.select(index)

func _edge() -> Dictionary:
	for t in definition.transitions:
		if t.id == selected_edge: return t
	return {}

func _set_edge(key: String, value: Variant) -> void:
	var edge := _edge()
	if edge.is_empty() or edge.get(key) == value: return
	var before: EnemyDefinition = definition.duplicate(true)
	edge[key] = value
	_record(before)

func _render_edge() -> void:
	_clear(edge_details)
	var edge := _edge()
	if edge.is_empty():
		_label(edge_details, "拖动节点端口连线；从列表选择规则。")
		return
	_label(edge_details, "转换 ID：" + selected_edge)
	var ids: Array = definition.states.map(func(s: Dictionary): return s.id)
	_choice(edge_details, "从", ids, edge.from, func(value: String): _set_edge("from", value))
	_choice(edge_details, "到", ids, edge.to, func(value: String): _set_edge("to", value))
	_choice(edge_details, "事件", EnemyDefinition.EVENTS, edge.event, func(value: String): _set_edge("event", value), EVENT_LABELS)
	_number(edge_details, "优先级（大者优先；同值按列表顺序）", edge.priority, func(value: float): _set_edge("priority", int(value)), -100000.0, 1.0)
	_choice(edge_details, "转换效果", ["none", "expose"], edge.effect, func(value: String): _set_edge("effect", value), ["无", "暴露：扣能量并求援"])
	_label(edge_details, "以下条件全部满足才转换（AND）")
	for index in edge.conditions.size():
		_render_condition(index, edge.conditions[index])
	_button(edge_details, "+ 条件", func():
		var before: EnemyDefinition = definition.duplicate(true)
		_edge().conditions.append(Template._c("timer", "le", 0.0))
		_record(before)
		_render_edge())
	_button(edge_details, "规则上移（同优先级先判断）", func(): _move_edge(-1))
	_button(edge_details, "规则下移", func(): _move_edge(1))
	_button(edge_details, "删除此转换", func():
		var before: EnemyDefinition = definition.duplicate(true)
		definition.transitions.erase(_edge())
		selected_edge = ""
		_record(before)
		_render_edge())

func _render_condition(index: int, c: Dictionary) -> void:
	var box := VBoxContainer.new()
	edge_details.add_child(box)
	_choice(box, "条件 %d" % (index + 1), EnemyDefinition.FACTS.keys(), c.fact, func(value: String):
		var before: EnemyDefinition = definition.duplicate(true)
		var condition: Dictionary = _edge().conditions[index]
		condition.fact = value
		condition.op = "eq"
		condition.value = true if EnemyDefinition.FACTS[value] == TYPE_BOOL else 0.0
		_record(before)
		_render_edge(), FACT_LABELS)
	var boolean: bool = EnemyDefinition.FACTS[c.fact] == TYPE_BOOL
	_choice(box, "比较", ["eq", "ne"] if boolean else EnemyDefinition.OPS, c.op, func(value: String): _set_condition(index, "op", value), OP_LABELS.slice(0, 2) if boolean else OP_LABELS)
	if boolean:
		_choice(box, "值", ["true", "false"], str(c.value), func(value: String): _set_condition(index, "value", value == "true"), ["是", "否"])
	else:
		_number(box, "值", c.value, func(value: float): _set_condition(index, "value", value), -100000.0)
	_button(box, "移除此条件", func():
		var before: EnemyDefinition = definition.duplicate(true)
		_edge().conditions.remove_at(index)
		_record(before)
		_render_edge())

func _set_condition(index: int, key: String, value: Variant) -> void:
	var before: EnemyDefinition = definition.duplicate(true)
	_edge().conditions[index][key] = value
	_record(before)

func _move_edge(direction: int) -> void:
	var index := definition.transitions.find(_edge())
	var next := clampi(index + direction, 0, definition.transitions.size() - 1)
	if index == next: return
	var before: EnemyDefinition = definition.duplicate(true)
	var edge := _edge()
	definition.transitions.remove_at(index)
	definition.transitions.insert(next, edge)
	_record(before)

func _render_parameters() -> void:
	_clear(params)
	_text(params, "敌人定义名称", definition.display_name, func(value: String):
		var before: EnemyDefinition = definition.duplicate(true)
		definition.display_name = value
		_record(before))
	var labels := {"alert_rate": "警觉累积 /s", "alert_decay": "警觉衰减 /s", "noise_alert": "噪音初始警觉", "help_radius": "求援半径 m", "waypoint_wait": "巡逻点停留 s"}
	for key in EnemyDefinition.PARAM_DEFAULTS:
		if key == "expose_penalty": continue # Preserve old data without offering the removed energy mechanic.
		_number(params, labels[key], definition.parameters[key], func(value: float):
			var before: EnemyDefinition = definition.duplicate(true)
			definition.parameters[key] = value
			_record(before))

func _validate() -> void:
	var errors := definition.validate()
	if scene_validator.is_valid(): errors.append_array(scene_validator.call())
	var warnings := definition.warnings()
	status.text = "验证通过：%d 个状态 / %d 条转换。%s" % [definition.states.size(), definition.transitions.size(), "；".join(warnings)] if errors.is_empty() else "验证失败：" + "；".join(errors)

func receive_runtime(key: String, packet: Dictionary) -> void:
	runtime[key] = packet
	_rebuild_instances()
	_highlight()

func remove_runtime(key: String) -> void:
	runtime.erase(key)
	_rebuild_instances()
	_highlight()

func clear_session(session_id: int) -> void:
	_paused_sessions.erase(session_id)
	for key in runtime.keys():
		if int(runtime[key].get("session", -1)) == session_id: runtime.erase(key)
	_rebuild_instances()
	_highlight()

func _rebuild_instances() -> void:
	instances.clear()
	instances.get_parent().visible = not runtime.is_empty()
	for key in runtime:
		instances.add_item(str(runtime[key].instance) + " [会话 %s]" % runtime[key].get("session", 0))
		instances.set_item_metadata(instances.item_count - 1, key)
	if not runtime.has(selected_instance): selected_instance = str(runtime.keys()[0]) if not runtime.is_empty() else ""
	for i in instances.item_count:
		if instances.get_item_metadata(i) == selected_instance: instances.select(i)

func _highlight() -> void:
	if runtime_label == null: return
	var packet: Dictionary = runtime.get(selected_instance, {})
	var expected_path := file_path if not file_path.is_empty() else TEMPLATE_PATH
	var matching: bool = not packet.is_empty() and packet.get("definition", "") == expected_path
	var mode := "回溯冻结" if packet.get("rewound", false) else ("暂停" if _paused_sessions.get(int(packet.get("session", -1)), false) else "运行中")
	var reason := str(packet.get("last_reason", packet.get("last_transition", "尚无转换")))
	for child in graph.get_children():
		if child is GraphNode:
			var active: bool = matching and str(child.name) == "s_" + str(packet.get("state_id", ""))
			var id := str(child.name).trim_prefix("s_")
			child.title = Presentation.title(str(definition.state_by_id(id).get("label", id)), id == definition.initial_state, active, mode)
			var value := "剩余 %.2f s · 警觉 %.1f" % [packet.get("timer", 0.0), packet.get("alert", 0.0)] if active else ("非活动状态" if matching else "")
			Presentation.show_runtime(child, active, mode, value, "最近转换原因：" + reason if active else "")
	for i in edge_list.item_count:
		var active: bool = matching and edge_list.get_item_metadata(i) == packet.get("last_transition", "")
		edge_list.set_item_custom_fg_color(i, Color("16956b") if active else edge_list.get_theme_color("font_color"))
	runtime_label.tooltip_text = "实例 %s\n定义 %s\n行为 %s · 速度 %s m/s\n状态 %s · 剩余 %s s\n警觉 %s · 看见目标 %s\n最近转换 %s" % [packet.get("instance", ""), packet.get("definition", ""), packet.get("behavior", ""), packet.get("speed", 0.0), packet.get("state_id", ""), packet.get("timer", 0.0), packet.get("alert", 0.0), packet.get("seen", false), packet.get("last_reason", packet.get("last_transition", ""))]
	if packet.is_empty():
		runtime_label.text = ""
	elif not matching:
		runtime_label.text = "实例使用其他定义：" + str(packet.get("definition", ""))
	else:
		runtime_label.text = "%s · %.2f s · %s%s%s" % [packet.get("state_id", ""), packet.get("timer", 0.0), str(packet.get("last_transition", "")) + " · 警觉 %.1f · 视野 %s" % [packet.get("alert", 0.0), packet.get("seen", false)], " · " + mode, " · 未保存草稿" if dirty else ""]


func _capture_view() -> void:
	if _rebuilding or definition == null: return
	definition.layout.scroll = graph.scroll_offset
	definition.layout.zoom = graph.zoom
	_update_dirty()

func _graph_input(event: InputEvent) -> void:
	if event is InputEventMouseButton: _capture_view.call_deferred()
	if event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed):
		match event.keycode:
			KEY_C: _copy_selected()
			KEY_V: _paste_selected()
			KEY_Z:
				if event.shift_pressed: history.redo()
				else: history.undo()
		graph.accept_event()

func _show_search() -> void:
	search_edit.text = ""
	_search_nodes()
	search_dialog.popup_centered()
	search_edit.grab_focus()

func _search_nodes() -> void:
	search_results.clear()
	var labels := ["巡逻路点 patrol", "调查最后位置 investigate", "追逐目标 chase", "原地停留 idle"]
	for i in EnemyDefinition.BEHAVIORS.size():
		if search_edit.text.is_empty() or labels[i].to_lower().contains(search_edit.text.to_lower()):
			var index := search_results.add_item(labels[i])
			search_results.set_item_metadata(index, EnemyDefinition.BEHAVIORS[i])
	if search_results.item_count > 0: search_results.select(0)

func _add_search_result() -> void:
	var selection := search_results.get_selected_items()
	if selection.is_empty(): return
	var behavior := str(search_results.get_item_metadata(selection[0]))
	var before: EnemyDefinition = definition.duplicate(true)
	var id := _unique_id("state", definition.states)
	var entry := Template._state(id, search_results.get_item_text(selection[0]).get_slice(" ", 0), behavior, 0.0 if behavior == "idle" else 2.0, 1.0, 0.0, Vector2.ZERO)
	entry.erase("position")
	definition.states.append(entry)
	definition.layout.nodes[id] = graph.scroll_offset / graph.zoom + Vector2(160, 180)
	selected_state = id
	_record(before, "添加行为节点")
	_render_state()
	search_dialog.hide()

func _copy_selected() -> void:
	_clipboard.clear()
	_clipboard_edges.clear()
	var ids: Array[String] = []
	for child in graph.get_children():
		if child is GraphNode and child.selected:
			var id := str(child.name).trim_prefix("s_")
			var entry := definition.state_by_id(id).duplicate(true)
			entry["position"] = definition.layout.nodes.get(id, Vector2.ZERO)
			_clipboard.append(entry)
			ids.append(id)
	for edge in definition.transitions:
		if ids.has(str(edge.from)) and ids.has(str(edge.to)): _clipboard_edges.append(edge.duplicate(true))
	status.text = "已复制 %d 个节点与 %d 条内部转换。" % [_clipboard.size(), _clipboard_edges.size()]

func _paste_selected() -> void:
	if _clipboard.is_empty(): return
	var before: EnemyDefinition = definition.duplicate(true)
	var remap := {}
	for old in _clipboard:
		var entry := old.duplicate(true)
		var id := _unique_id("state", definition.states)
		remap[old.id] = id
		entry.id = id
		entry.label = str(entry.label) + " 副本"
		definition.layout.nodes[id] = entry.position + Vector2(60, 60)
		entry.erase("position")
		definition.states.append(entry)
	for old in _clipboard_edges:
		var edge := old.duplicate(true)
		edge.id = _unique_id("edge", definition.transitions)
		edge.from = remap[old.from]
		edge.to = remap[old.to]
		definition.transitions.append(edge)
	_record(before, "粘贴状态子图")
	status.text = "已粘贴，节点与转换已分配新 ID。"

func set_scene_guard_label(text: String) -> void:
	scene_label.text = text


func _exit_tree() -> void:
	if get_meta("godot_level_editor_reparenting", false): return
	if is_instance_valid(history): history.free()


func set_session_paused(session_id: int, paused: bool) -> void:
	if paused: _paused_sessions[session_id] = true
	else: _paused_sessions.erase(session_id)
	_highlight()
