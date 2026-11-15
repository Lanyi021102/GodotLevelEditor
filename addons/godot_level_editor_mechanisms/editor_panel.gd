@tool
extends VBoxContainer
const Schema := preload("res://addons/godot_level_editor_mechanisms/graph/schema.gd")
const Presentation := preload("res://addons/godot_level_editor_mechanisms/graph/node_presentation.gd")
const Assembly := preload("res://addons/godot_level_editor_mechanisms/runtime/assembly.gd")
const Factory := preload("res://addons/godot_level_editor_mechanisms/factory.gd")
const Store := preload("res://addons/godot_level_editor_mechanisms/store.gd")
var plugin: EditorPlugin
var assembly: Node3D
var graph: GraphEdit
var details: VBoxContainer
var status: Label
var path_label: Label
var runtime_label: Label
var runtime_choice: OptionButton
var runtime_packets := {}
var selected_runtime := ""
var selected_id := ""
var dirty := false
var _moving_before: Resource
var _clipboard: Array[String] = []
var _syncing := false
var _popup_position := Vector2(70, 70)
var _picker: ConfirmationDialog
var _search: LineEdit
var _kinds: ItemList
var _save_dialog: EditorFileDialog
var _open_dialog: EditorFileDialog
var _reload_dialog: ConfirmationDialog
var _new_file := false
var _known_hash := ""
var _skip_native_save := false
var _viewport: SubViewport
var _camera: Camera3D
var _preview: Node3D
var _preview_running := false
var _preview_accumulator := 0.0
var _preview_plate := false
var plate_button: CheckBox
var _preview_status: Label
var _angle := 0.65
var _distance := 9.0
var _focus := Vector3(0, 1.8, 0)
var library_actions: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HFlowContainer.new()
	add_child(bar)
	library_actions.append(_button(bar, "新建组合", func(): _new_file = true; _save_dialog.popup_centered_ratio(0.6)))
	library_actions.append(_button(bar, "打开", func(): _open_dialog.popup_centered_ratio(0.6)))
	library_actions.append(_button(bar, "示例", func(): EditorInterface.open_scene_from_path("res://scenes/mechanisms/lever_plate_door.tscn")))
	_button(bar, "重载", _request_reload)
	_button(bar, "保存", save)
	_button(bar, "另存为", func(): _new_file = false; _save_dialog.popup_centered_ratio(0.6))
	_button(bar, "验证", _validate)
	_button(bar, "撤销", func(): _history(false))
	_button(bar, "重做", func(): _history(true))
	_button(bar, "+ 节点", func(): _show_picker(Vector2(60, 100)))
	_button(bar, "适应图", func(): _fit_graph())
	path_label = _label(self, "")
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 16)
	add_child(legend)
	legend.hide()
	for info in Presentation.CATEGORIES.values():
		var item := _label(legend, "● " + str(info.label))
		item.add_theme_color_override("font_color", info.color)
		item.tooltip_text = info.hint
	_label(legend, "左侧输入 → 右侧输出").tooltip_text = "节点标题颜色表示职责；端口和连线颜色表示数据类型。"
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	graph = GraphEdit.new()
	graph.custom_minimum_size = Vector2(520, 430)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.right_disconnects = true
	graph.connection_request.connect(_connect_nodes)
	graph.disconnection_request.connect(_disconnect_nodes)
	graph.delete_nodes_request.connect(_delete_nodes)
	graph.duplicate_nodes_request.connect(func(): _duplicate_nodes(_selected_nodes()))
	graph.copy_nodes_request.connect(func(): _clipboard = _selected_nodes())
	graph.paste_nodes_request.connect(func(): _duplicate_nodes(_clipboard))
	graph.node_selected.connect(_select_graph_node)
	graph.begin_node_move.connect(func():
		if is_instance_valid(assembly): _moving_before = assembly.definition.duplicate(true))
	graph.end_node_move.connect(_end_move)
	graph.scroll_offset_changed.connect(func(_offset: Vector2): _view_changed())
	graph.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed: _view_changed.call_deferred())
	graph.popup_request.connect(_show_picker)
	split.add_child(graph)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	split.add_child(side)
	var preview_bar := HBoxContainer.new()
	side.add_child(preview_bar)
	_button(preview_bar, "预览 / 停止", _toggle_preview)
	_button(preview_bar, "模拟交互", _preview_interact)
	plate_button = CheckBox.new()
	plate_button.text = "踩板"
	plate_button.toggled.connect(func(value: bool):
		_preview_plate = value
		_update_preview_plate())
	preview_bar.add_child(plate_button)
	_button(preview_bar, "复位", _reset_preview)
	var viewport_box := SubViewportContainer.new()
	viewport_box.custom_minimum_size = Vector2(330, 235)
	viewport_box.stretch = true
	side.add_child(viewport_box)
	viewport_box.gui_input.connect(_orbit)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_box.add_child(_viewport)
	_setup_world()
	_preview_status = _label(side, "隔离预览；左拖旋转，滚轮缩放")
	_preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_status.hide()
	_button(side, "定位三维对象 / 检查器编辑", _focus_object)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details)
	var runtime_bar := HBoxContainer.new()
	add_child(runtime_bar)
	runtime_choice = OptionButton.new()
	runtime_choice.custom_minimum_size.x = 330
	runtime_bar.add_child(runtime_choice)
	runtime_choice.item_selected.connect(func(index: int):
		selected_runtime = str(runtime_choice.get_item_metadata(index)); _display_trace())
	runtime_label = _label(runtime_bar, "")
	runtime_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status = _label(self, "")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_make_dialogs()
	_rebuild_runtime_choices()

