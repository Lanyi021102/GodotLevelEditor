@tool
extends EditorPlugin
const PANEL := preload("res://addons/godot_level_editor/graph_panel.gd")
const DEBUGGER := preload("res://addons/godot_level_editor/debugger.gd")
const FACTORY := preload("res://addons/godot_level_editor/scene_factory.gd")
const WORLD := preload("res://addons/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/runtime/level_graph.gd")
const GROUPS := preload("res://addons/godot_level_editor/scene_groups.gd")
var panel: Control
var dock: VBoxContainer
var palette: OptionButton
var message: Label
var file_dialog: EditorFileDialog
var file_action := ""
var debugger: EditorDebuggerPlugin
var dock_scroll: ScrollContainer
var shape_grid: GridContainer
var large_preview: Control
var selected_kind := "box"
var _known_scene_nodes: Dictionary = {}
var size_fields: Array[SpinBox] = []
var gizmos: EditorNode3DGizmoPlugin
var push_pull: RefCounted
var push_buttons: Array[Button] = []
var selection_buttons: Dictionary = {}
var edit_step := 0.1
var step_input: LineEdit
var step_presets: MenuButton
const STEP_METADATA := "godot_level_editor_edit"
const STEP_PRESETS := [0.1, 0.5, 1.0]
var spatial_tools: HBoxContainer
var radial_tool: RefCounted
var asset_drop_tool: RefCounted
var entity_inspector: EditorInspectorPlugin
var entity_gizmos: EditorNode3DGizmoPlugin
const ITEM := preload("res://addons/godot_level_editor/palette_item.gd")
const SHAPES := preload("res://addons/godot_level_editor/runtime/whitebox_shapes.gd")
const OBJECT_LABELS := {"room": "房间区域 Room", "region": "目标 / 触发区域", "spawn": "玩家出生点", "lever": "开关", "plate": "压力板", "kinetic": "动能板", "breaker": "电闸", "door": "门", "guard": "敌人", "placeholder": "自定义组件"}

