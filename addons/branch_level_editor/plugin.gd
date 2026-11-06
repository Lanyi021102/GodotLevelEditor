@tool
extends EditorPlugin
const PANEL := preload("res://addons/branch_level_editor/graph_panel.gd")
const DEBUGGER := preload("res://addons/branch_level_editor/debugger.gd")
const FACTORY := preload("res://addons/branch_level_editor/scene_factory.gd")
const WORLD := preload("res://addons/branch_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/branch_level_editor/runtime/level_graph.gd")
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
var size_fields: Array[SpinBox] = []
var gizmos: EditorNode3DGizmoPlugin
var push_pull: RefCounted
var push_buttons: Array[Button] = []
var spatial_tools: HBoxContainer
const ITEM := preload("res://addons/branch_level_editor/palette_item.gd")
const SHAPES := preload("res://addons/branch_level_editor/runtime/whitebox_shapes.gd")
const OBJECT_LABELS := {"room": "房间区域 Room", "region": "目标 / 触发区域", "spawn": "玩家出生点", "port": "房间接驳点", "lever": "开关", "plate": "压力板", "kinetic": "动能板", "breaker": "电闸", "door": "门", "guard": "敌人", "placeholder": "自定义组件"}

func _enter_tree() -> void:
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
	gizmos = preload("res://addons/branch_level_editor/block_gizmo.gd").new()
	add_node_3d_gizmo_plugin(gizmos)
	push_pull = preload("res://addons/branch_level_editor/push_pull_tool.gd").new()
	push_pull.plugin = self
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	spatial_tools = HBoxContainer.new()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, spatial_tools)
	_push_button(spatial_tools)
	_push_button(dock)
	_button("移动吸附设为 0.1", _configure_snap)
	_configure_snap.call_deferred()
	_button("打开触发／操作／判断示例", func(): EditorInterface.open_scene_from_path("res://scenes/level_editor/logic_playground.tscn"))
	_button("打开首版连续世界", func(): EditorInterface.open_scene_from_path("res://scenes/level_editor/continuous_world.tscn"))
	_button("新建房间 .tscn", func(): _choose_file("room"))
	_button("新建世界 .tscn", func(): _choose_file("world"))
	_button("实例化房间到世界", func(): _choose_file("instance"))
	_button("设选中 Room 为起始房间", _set_start_room)
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
	note.text = "推拉面：选面后拖动；推拉与移动均为 0.1。"
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
	_button("打开节点图", func(): _make_visible(true); EditorInterface.set_main_screen_editor(_get_plugin_name()); panel.use_current_world())
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
	if OS.get_cmdline_user_args().has("--branch-level-smoke"):
		_run_smoke.call_deferred()

func _button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	dock.add_child(button)

func _push_button(parent: Node) -> void:
	var button := Button.new()
	button.text = "推拉面 · 0.1"
	button.toggle_mode = true
	button.tooltip_text = "点击白盒的面并拖动；松开确认，Esc 取消。"
	button.toggled.connect(func(value: bool):
		for other in push_buttons: other.set_pressed_no_signal(value)
		push_pull.set_enabled(value))
	parent.add_child(button)
	push_buttons.append(button)

func _configure_snap() -> void:
	var configured := preload("res://addons/branch_level_editor/native_snap.gd").configure()
	if is_instance_valid(message): message.text = "三维物件移动吸附已设为 0.1；推拉面也按 0.1 推进。" if configured else "请在三维视口的“变换 → 配置吸附”中将平移设为 0.1，并开启吸附。"

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	return EditorPlugin.AFTER_GUI_INPUT_STOP if push_pull.input(camera, event) else EditorPlugin.AFTER_GUI_INPUT_PASS
func _forward_3d_force_draw_over_viewport(control: Control) -> void:
	if push_pull != null: push_pull.draw(control)

func _has_main_screen() -> bool: return true
func _get_plugin_name() -> String: return "关卡与世界"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("GraphEdit", "EditorIcons")
func _make_visible(value: bool) -> void:
	if is_instance_valid(panel): panel.visible = value
func _handles(object: Object) -> bool: return object is BranchLevelGraph
func _edit(object: Object) -> void:
	if object is BranchLevelGraph: panel.open_graph(object)
func _get_unsaved_status(_for_scene: String) -> String:
	return "关卡节点图有未保存修改，请先保存。" if is_instance_valid(panel) and panel.dirty else ""

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.dirty: panel.save_graph()

func _scene_changed(root: Node) -> void:
	_configure_snap.call_deferred()
	if push_pull != null:
		if push_pull.dragging: push_pull.finish(true)
		push_pull.clear()
	if not panel.dirty and root != null and root.get_script() == WORLD:
		panel.world = root
		panel._switch_graph()

func _selection_changed() -> void:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	if push_pull != null and not push_pull.dragging and not push_pull.picked.is_empty() and not nodes.has(push_pull.picked.get("block")): push_pull.clear()
	if nodes.size() == 1:
		panel.focus_object(nodes[0])
		if nodes[0].get_script() == FACTORY.BLOCK:
			for axis in size_fields.size(): size_fields[axis].set_value_no_signal(nodes[0].size[axis])

func _choose_file(action: String) -> void:
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
		FACTORY.boundary(node, [])
	else:
		node = WORLD.new()
		node.name = "BranchWorld"
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
		node.bounds_size = Vector3(10, 4, 10)
	elif kind == "spawn": node = preload("res://addons/branch_level_editor/runtime/spawn_marker.gd").new()
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
	var history := get_undo_redo()
	history.create_action(title, UndoRedo.MERGE_DISABLE, root)
	history.add_do_method(parent, "add_child", node, true)
	history.add_do_method(node, "set_owner", root)
	history.add_undo_method(parent, "remove_child", node)
	history.add_do_reference(node)
	history.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(node)

func _duplicate_spatial() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not root.get_script() in [FACTORY.ROOM, WORLD]: return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var remap := {}
	var copies: Array[Node] = []
	for node in selected:
		if node.get_parent() != root or (not node.get("object_id") is String and node.get_script() != FACTORY.ROOM): continue
		var copy := node.duplicate()
		# Generated previews have no owner and must not become authored children.
		for child in copy.get_children():
			if child.owner == null and not child.get("object_id") is String: child.free()
		var id := GRAPH.fresh_id("room" if node.get_script() == FACTORY.ROOM else "object")
		if node.get_script() == FACTORY.ROOM:
			copy.room_id = id
			copy.display_name += "（副本）"
		else:
			remap[node.object_id] = id
			copy.object_id = id
		copy.position.x += 2
		copies.append(copy)
	for node in copies:
		if node.get_script() == FACTORY.PLACE:
			for i in node.source_ids.size(): node.source_ids[i] = remap.get(node.source_ids[i], node.source_ids[i])
	if copies.is_empty(): return
	var history := get_undo_redo()
	history.create_action("复制关卡对象（新 ID）", UndoRedo.MERGE_DISABLE, root)
	for node in copies:
		history.add_do_method(root, "add_child", node, true)
		history.add_do_method(node, "set_owner", root)
		if node.get_script() == FACTORY.ROOM:
			for child in node.get_children():
				if child.get("object_id") is String: history.add_do_method(child, "set_owner", root)
		history.add_undo_method(root, "remove_child", node)
		history.add_do_reference(node)
	history.commit_action()
	EditorInterface.get_selection().clear()
	for node in copies: EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(copies[0])

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
	if push_pull != null and push_pull.dragging: push_pull.finish(true)
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