func _make_dialogs() -> void:
	_picker = ConfirmationDialog.new()
	_picker.title = "添加机关节点"
	_picker.min_size = Vector2i(400, 420)
	_picker.get_ok_button().text = "添加"
	var box := VBoxContainer.new()
	_picker.add_child(box)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索节点名称 / AND / event / number"
	box.add_child(_search)
	_kinds = ItemList.new()
	_kinds.custom_minimum_size.y = 320
	box.add_child(_kinds)
	_search.text_changed.connect(_filter_kinds)
	_kinds.item_activated.connect(func(_index: int): _add_selected_kind(); _picker.hide())
	_picker.confirmed.connect(_add_selected_kind)
	add_child(_picker)
	_save_dialog = EditorFileDialog.new()
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.add_filter("*.tscn", "独立机关场景（同时保存 .graph.tres）")
	_save_dialog.current_path = "res://scenes/mechanisms/new_mechanism.tscn"
	_save_dialog.file_selected.connect(_save_to)
	add_child(_save_dialog)
	_open_dialog = EditorFileDialog.new()
	_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_open_dialog.add_filter("*.tscn", "机关场景")
	_reload_dialog = ConfirmationDialog.new()
	_reload_dialog.dialog_text = "重新载入磁盘上的场景与图定义，将丢弃本场景未保存修改。"
	_reload_dialog.confirmed.connect(_reload_current)
	add_child(_reload_dialog)
	_open_dialog.file_selected.connect(func(path: String): EditorInterface.open_scene_from_path(path))
	add_child(_open_dialog)

func bind_scene(root: Node) -> void:
	assembly = root if root is Assembly else null
	selected_id = ""
	dirty = false
	_skip_native_save = false
	_preview_running = false
	if is_instance_valid(assembly):
		assembly.configure()
		_known_hash = _disk_hash(assembly.scene_file_path)
	_render()
	_refresh_preview()

func _render() -> void:
	if graph == null: return
	_syncing = true
	graph.clear_connections()
	for child in graph.get_children():
		if child is GraphNode:
			graph.remove_child(child)
			child.queue_free()
	if not is_instance_valid(assembly) or assembly.definition == null or not assembly.definition.has_method("find_node"):
		path_label.text = ""
		_clear(details)
		_syncing = false
		return
	var definition: Resource = assembly.definition
	path_label.text = ("● " if dirty else "") + definition.display_name + "  |  " + assembly.scene_file_path
	for entry in definition.nodes:
		if not Schema.KINDS.has(str(entry.get("kind", ""))): continue
		var node := GraphNode.new()
		node.name = str(entry.id)
		node.title = str(entry.get("label", Schema.KINDS[entry.kind].title))
		Presentation.apply(node, str(entry.kind))
		node.position_offset = definition.positions.get(entry.id, Vector2.ZERO)
		node.selected = str(entry.id) == selected_id
		node.custom_minimum_size.x = 210
		var inputs: Array = Schema.KINDS[entry.kind]["in"]
		var outputs: Array = Schema.KINDS[entry.kind]["out"]
		for row in maxi(inputs.size(), outputs.size()):
			var input: Array = inputs[row] if row < inputs.size() else []
			var output: Array = outputs[row] if row < outputs.size() else []
			var input_text := "%s [%s]" % [Schema.PORT_LABELS.get(input[0], input[0]), Schema.TYPE_TAGS[input[1]]] if not input.is_empty() else ""
			var output_text := "%s [%s]" % [Schema.PORT_LABELS.get(output[0], output[0]), Schema.TYPE_TAGS[output[1]]] if not output.is_empty() else ""
			var hint := ("输入 %s：%s  " % [input[0], Schema.TYPE_NAMES[input[1]]] if not input.is_empty() else "") + ("输出 %s：%s" % [output[0], Schema.TYPE_NAMES[output[1]]] if not output.is_empty() else "")
			node.add_child(Presentation.port_row(input_text, output_text, hint))
			node.set_slot(row, not input.is_empty(), input[1] if not input.is_empty() else 0, Schema.TYPE_COLORS.get(input[1], Color.WHITE) if not input.is_empty() else Color.WHITE, not output.is_empty(), output[1] if not output.is_empty() else 0, Schema.TYPE_COLORS.get(output[1], Color.WHITE) if not output.is_empty() else Color.WHITE)
		var value := Label.new()
		value.name = "RuntimeValue"
		value.text = ""
		value.hide()
		node.add_child(value)
		graph.add_child(node)
	for edge in definition.edges:
		var from := _port_index(str(edge.from), "out", str(edge.out))
		var to := _port_index(str(edge.to), "in", str(edge["in"]))
		if from >= 0 and to >= 0: graph.connect_node(str(edge.from), from, str(edge.to), to)
	graph.zoom = clampf(definition.view_zoom, 0.2, 2.0)
	graph.set_scroll_offset(definition.view_offset)
	_syncing = false
	_render_details()
	_display_trace()
	_fit_default_view.call_deferred()