func _enter_tree() -> void:
	set_meta("godot_level_editor_module", "level")
	add_to_group("godot_level_editor_suite_modules")
	panel = PANEL.new()
	panel.plugin = self
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	debugger = DEBUGGER.new()
	debugger.state_received.connect(panel.receive_runtime)
	debugger.instance_removed.connect(panel.remove_runtime)
	debugger.session_cleared.connect(panel.clear_session)
	debugger.session_paused.connect(panel.set_session_paused)
	add_debugger_plugin(debugger)
	dock = VBoxContainer.new()
	dock_scroll = ScrollContainer.new()
	dock_scroll.name = "关卡摆放"
	dock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dock_scroll.add_child(dock)
	dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_scroll)
	gizmos = preload("res://addons/godot_level_editor/block_gizmo.gd").new()
	add_node_3d_gizmo_plugin(gizmos)
	push_pull = preload("res://addons/godot_level_editor/push_pull_tool.gd").new()
	push_pull.plugin = self
	gizmos.face_tool = push_pull
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	spatial_tools = HBoxContainer.new()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, spatial_tools)
	radial_tool = preload("res://addons/godot_level_editor/radial_tool.gd").new()
	radial_tool.setup(self, spatial_tools)
	asset_drop_tool = preload("res://addons/godot_level_editor/asset_drop_tool.gd").new()
	asset_drop_tool.plugin = self
	entity_inspector = preload("res://addons/godot_level_editor/entity_inspector.gd").new()
	entity_inspector.plugin = self
	add_inspector_plugin(entity_inspector)
	entity_gizmos = preload("res://addons/godot_level_editor/entity_gizmo.gd").new()
	add_node_3d_gizmo_plugin(entity_gizmos)
	main_screen_changed.connect(func(screen: String):
		if screen != "3D":
			if radial_tool != null: radial_tool.cancel()
			if push_pull.enabled: push_pull.set_enabled(false))
	for mode in ["face", "edge", "point"]: _push_button(spatial_tools, mode)
	_build_step_controls()
	_push_button(dock)
	_button("应用当前编辑步长", _configure_snap)
	_configure_snap.call_deferred()
	_button("打开触发／操作／判断示例", func(): EditorInterface.open_scene_from_path("res://scenes/levels/logic_playground.tscn"))
	_button("打开首版连续世界", func(): EditorInterface.open_scene_from_path("res://scenes/levels/continuous_world.tscn"))
	_button("新建房间 .tscn", func(): _choose_file("room"))
	_button("新建关卡", func(): _choose_file("world"))
	_button("实例化房间到世界", func(): _choose_file("instance"))
	var hint := Label.new()
	hint.text = "物件库 · 拖入三维场地"
	dock.add_child(hint)
	var category := OptionButton.new()
	category.add_item("白盒形状 · 1×1×1")
	category.add_item("关卡对象 · Room / 机关 / 敌人")
	dock.add_child(category)
	category.item_selected.connect(_populate_library)
	large_preview = ITEM.new()
	large_preview.kind = "box"
	large_preview.title = "方块 · 1×1×1"
	large_preview.custom_minimum_size = Vector2(230, 140)
	large_preview.chosen.connect(func(_kind: String): pass)
	dock.add_child(large_preview)
	shape_grid = GridContainer.new()
	shape_grid.columns = 2
	shape_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var library_scroll := ScrollContainer.new()
	library_scroll.custom_minimum_size.y = 220
	library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dock.add_child(library_scroll)
	library_scroll.add_child(shape_grid)
	_populate_library(0)
	var note := Label.new()
	note.text = "选中面／线／点后拖中心操作轴；Esc 取消选择并恢复物体轴。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(note)
	var dimensions_label := Label.new()
	dimensions_label.text = "选中白盒的尺寸 · 0.1 步长"
	dock.add_child(dimensions_label)
	var dimension_row := HBoxContainer.new()
	dock.add_child(dimension_row)
	for axis in 3:
		var field := SpinBox.new()
		field.min_value = 0.1
		field.max_value = 1000
		field.step = 0.1
		field.value = 1
		field.prefix = ["宽 ", "高 ", "深 "][axis]
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.custom_minimum_size.x = 72
		field.value_changed.connect(func(_v: float): _edit_dimensions())
		dimension_row.add_child(field)
		size_fields.append(field)
	palette = OptionButton.new() # Retained programmatic legacy palette compatibility.
	for label in ["白盒", "压力板", "动能板", "电闸", "门", "守卫", "占位", "接驳点", "目标区域"]: palette.add_item(label)
	palette.hide()
	dock.add_child(palette)
	_button("添加所选物件", _add_spatial)
	_button("复制所选（新对象 ID）", _duplicate_spatial)
	_button("保存场景并重载校验", _save_scene)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text = "拖动缩略图可直接放入三维场景。选中白盒拖面手柄拉伸；检查器可改楼梯步数、壁厚、弧度等。"
	dock.add_child(message)
	file_dialog = EditorFileDialog.new()
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.add_filter("*.tscn", "Godot 场景")
	file_dialog.file_selected.connect(_file_selected)
	dock.add_child(file_dialog)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	scene_changed.connect(_scene_changed)
	get_tree().node_added.connect(_node_added)
	_remember_scene(EditorInterface.get_edited_scene_root())
	if OS.get_cmdline_user_args().has("--godot-level-editor-level-smoke"):
		_run_smoke.call_deferred()
	if OS.get_cmdline_user_args().has("--quick-add-test"):
		_run_quick_add_test.call_deferred()
	if OS.get_cmdline_user_args().has("--face-gizmo-test"):
		_run_face_gizmo_test.call_deferred()

func _button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	dock.add_child(button)

func _push_button(parent: Node, mode := "face") -> void:
	var button := Button.new()
	button.text = {"face": "选中面", "edge": "选中线", "point": "选中点"}[mode]
	button.toggle_mode = true
	button.tooltip_text = "选中元素后在其中心拖动操作轴；Esc／点击空白恢复物体轴。"
	button.toggled.connect(func(value: bool):
		if value and radial_tool != null: radial_tool.cancel()
		if value: push_pull.set_mode(mode)
		elif push_pull.mode == mode: push_pull.set_enabled(false))
	parent.add_child(button)
	if not selection_buttons.has(mode): selection_buttons[mode] = []
	selection_buttons[mode].append(button)
	if mode == "face": push_buttons.append(button)