func _port_index(id: String, direction: String, port: String) -> int:
	var entry: Dictionary = assembly.definition.find_node(id)
	var ports: Array = Schema.KINDS.get(str(entry.get("kind", "")), {}).get(direction, [])
	for i in ports.size():
		if ports[i][0] == port: return i
	return -1

func _port_id(id: String, direction: String, index: int) -> String:
	var entry: Dictionary = assembly.definition.find_node(id)
	var ports: Array = Schema.KINDS.get(str(entry.get("kind", "")), {}).get(direction, [])
	return str(ports[index][0]) if index >= 0 and index < ports.size() else ""

func _commit(title: String, before: Resource, after: Resource, additions: Array[Node] = []) -> void:
	var history := plugin.get_undo_redo()
	history.create_action(title, UndoRedo.MERGE_DISABLE, assembly)
	for object in additions:
		history.add_do_method(assembly, "add_child", object)
		history.add_do_method(object, "set_owner", assembly)
		history.add_undo_method(assembly, "remove_child", object)
		history.add_do_reference(object)
	history.add_do_method(self, "_apply", assembly, after)
	history.add_undo_method(self, "_apply", assembly, before)
	history.commit_action()

func _apply(target: Node3D, definition: Resource) -> void:
	if not is_instance_valid(target): return
	target.definition = definition
	target.configure()
	if target == assembly:
		dirty = true
		EditorInterface.mark_scene_as_unsaved()
		_render()
		_refresh_preview()

func _connect_nodes(from: StringName, output: int, to: StringName, input: int) -> void:
	if not is_instance_valid(assembly): return
	var before: Resource = assembly.definition.duplicate(true)
	var after: Resource = before.duplicate(true)
	var edge := {"from": str(from), "out": _port_id(str(from), "out", output), "to": str(to), "in": _port_id(str(to), "in", input)}
	var source: Dictionary = after.find_node(str(from))
	var target: Dictionary = after.find_node(str(to))
	var a := Schema.port(str(source.get("kind", "")), "out", edge.out)
	var b := Schema.port(str(target.get("kind", "")), "in", edge["in"])
	if a.is_empty() or b.is_empty() or a[1] != b[1]: status.text = "端口类型不匹配"; return
	for existing in after.edges.duplicate():
		if existing.to == edge.to and existing["in"] == edge["in"]: after.edges.erase(existing)
	after.edges.append(edge)
	if after.data_order().size() != after.nodes.size(): status.text = "拒绝连续数据循环；使用事件延迟节点推进反馈。"; return
	_commit("连接机关端口", before, after)

func _disconnect_nodes(from: StringName, output: int, to: StringName, input: int) -> void:
	if not is_instance_valid(assembly): return
	var before: Resource = assembly.definition.duplicate(true)
	var after: Resource = before.duplicate(true)
	after.edges.erase({"from": str(from), "out": _port_id(str(from), "out", output), "to": str(to), "in": _port_id(str(to), "in", input)})
	_commit("断开机关端口", before, after)

func _end_move() -> void:
	if not is_instance_valid(assembly) or _moving_before == null: return
	var after: Resource = assembly.definition.duplicate(true)
	for child in graph.get_children():
		if child is GraphNode: after.positions[str(child.name)] = child.position_offset
	_commit("移动机关图节点", _moving_before, after)
	_moving_before = null

func _view_changed() -> void:
	if _syncing or not is_instance_valid(assembly) or assembly.definition == null or not assembly.definition.has_method("find_node"): return
	if assembly.definition.view_offset == graph.scroll_offset and is_equal_approx(assembly.definition.view_zoom, graph.zoom): return
	assembly.definition.view_offset = graph.scroll_offset
	assembly.definition.view_zoom = graph.zoom
	dirty = true

func _show_picker(position: Vector2) -> void:
	if not is_instance_valid(assembly): status.text = "先打开或新建机关场景。"; return
	_popup_position = (position + graph.scroll_offset) / graph.zoom
	_search.text = ""
	_filter_kinds("")
	_picker.popup_centered()
	_search.grab_focus()

func _filter_kinds(query: String) -> void:
	_kinds.clear()
	for kind in Schema.KINDS:
		var title: String = Schema.KINDS[kind].title
		if query.is_empty() or query.to_lower() in (kind + " " + title).to_lower():
			_kinds.add_item(title)
			_kinds.set_item_metadata(_kinds.item_count - 1, kind)
	if _kinds.item_count > 0: _kinds.select(0)

func _add_selected_kind() -> void:
	if _kinds.get_selected_items().is_empty() or not is_instance_valid(assembly): return
	add_kind(str(_kinds.get_item_metadata(_kinds.get_selected_items()[0])))

func add_kind(kind: String) -> void:
	var before: Resource = assembly.definition.duplicate(true)
	var after: Resource = before.duplicate(true)
	var id := Schema.uid("node")
	var params := Schema.defaults(kind)
	var additions: Array[Node] = []
	if kind in ["lever", "plate", "door"] or kind in Schema.COMPONENT_KINDS:
		var object_id := Schema.uid("object")
		params.object_id = object_id
		var object := Factory.component(kind, object_id)
		object.position.x = assembly.get_child_count() * 1.8
		additions.append(object)
	elif Schema.KINDS[kind].get("binding", "") == "stateful":
		for object_id in assembly.bindings:
			var component: Node = assembly.bindings[object_id]
			if not component.has_method("get_state"): continue
			params.object_id = object_id
			if params.has("state"):
				var states: Array = component.requestable_states() if kind == "request_state" else component.state_names()
				params.state = states[0] if not states.is_empty() else ""
			if kind == "perform_action": params.action = component.action_names()[0] if not component.action_names().is_empty() else ""
			break
	after.nodes.append({"id": id, "kind": kind, "label": Schema.KINDS[kind].title, "params": params})
	after.positions[id] = _popup_position
	selected_id = id
	_commit("添加机关节点", before, after, additions)

func _selected_nodes() -> Array[String]:
	var ids: Array[String] = []
	for child in graph.get_children():
		if child is GraphNode and child.selected: ids.append(str(child.name))
	return ids

func _delete_nodes(ids: Array) -> void:
	if not is_instance_valid(assembly): return
	var before: Resource = assembly.definition.duplicate(true)
	var after: Resource = before.duplicate(true)
	for entry in after.nodes.duplicate():
		if str(entry.id) in ids:
			after.nodes.erase(entry)
			after.positions.erase(entry.id)
	for edge in after.edges.duplicate():
		if str(edge.from) in ids or str(edge.to) in ids: after.edges.erase(edge)
	selected_id = ""
	_commit("删除机关图节点（保留空间对象）", before, after)

func _duplicate_nodes(ids: Array) -> void:
	if not is_instance_valid(assembly) or ids.is_empty(): return
	var before: Resource = assembly.definition.duplicate(true)
	var after: Resource = before.duplicate(true)
	var remap := {}
	var objects := {}
	var additions: Array[Node] = []
	for id in ids:
		var source: Dictionary = before.find_node(id)
		if source.is_empty(): continue
		var entry := source.duplicate(true)
		entry.id = Schema.uid("node")
		remap[id] = entry.id
		var object_id := str(entry.params.get("object_id", ""))
		if not object_id.is_empty() and assembly.bindings.has(object_id):
			if not objects.has(object_id):
				var original: Node3D = assembly.bindings[object_id]
				var kind := str(original.get_meta("mechanism_kind", ""))
				var new_id := Schema.uid("object")
				var object := Factory.component(kind, new_id)
				if object != null:
					for property in original.get_property_list():
						if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE and property.name != "object_id": object.set(property.name, original.get(property.name))
					object.transform = original.transform
					object.position.x += 1.5
					objects[object_id] = new_id
					additions.append(object)
			entry.params.object_id = objects.get(object_id, object_id)
		after.nodes.append(entry)
		after.positions[entry.id] = before.positions.get(id, Vector2.ZERO) + Vector2(50, 50)
	for edge in before.edges:
		if remap.has(str(edge.from)) and remap.has(str(edge.to)):
			var copy: Dictionary = edge.duplicate()
			copy.from = remap[str(edge.from)]
			copy.to = remap[str(edge.to)]
			after.edges.append(copy)
	_commit("复制机关节点及绑定对象", before, after, additions)