func _sync_selection_buttons() -> void:
	for mode in selection_buttons:
		for button in selection_buttons[mode]: button.set_pressed_no_signal(push_pull.enabled and push_pull.mode == mode)

func _build_step_controls() -> void:
	var saved: float = float(EditorInterface.get_editor_settings().get_project_metadata(STEP_METADATA, "step", 0.1))
	if is_finite(saved) and saved >= 0.001 and saved <= 1000: edit_step = snappedf(saved, 0.001)
	var controls := HBoxContainer.new()
	controls.name = "EditStep"
	spatial_tools.add_child(controls)
	var label := Label.new(); label.text = "步长"; controls.add_child(label)
	step_input = LineEdit.new()
	step_input.name = "EditStepValue"
	step_input.custom_minimum_size.x = 64 * EditorInterface.get_editor_scale()
	step_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	step_input.text = String.num(edit_step, 3)
	step_input.tooltip_text = "移动／推拉／放置步长（米），可填写 0.001–1000；Enter 或移开焦点应用。"
	step_input.select_all_on_focus = true
	controls.add_child(step_input)
	step_input.text_submitted.connect(func(_text: String): _commit_step_input())
	step_input.focus_exited.connect(_commit_step_input)
	step_presets = MenuButton.new(); step_presets.text = "⌄"; step_presets.tooltip_text = "步长预设"; controls.add_child(step_presets)
	for index in STEP_PRESETS.size(): step_presets.get_popup().add_item(String.num(STEP_PRESETS[index], 1), index)
	step_presets.get_popup().id_pressed.connect(func(id: int):
		if id >= 0 and id < STEP_PRESETS.size(): _set_edit_step(STEP_PRESETS[id]))

func _commit_step_input() -> void:
	var text := step_input.text.strip_edges()
	if not text.is_valid_float() or not _set_edit_step(text.to_float()):
		step_input.text = String.num(edit_step, 3)
		if is_instance_valid(message): message.text = "步长请输入 0.001–1000 之间的数字。"

func _set_edit_step(value: float) -> bool:
	if not is_finite(value) or value < 0.001 or value > 1000: return false
	edit_step = snappedf(value, 0.001)
	step_input.text = String.num(edit_step, 3)
	EditorInterface.get_editor_settings().set_project_metadata(STEP_METADATA, "step", edit_step)
	_configure_snap()
	return true

func _configure_snap() -> void:
	var configured := preload("res://addons/godot_level_editor/native_snap.gd").configure(edit_step)
	if is_instance_valid(message): message.text = "移动／推拉／放置步长已设为 %s 米。" % String.num(edit_step, 3) if configured else "请在三维视口的“变换 → 配置吸附”中将平移设为 %s，并开启吸附。" % String.num(edit_step, 3)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if radial_tool != null and radial_tool.input(camera, event): return EditorPlugin.AFTER_GUI_INPUT_STOP
	if push_pull.input(camera, event): return EditorPlugin.AFTER_GUI_INPUT_STOP
	if push_pull.uses_native_gizmo(): return EditorPlugin.AFTER_GUI_INPUT_CUSTOM
	return EditorPlugin.AFTER_GUI_INPUT_PASS
func _forward_3d_force_draw_over_viewport(control: Control) -> void:
	if push_pull != null: push_pull.draw(control)
	if radial_tool != null: radial_tool.draw(control)

func _process(_delta: float) -> void:
	# Tool scripts can reload while the user keeps unsaved level edits open.
	if entity_inspector == null:
		entity_inspector = preload("res://addons/godot_level_editor/entity_inspector.gd").new(); entity_inspector.plugin = self; add_inspector_plugin(entity_inspector)
	if entity_gizmos == null:
		entity_gizmos = preload("res://addons/godot_level_editor/entity_gizmo.gd").new(); add_node_3d_gizmo_plugin(entity_gizmos)
	if radial_tool != null: radial_tool.process()
	if asset_drop_tool == null and radial_tool != null:
		asset_drop_tool = preload("res://addons/godot_level_editor/asset_drop_tool.gd").new()
		asset_drop_tool.plugin = self
	if asset_drop_tool != null: asset_drop_tool.sync()

func _build() -> bool:
	if radial_tool != null: radial_tool.cancel()
	if push_pull != null and push_pull.enabled: push_pull.set_enabled(false)
	return true