func _select_graph_node(node: Node) -> void:
	if _syncing: return
	selected_id = str(node.name)
	_render_details()
	_select_bound_object(false)
	_display_trace()

func scene_selection_changed() -> void:
	if _syncing or not is_instance_valid(assembly): return
	var selection := EditorInterface.get_selection().get_selected_nodes()
	if selection.is_empty(): return
	var object: Node = selection.back()
	while object != null and object != assembly and not object.has_meta("mechanism_kind"): object = object.get_parent()
	if object == null or object == assembly: return
	for entry in assembly.definition.nodes:
		if entry.get("params", {}).get("object_id", "") == str(object.get("object_id")):
			selected_id = str(entry.id)
			_syncing = true
			for child in graph.get_children():
				if child is GraphNode: child.selected = str(child.name) == selected_id
			_syncing = false
			_render_details()
			_display_trace()
			return

func _select_bound_object(switch_screen: bool) -> void:
	if not is_instance_valid(assembly): return
	var entry: Dictionary = assembly.definition.find_node(selected_id)
	var object: Node3D = assembly.bindings.get(str(entry.get("params", {}).get("object_id", "")))
	if not is_instance_valid(object): return
	_syncing = true
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(object)
	EditorInterface.inspect_object(object, "", true)
	_syncing = false
	if switch_screen:
		EditorInterface.set_main_screen_editor("3D")

func _focus_object() -> void:
	_select_bound_object(true)

func _render_details() -> void:
	_clear(details)
	if not is_instance_valid(assembly): return
	var entry: Dictionary = assembly.definition.find_node(selected_id)
	if entry.is_empty():
		_label(details, "")
		return
	_label(details, "稳定节点 ID：" + selected_id).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var title := LineEdit.new()
	title.text = str(entry.get("label", ""))
	title.placeholder_text = "显示名称"
	title.text_submitted.connect(func(value: String): _change_parameter("label", value))
	details.add_child(title)
	var params: Dictionary = entry.get("params", {})
	if Schema.KINDS[str(entry.kind)].has("binding"):
		_label(details, "绑定对象（稳定 ID）")
		var choices := OptionButton.new()
		choices.add_item("请选择组件"); choices.set_item_metadata(0, "")
		var expected: String = Schema.KINDS[str(entry.kind)].binding
		for id in assembly.bindings:
			var object: Node = assembly.bindings[id]
			if expected == "power" or (expected == "stateful" and object.has_method("get_state")) or object.get_meta("mechanism_kind", "") == expected or object.get("component_type") == expected:
				choices.add_item(str(object.name) + " · " + id)
				choices.set_item_metadata(choices.item_count - 1, id)
				if id == params.get("object_id", ""): choices.select(choices.item_count - 1)
		choices.item_selected.connect(func(index: int): _change_parameter("object_id", str(choices.get_item_metadata(index))))
		details.add_child(choices)
	var component: Node = assembly.bindings.get(str(params.get("object_id", "")))
	if is_instance_valid(component) and component.has_method("get_state"):
		for key in ["state", "from_state", "to_state", "action", "property"]:
			if not params.has(key): continue
			var values: Array = []
			if key == "property": values = ["locked", "interaction_enabled", "motion_seconds", "reset_after"]
			elif key == "action": values = component.action_names().duplicate()
			else: values = (component.requestable_states() if entry.kind == "request_state" else component.state_names()).duplicate()
			if key in ["from_state", "to_state"] or (key == "action" and entry.kind == "action_finished"): values.push_front("")
			if not values.has(params[key]): values.push_front(params[key])
			_label(details, {"state": "状态", "from_state": "原状态（留空为任意）", "to_state": "新状态（留空为任意）", "action": "动作", "property": "机关属性"}[key])
			var field := OptionButton.new()
			for value in values:
				field.add_item("任意" if str(value).is_empty() else str(preload("res://addons/godot_level_editor_mechanisms/task_parameters.gd").NAMES.get(value, value)) + " · " + str(value))
				field.set_item_metadata(field.item_count - 1, value)
				if value == params[key]: field.select(field.item_count - 1)
			field.item_selected.connect(func(index: int): _change_parameter(key, field.get_item_metadata(index))); details.add_child(field)
		for key in ["enabled", "succeeded", "bool_value"]:
			if not params.has(key): continue
			var field := CheckBox.new(); field.text = {"enabled": "允许交互", "succeeded": "动作成功（取消勾选为失败）", "bool_value": "属性值：是"}[key]; field.button_pressed = params[key]
			field.toggled.connect(func(value: bool): _change_parameter(key, value)); details.add_child(field)
		if params.has("number_value"): _number_parameter("number_value", float(params.number_value))
		if entry.kind in Schema.COMPONENT_KINDS: preload("res://addons/godot_level_editor_mechanisms/component_parameters.gd").draw(self, component)
	if params.has("value"):
		if params.value is bool:
			var value := CheckBox.new()
			value.text = "布尔值为 true"
			value.button_pressed = params.value
			value.toggled.connect(func(next: bool): _change_parameter("value", next))
			details.add_child(value)
		else: _number_parameter("value", float(params.value))
	if params.has("seconds"): _number_parameter("seconds", float(params.seconds))
	var reason := Label.new()
	reason.name = "Reason"
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(reason)

func set_component_property(component: Node, key: String, value: Variant) -> void:
	var history := plugin.get_undo_redo()
	history.create_action("编辑机关组件配置", UndoRedo.MERGE_DISABLE, assembly)
	history.add_do_property(component, key, value); history.add_undo_property(component, key, component.get(key))
	history.add_do_method(self, "_component_config_changed", component); history.add_undo_method(self, "_component_config_changed", component)
	history.commit_action()

func _component_config_changed(component: Node) -> void:
	component.rebuild_design(); component.reset_state()
	dirty = true; EditorInterface.mark_scene_as_unsaved(); assembly.configure()
	_render_details.call_deferred(); _refresh_preview.call_deferred()

func _number_parameter(key: String, value: float) -> void:
	_label(details, "延迟秒数（至少下一物理帧触发）" if key == "seconds" else "数值")
	var field := SpinBox.new()
	field.min_value = 0 if key == "seconds" else -100000
	field.max_value = 3600 if key == "seconds" else 100000
	field.step = 0.05
	field.value = value
	field.value_changed.connect(func(next: float): _change_parameter(key, next))
	details.add_child(field)

func _change_parameter(key: String, value: Variant) -> void:
	if not is_instance_valid(assembly): return
	var before: Resource = assembly.definition.duplicate(true)
	var after: Resource = before.duplicate(true)
	var entry: Dictionary = after.find_node(selected_id)
	if entry.is_empty(): return
	if key == "label": entry.label = value
	else: entry.params[key] = value
	_commit("修改机关节点参数", before, after)

func _validate() -> bool:
	if not is_instance_valid(assembly): status.text = "没有独立机关场景。"; return false
	var errors := Store.validate(assembly)
	status.text = "验证通过：节点、端口、类型、对象绑定、循环及组件参数有效。" if errors.is_empty() else "\n".join(errors)
	return errors.is_empty()

func save() -> void:
	if not is_instance_valid(assembly): return
	if assembly.scene_file_path.is_empty():
		_new_file = false
		_save_dialog.popup_centered_ratio(0.6)
	else: _save_to(assembly.scene_file_path)

func _save_to(path: String, sync_editor := true) -> void:
	if _new_file:
		var root := Factory.sample()
		var result := Store.save_pair(root, path)
		root.free()
		_new_file = false
		if not result.ok: status.text = str(result.errors); return
		EditorInterface.get_resource_filesystem().scan()
		EditorInterface.open_scene_from_path(path)
		return
	if not is_instance_valid(assembly): return
	if path == assembly.scene_file_path and not _known_hash.is_empty() and _known_hash != _disk_hash(path):
		status.text = "磁盘文件已被其他编辑修改；请重开检查或另存为，避免覆盖。"
		return
	if path != assembly.scene_file_path and path in EditorInterface.get_unsaved_scenes():
		status.text = "目标场景在另一个标签中有未保存修改，请先保存或选择其他文件。"
		return
	if not _validate(): return
	var result := Store.save_pair(assembly, path)
	if not result.ok: status.text = str(result.errors); return
	_known_hash = _disk_hash(path)
	dirty = false
	if path == assembly.scene_file_path:
		if sync_editor: EditorInterface.save_scene()
	else:
		_skip_native_save = true
		if path in EditorInterface.get_open_scenes(): EditorInterface.reload_scene_from_path(path)
		EditorInterface.open_scene_from_path(path)
	EditorInterface.get_resource_filesystem().scan()
	status.text = "已保存场景与图定义：" + path
	_render()