func _has_main_screen() -> bool: return not _in_suite()
func _get_plugin_name() -> String: return "关卡与世界"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("GraphEdit", "EditorIcons")
func _make_visible(value: bool) -> void:
	if _in_suite() and value:
		var suite := get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
		if suite != null and is_instance_valid(suite.window) and suite.window.visible and not EditorInterface.is_playing_scene():
			suite.open_tab("关卡")
	elif is_instance_valid(panel): panel.visible = value
func _handles(object: Object) -> bool: return not _in_suite() and object is GodotLevelEditorLevelGraph and not object.has_method("load_dialogue")
func _edit(object: Object) -> void:
	if object is GodotLevelEditorLevelGraph: panel.open_graph(object)
func _get_unsaved_status(_for_scene: String) -> String:
	return "关卡节点图有未保存修改，请先保存。" if is_instance_valid(panel) and panel.dirty else ""

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.dirty: panel.save_graph()

func _scene_changed(root: Node) -> void:
	if radial_tool != null: radial_tool.cancel()
	_remember_scene(root)
	_configure_snap.call_deferred()
	if push_pull != null:
		if push_pull.dragging: push_pull.finish(true)
		push_pull.clear()
	if not panel.dirty and root != null and root.get_script() == WORLD:
		panel.world = root
		panel._switch_graph()

func _selection_changed() -> void:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	if push_pull != null and not push_pull.selecting and not push_pull.dragging and not push_pull.picked.is_empty() and not nodes.has(push_pull.picked.get("block")): push_pull.clear()
	if nodes.size() == 1:
		panel.focus_object(nodes[0])
		if nodes[0].get_script() == FACTORY.BLOCK:
			for axis in size_fields.size(): size_fields[axis].set_value_no_signal(nodes[0].size[axis])

func _choose_file(action: String) -> void:
	if action == "world" and _in_suite():
		var suite := get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
		if suite != null:
			suite.open_tab("关卡")
			suite.level_panel.show_form(false)
			return
	file_action = action
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE if action == "instance" else EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_dir = "res://scenes/level_editor/rooms" if action == "room" else "res://scenes/level_editor"
	file_dialog.current_file = "" if action == "instance" else "new_%s.tscn" % action
	file_dialog.popup_centered_ratio(0.7)