func _request_reload() -> void:
	if not is_instance_valid(assembly) or assembly.scene_file_path.is_empty(): return
	if dirty or assembly in EditorInterface.get_open_scene_roots() and assembly.scene_file_path in EditorInterface.get_unsaved_scenes():
		_reload_dialog.popup_centered()
	else: _reload_current()

func _reload_current() -> void:
	if not is_instance_valid(assembly) or assembly.scene_file_path.is_empty(): return
	var path := assembly.scene_file_path
	var fresh := Store.load_pair(path)
	if fresh == null:
		status.text = "磁盘资源无效或版本不支持，当前编辑状态已保留。"
		return
	fresh.definition.take_over_path(path.get_basename() + ".graph.tres")
	fresh.free()
	_skip_native_save = true
	EditorInterface.reload_scene_from_path(path)

func save_before_editor() -> void:
	if not _skip_native_save and dirty and is_instance_valid(assembly) and not assembly.scene_file_path.is_empty(): _save_to(assembly.scene_file_path, false)

func _disk_hash(path: String) -> String:
	if path.is_empty(): return ""
	var graph_path := path.get_basename() + ".graph.tres"
	return (FileAccess.get_md5(path) if FileAccess.file_exists(path) else "") + ":" + (FileAccess.get_md5(graph_path) if FileAccess.file_exists(graph_path) else "")

func _history(redo: bool) -> void:
	if not is_instance_valid(assembly): return
	var manager := plugin.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(assembly))
	if redo: history.redo()
	else: history.undo()

func inspector_edited(_property: String) -> void:
	if is_instance_valid(assembly):
		assembly.configure()
		dirty = true
		_refresh_preview.call_deferred()

func _setup_world() -> void:
	var environment := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color("1b2633")
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color("d2dfea")
	sky.ambient_light_energy = 0.7
	environment.environment = sky
	_viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.6
	_viewport.add_child(sun)
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(35, 0.12, 35)
	floor.mesh = mesh
	floor.position.y = -0.08
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("7d8d99")
	floor.material_override = material
	_viewport.add_child(floor)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	_update_camera()

func _reset_preview() -> void:
	_preview_plate = false
	plate_button.set_pressed_no_signal(false)
	_focus = Vector3(0, 1.8, 0)
	_update_camera()
	_refresh_preview()

func _refresh_preview() -> void:
	if _viewport == null: return
	if is_instance_valid(_preview):
		_viewport.remove_child(_preview)
		_preview.free()
	_preview = null
	_preview_accumulator = 0.0
	if not is_instance_valid(assembly) or assembly.definition == null or not assembly.definition.has_method("find_node"): return
	var scene := PackedScene.new()
	if scene.pack(assembly) != OK: return
	_preview = scene.instantiate()
	_preview.definition = assembly.definition.duplicate(true)
	_preview.transform = Transform3D.IDENTITY
	_viewport.add_child(_preview)
	for label in _preview.find_children("*", "Label3D", true, false): label.hide()
	_preview.configure()
	_update_preview_plate()
	_preview_status.text = "隔离预览：" + ("就绪" if _preview.errors.is_empty() else str(_preview.errors))

func _toggle_preview() -> void:
	if not is_instance_valid(_preview): return
	if not _preview.errors.is_empty(): _preview_status.text = str(_preview.errors); return
	_preview_running = not _preview_running
	_preview_status.text = "预览运行 · 60 Hz" if _preview_running else "预览暂停"

func _preview_interact() -> void:
	if not is_instance_valid(_preview): return
	var entry: Dictionary = assembly.definition.find_node(selected_id)
	var target_id := str(entry.get("params", {}).get("object_id", ""))
	for id in _preview.bindings:
		var object: Node = _preview.bindings[id]
		if object.has_method("interact") and (target_id.is_empty() or target_id == id):
			object.interact()
			return

func _update_preview_plate() -> void:
	if not is_instance_valid(_preview): return
	for object in _preview.bindings.values():
		if object.has_method("set_preview_powered"): object.set_preview_powered(_preview_plate)

func _process(delta: float) -> void:
	if not visible or not _preview_running or not is_instance_valid(_preview): return
	_preview_accumulator = minf(_preview_accumulator + delta, 0.25)
	while _preview_accumulator >= 1.0 / 60.0:
		_preview_accumulator -= 1.0 / 60.0
		_preview.step()
		for object in _preview.bindings.values():
			if object.get_meta("mechanism_kind", "") == "lever" or object.has_method("get_state"): object.advance(1.0 / 60.0)
		for object in _preview.bindings.values():
			if object.get_meta("mechanism_kind", "") == "door": object.advance(1.0 / 60.0)
	_display_trace()

func _orbit(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_angle += event.relative.x * 0.01
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _distance = maxf(4, _distance - 1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _distance = minf(35, _distance + 1)
		_update_camera()

func _update_camera() -> void:
	if not is_instance_valid(_camera) or not _camera.is_inside_tree(): return
	_camera.size = _distance
	_camera.position = _focus + Vector3(sin(_angle) * 12, 10, cos(_angle) * 12)
	_camera.look_at(_focus)

func receive_runtime(key: String, packet: Dictionary) -> void:
	runtime_packets[key] = packet
	_rebuild_runtime_choices()
	_display_trace()

func remove_runtime(key: String) -> void:
	runtime_packets.erase(key)
	if selected_runtime == key: selected_runtime = ""
	_rebuild_runtime_choices()
	_display_trace()

func clear_session(session_id: int) -> void:
	for key in runtime_packets.keys():
		if int(runtime_packets[key].get("session", -1)) == session_id: runtime_packets.erase(key)
	selected_runtime = ""
	_rebuild_runtime_choices()
	_display_trace()

func _rebuild_runtime_choices() -> void:
	if runtime_choice == null: return
	runtime_choice.clear()
	runtime_choice.add_item("隔离预览（编辑场景副本）")
	runtime_choice.set_item_metadata(0, "")
	runtime_choice.get_parent().visible = not runtime_packets.is_empty() or _preview_running
	for key in runtime_packets:
		var packet: Dictionary = runtime_packets[key]
		runtime_choice.add_item("游戏：" + str(packet.get("instance", key)))
		runtime_choice.set_item_metadata(runtime_choice.item_count - 1, key)
		if selected_runtime == key: runtime_choice.select(runtime_choice.item_count - 1)

func _display_trace() -> void:
	if not is_instance_valid(assembly) or runtime_label == null: return
	var state: Dictionary = _preview.trace if is_instance_valid(_preview) else {}
	if not selected_runtime.is_empty():
		var packet: Dictionary = runtime_packets.get(selected_runtime, {})
		var expected_path: String = assembly.definition.resource_path
		if expected_path.is_empty(): expected_path = assembly.scene_file_path.get_basename() + ".graph.tres"
		if packet.get("definition_id", "") != assembly.definition.definition_id or (not str(packet.get("definition", "")).is_empty() and packet.definition != expected_path):
			runtime_label.text = "所选运行实例与当前图定义不对应"
			state = {}
		else:
			state = packet.get("trace", {})
			runtime_label.text = "真实实例 %s | 帧 %s | 待处理 %s | %s" % [packet.get("instance", ""), packet.get("frame", 0), packet.get("pending", 0), str(packet.get("errors", []))]
	else:
		runtime_label.text = "隔离预览 · 帧 %d" % (_preview.frame if is_instance_valid(_preview) else 0)
	for child in graph.get_children():
		if child is GraphNode:
			var value: Dictionary = state.get(str(child.name), {})
			var label := child.get_node_or_null("RuntimeValue")
			var active: bool = value.get("value", false) == true
			if label != null:
				label.text = ("● " if active else "") + "当前值：" + str(value.get("value", ""))
				label.visible = not value.is_empty()
			Presentation.show_runtime(child, active)
	var reason := details.get_node_or_null("Reason")
	if reason != null:
		var value: Dictionary = state.get(selected_id, {})
		var event: Dictionary = value.get("last_event", {})
		reason.visible = not value.is_empty()
		reason.text = "当前原因：%s\n物理帧：%s\n最近事件：%s（帧 %s）" % [value.get("reason", "未执行"), value.get("frame", "—"), event.get("reason", "尚无"), event.get("frame", "—")]

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _fit_graph(save_view := true) -> void:
	if not is_instance_valid(assembly): return
	var bounds := Rect2()
	var first := true
	for child in graph.get_children():
		if child is GraphNode:
			var rect := Rect2(child.position_offset, child.size)
			bounds = rect if first else bounds.merge(rect)
			first = false
	if first: return
	_syncing = true
	graph.zoom = clampf(minf((graph.size.x - 100) / maxf(bounds.size.x, 1), (graph.size.y - 150) / maxf(bounds.size.y, 1)), 0.2, 1.0)
	graph.scroll_offset = bounds.position * graph.zoom - Vector2(45, 85)
	_syncing = false
	if save_view: _view_changed()

func _fit_default_view() -> void:
	await get_tree().process_frame
	if is_instance_valid(assembly) and assembly.definition != null and assembly.definition.has_method("find_node") and assembly.definition.view_offset == Vector2.ZERO and is_equal_approx(assembly.definition.view_zoom, 1.0): _fit_graph(false)