func _file_selected(path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if file_action == "instance":
		if root == null or root.get_script() != WORLD:
			message.text = "请先打开世界场景。"
			return
		var packed: PackedScene = load(path)
		var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		if instance.get_script() != FACTORY.ROOM:
			instance.free()
			message.text = "所选场景不是关卡房间。"
			return
		instance.room_id = GRAPH.fresh_id("room")
		instance.position = Vector3(20 * root.rooms().size(), 0, 0)
		_add_undoable(root, instance, root, "实例化房间")
		return
	if FileAccess.file_exists(path):
		message.text = "目标文件已存在，请选择新文件名。"
		return
	var node: Node3D
	if file_action == "room":
		node = FACTORY.room(GRAPH.fresh_id("room"))
		node.uses_topology = false
		FACTORY.boundary(node, [])
		for child in node.get_children():
			if child is Node3D and GROUPS.kind(child) == "whitebox": GROUPS.group_new_node(node, child)
	else:
		node = WORLD.new()
		node.name = "GodotLevelEditorWorld"
		node.world_id = GRAPH.fresh_id("world")
		for kind in ["topology", "events"]:
			var graph := GRAPH.new()
			graph.graph_id = GRAPH.fresh_id("graph")
			graph.graph_kind = kind
			var graph_path: String = path.get_basename() + "_" + kind + ".tres"
			if FileAccess.file_exists(graph_path):
				node.free()
				message.text = "相邻图资源已存在，请选择新文件名。"
				return
			var err := ResourceSaver.save(graph, graph_path)
			if err != OK:
				node.free()
				message.text = error_string(err)
				return
			node.set(kind, load(graph_path))
	var err := FACTORY.save_scene(node, path)
	node.free()
	if err == OK:
		EditorInterface.get_resource_filesystem().scan()
		EditorInterface.open_scene_from_path(path)
	else: message.text = "创建失败：" + error_string(err)

func _add_spatial() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not root.get_script() in [FACTORY.ROOM, WORLD]:
		message.text = "请先打开房间或世界场景。"
		return
	var kind := selected_kind
	var node: Node3D
	if SHAPES.LABELS.has(kind):
		node = FACTORY.BLOCK.new()
		node.shape_kind = kind
		node.size = Vector3.ONE
		if kind == "tube": node.curve_angle = 360
	elif kind == "room":
		if root.get_script() != WORLD:
			message.text = "Room 请添加到世界场景。"
			return
		node = FACTORY.ROOM.new()
		node.room_id = GRAPH.fresh_id("room")
		node.display_name = "新房间"
		node.uses_topology = false
		node.bounds_size = Vector3(10, 4, 10)
	elif kind == "spawn": node = preload("res://addons/godot_level_editor/runtime/spawn_marker.gd").new()
	elif kind == "port": node = FACTORY.PORT.new()
	elif kind == "region": node = FACTORY.REGION.new()
	else:
		node = FACTORY.PLACE.new()
		node.component_kind = kind
	if kind != "room": node.object_id = GRAPH.fresh_id("object")
	node.name = SHAPES.LABELS.get(kind, OBJECT_LABELS.get(kind, "物件"))
	if kind == "door": node.position.y = 1.15
	elif SHAPES.LABELS.has(kind): node.position.y = node.size.y * 0.5
	_add_undoable(root, node, root, "添加关卡物件")

func _populate_library(category: int) -> void:
	if shape_grid == null: return
	for child in shape_grid.get_children(): child.free()
	var labels: Dictionary = SHAPES.LABELS if category == 0 else OBJECT_LABELS
	for kind in labels:
		var item := ITEM.new()
		item.kind = kind
		item.title = labels[kind]
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.chosen.connect(_choose_kind)
		shape_grid.add_child(item)

func _choose_kind(kind: String) -> void:
	selected_kind = kind
	for item in shape_grid.get_children(): item.selected = item.kind == kind
	# Rebuild the selected preview so its drawing and drag payload stay in sync.
	var index := large_preview.get_index()
	dock.remove_child(large_preview)
	large_preview.queue_free()
	large_preview = ITEM.new()
	large_preview.kind = kind
	large_preview.title = SHAPES.LABELS.get(kind, OBJECT_LABELS.get(kind, kind))
	large_preview.custom_minimum_size = Vector2(230, 140)
	large_preview.chosen.connect(func(_kind: String): pass)
	dock.add_child(large_preview)
	dock.move_child(large_preview, index)

func _edit_dimensions() -> void:
	if size_fields.size() != 3: return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.size() != 1 or selected[0].get_script() != FACTORY.BLOCK: return
	var node: Node3D = selected[0]
	var dimensions := Vector3(size_fields[0].value, size_fields[1].value, size_fields[2].value)
	if node.size.is_equal_approx(dimensions): return
	var history := get_undo_redo()
	history.create_action("修改白盒尺寸（0.1）", UndoRedo.MERGE_ENDS, node)
	history.add_do_property(node, "size", dimensions)
	history.add_undo_property(node, "size", node.size)
	history.commit_action()

func _add_undoable(parent: Node, node: Node, root: Node, title: String) -> void:
	_add_nodes_undoable(parent, [node], root, title)

func _add_nodes_undoable(parent: Node, nodes: Array, root: Node, title: String, additional_owned: Array[Node] = []) -> void:
	if nodes.is_empty(): return
	var history := get_undo_redo()
	history.create_action(title, UndoRedo.MERGE_DISABLE, root)
	var groups := {}
	var new_groups: Array[Node] = []
	var tagged_groups: Array[Node] = []
	var parents: Array[Node] = []
	var start_room: Node
	for node in nodes:
		var destination: Node = parent
		var category := GROUPS.kind(node)
		if parent == root and not category.is_empty():
			if not groups.has(category):
				var group := GROUPS.find_group(root, category)
				if group == null:
					group = GROUPS.new_group(category)
					new_groups.append(group)
					history.add_do_method(root, "add_child", group, true)
					history.add_do_method(group, "set_owner", root)
					history.add_do_reference(group)
				elif not group.has_meta(GROUPS.META):
					tagged_groups.append(group)
					history.add_do_method(group, "set_meta", GROUPS.META, category)
				groups[category] = group
			destination = groups[category]
			if node is Node3D: node.transform = (destination as Node3D).transform.affine_inverse() * node.transform
		parents.append(destination)
		history.add_do_method(destination, "add_child", node, true)
		history.add_do_method(node, "set_owner", root)
		var properties: Node = node.get_node_or_null("EntityProperties")
		if properties != null and properties.get_script() == preload("res://addons/godot_level_editor/runtime/entity_binding.gd"):
			history.add_do_method(properties, "set_owner", root)
		history.add_do_reference(node)
		if node.get_script() == FACTORY.ROOM and node.uses_topology and start_room == null: start_room = node
	for child in additional_owned: history.add_do_method(child, "set_owner", root)
	if start_room != null and root.get_script() == WORLD and root.rooms().filter(func(room: Node): return room.uses_topology).is_empty():
		history.add_do_property(root, "start_room_id", start_room.room_id)
		history.add_undo_property(root, "start_room_id", root.start_room_id)
	history.add_undo_method(self, "_undo_added_nodes", root, nodes, parents, new_groups, tagged_groups)
	history.commit_action()
	EditorInterface.get_selection().clear()
	for node in nodes: EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(nodes[0])

func _undo_added_nodes(root: Node, nodes: Array, parents: Array[Node], new_groups: Array[Node], tagged_groups: Array[Node]) -> void:
	for index in range(nodes.size() - 1, -1, -1):
		if nodes[index].get_parent() == parents[index]: parents[index].remove_child(nodes[index])
	for group in tagged_groups: group.remove_meta(GROUPS.META)
	for group in new_groups:
		if group.get_parent() == root and group.get_child_count() == 0: root.remove_child(group)

func _duplicate_spatial() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not root.get_script() in [FACTORY.ROOM, WORLD]: return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var remap := {}
	var copies: Array[Node] = []
	var owned_copies: Array[Node] = []
	for node in selected:
		if node.owner != root or (node.get_parent() != root and not GROUPS.is_group(node.get_parent())) or GROUPS.kind(node).is_empty(): continue
		var copy := node.duplicate()
		for authored in node.find_children("*", "Node", true, false):
			if authored.owner == root:
				var duplicate_child := copy.get_node_or_null(node.get_path_to(authored))
				if duplicate_child != null: owned_copies.append(duplicate_child)
		# Generated previews have no owner and must not become authored children.
		for child in copy.get_children():
			if child.owner == null and not child.get("object_id") is String and not owned_copies.has(child): child.free()
		var id := GRAPH.fresh_id("room" if node.get_script() == FACTORY.ROOM else "object")
		if node.get_script() == FACTORY.ROOM:
			copy.room_id = id
			copy.display_name += "（副本）"
		elif node.get("object_id") is String:
			remap[node.object_id] = id
			copy.object_id = id
		else:
			for key in ["instance_id", "enemy_instance_id"]:
				if copy.get(key) is String: copy.set(key, GRAPH.fresh_id("instance"))
		copy.transform = root.global_transform.affine_inverse() * node.global_transform
		copy.position.x += 2
		copies.append(copy)
	for node in copies:
		if node.get_script() == FACTORY.PLACE:
			for i in node.source_ids.size(): node.source_ids[i] = remap.get(node.source_ids[i], node.source_ids[i])
	if copies.is_empty(): return
	_add_nodes_undoable(root, copies, root, "复制关卡对象（新 ID）", owned_copies)

func _save_scene() -> void:
	if push_pull != null and push_pull.dragging: push_pull.finish(false)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path.is_empty(): return
	if root.get_script() == WORLD or root.get_script() == FACTORY.ROOM:
		var errors: PackedStringArray = root.validate()
		if not errors.is_empty():
			message.text = "未保存：" + "; ".join(errors)
			return
	if panel.dirty and not panel.save_graph():
		message.text = "图校验未通过，请先完成节点图。"
		return
	var err := OK
	if DisplayServer.get_name() == "headless":
		EditorInterface.save_scene_as(root.scene_file_path, false)
	else:
		err = EditorInterface.save_scene()
	if err != OK:
		message.text = "保存失败：" + error_string(err)
		return
	var reloaded: PackedScene = ResourceLoader.load(root.scene_file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if reloaded == null:
		message.text = "场景重载失败。"
		return
	var instance := reloaded.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	message.text = "已保存并从磁盘校验：" + root.scene_file_path
	instance.free()
	EditorInterface.reload_scene_from_path(root.scene_file_path)

func _exit_tree() -> void:
	if entity_gizmos != null: remove_node_3d_gizmo_plugin(entity_gizmos)
	if entity_inspector != null: remove_inspector_plugin(entity_inspector)
	if radial_tool != null: radial_tool.dispose()
	if asset_drop_tool != null: asset_drop_tool.dispose()
	if push_pull != null and push_pull.dragging: push_pull.finish(true)
	if push_pull != null: push_pull.clear()
	if gizmos != null: gizmos.face_tool = null
	if is_instance_valid(spatial_tools):
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, spatial_tools)
		spatial_tools.queue_free()
	if debugger != null: remove_debugger_plugin(debugger)
	if is_instance_valid(dock):
		remove_control_from_docks(dock_scroll)
		dock_scroll.queue_free()
	if gizmos != null: remove_node_3d_gizmo_plugin(gizmos)
	if is_instance_valid(panel): panel.queue_free()

func _set_start_room() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if root == null or root.get_script() != WORLD or selected.size() != 1 or selected[0].get_script() != FACTORY.ROOM:
		message.text = "请在世界中选中一个 Room。"
		return
	var history := get_undo_redo()
	history.create_action("设置起始房间", UndoRedo.MERGE_DISABLE, root)
	history.add_do_property(root, "start_room_id", selected[0].room_id)
	history.add_undo_property(root, "start_room_id", root.start_room_id)
	history.commit_action()
	message.text = "起始房间：" + selected[0].display_name

func _run_smoke() -> void:
	get_tree().create_timer(60, true).timeout.connect(func(): get_tree().quit(2))
	var smoke: Script = load("res://tools/level_editor/editor_smoke.gd")
	await smoke.run(self)

func _run_quick_add_test() -> void:
	await load("res://tools/level_editor/test_quick_add.gd").new().run(self)

func _run_face_gizmo_test() -> void:
	await load("res://tools/level_editor/test_face_gizmo.gd").new().run(self)

func _in_suite() -> bool:
	return "res://addons/godot_level_editor_suite/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())

func _open_graph_workspace() -> void:
	if _in_suite():
		var suite := get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
		if suite != null:
			suite.open_tab("关卡")
			suite.level_panel.set_mode(1)
	else:
		_make_visible(true)
		EditorInterface.set_main_screen_editor(_get_plugin_name())
	panel.use_current_world()

func _remember_scene(root: Node) -> void:
	_known_scene_nodes.clear()
	if root == null: return
	_known_scene_nodes[root.get_instance_id()] = true
	for node in root.find_children("*", "Node3D", true, false): _known_scene_nodes[node.get_instance_id()] = true
func _node_added(node: Node) -> void:
	if node is Node3D: _normalize_new_identity.call_deferred(node.get_instance_id())
func _normalize_new_identity(node_id: int) -> void:
	if not is_instance_id_valid(node_id): return
	var node := instance_from_id(node_id) as Node
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	var root := EditorInterface.get_edited_scene_root()
	if root == null or node.owner != root or _known_scene_nodes.has(node.get_instance_id()): return
	_known_scene_nodes[node.get_instance_id()] = true
	var key := "room_id" if node.get_script() == FACTORY.ROOM else "instance_id" if node.get_script() == preload("res://addons/godot_level_editor_mechanisms/runtime/assembly.gd") else "object_id"
	var value: Variant = node.get(key)
	if not value is String: return
	if value.is_empty():
		node.set(key, GRAPH.fresh_id("instance"))
		value = node.get(key)
	var scope: Node = node.get_parent()
	while GROUPS.is_group(scope): scope = scope.get_parent()
	for sibling in GROUPS.contents(scope):
		if sibling != node and sibling.get(key) == value:
			node.set(key, GRAPH.fresh_id("room" if key == "room_id" else "object"))
			EditorInterface.mark_scene_as_unsaved()
			break
	if key == "room_id" and node.uses_topology and root.get_script() == WORLD and root.rooms().size() == 1 and root.start_room_id != node.room_id:
		root.start_room_id = node.room_id
		EditorInterface.mark_scene_as_unsaved()
