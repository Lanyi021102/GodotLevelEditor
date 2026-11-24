@tool
extends EditorPlugin
const PANEL := preload("res://addons/godot_level_editor/modules/godot_level_editor/graph_panel.gd")
const DEBUGGER := preload("res://addons/godot_level_editor/modules/godot_level_editor/debugger.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const GROUPS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
var panel: Control
var debugger: EditorDebuggerPlugin
var _known_scene_nodes: Dictionary = {}
var gizmos: EditorNode3DGizmoPlugin
var push_pull: RefCounted
var push_buttons: Array[Button] = []
var selection_buttons: Dictionary = {}
var last_message := ""
var _legacy_dock_checked := false
var edit_step := 0.1
var step_input: LineEdit
var step_presets: MenuButton
const STEP_METADATA := "godot_level_editor_edit"
const STEP_PRESETS := [0.1, 0.5, 1.0]
var spatial_tools: HBoxContainer
var radial_tool: RefCounted
var measurement: RefCounted
var terrain_tool: RefCounted
var performance_point_pick := Callable()
var asset_drop_tool: RefCounted
var entity_inspector: EditorInspectorPlugin
var entity_gizmos: EditorNode3DGizmoPlugin
var vehicle_gizmos: EditorNode3DGizmoPlugin
var vehicle_inspector: EditorInspectorPlugin


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
	gizmos = preload("res://addons/godot_level_editor/modules/godot_level_editor/block_gizmo.gd").new()
	add_node_3d_gizmo_plugin(gizmos)
	push_pull = preload("res://addons/godot_level_editor/modules/godot_level_editor/push_pull_tool.gd").new()
	push_pull.plugin = self
	gizmos.face_tool = push_pull
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	spatial_tools = HBoxContainer.new()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, spatial_tools)
	radial_tool = preload("res://addons/godot_level_editor/modules/godot_level_editor/radial_tool.gd").new()
	radial_tool.setup(self, spatial_tools)
	asset_drop_tool = preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_drop_tool.gd").new()
	asset_drop_tool.plugin = self
	entity_inspector = preload("res://addons/godot_level_editor/modules/godot_level_editor/entity_inspector.gd").new()
	entity_inspector.plugin = self
	add_inspector_plugin(entity_inspector)
	entity_gizmos = preload("res://addons/godot_level_editor/modules/godot_level_editor/entity_gizmo.gd").new()
	add_node_3d_gizmo_plugin(entity_gizmos)
	vehicle_inspector = preload("res://addons/godot_level_editor/modules/godot_level_editor_vehicle/vehicle_inspector.gd").new()
	vehicle_inspector.editor = self
	add_inspector_plugin(vehicle_inspector)
	vehicle_gizmos = preload("res://addons/godot_level_editor/modules/godot_level_editor_vehicle/vehicle_gizmo.gd").new()
	add_node_3d_gizmo_plugin(vehicle_gizmos)
	main_screen_changed.connect(func(screen: String):
		if screen != "3D":
			if measurement != null: measurement.cancel()
			if radial_tool != null: radial_tool.cancel()
			if terrain_tool != null: terrain_tool.cancel()
			if push_pull.enabled: push_pull.set_enabled(false))
	for mode in ["face", "edge", "point"]: _push_button(spatial_tools, mode)
	_build_step_controls()
	measurement = preload("res://addons/godot_level_editor/modules/godot_level_editor/measure_tool.gd").new()
	measurement.setup(self, spatial_tools)
	terrain_tool = preload("terrain/editor_tool.gd").new()
	terrain_tool.setup(self, spatial_tools)
	measurement.update_selection(EditorInterface.get_selection().get_selected_nodes())
	_configure_snap.call_deferred()
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	scene_changed.connect(_scene_changed)
	get_tree().node_added.connect(_node_added)
	_remember_scene(EditorInterface.get_edited_scene_root())
	if OS.get_cmdline_user_args().has("--godot-level-editor-level-smoke"):
		_run_smoke.call_deferred()
	if OS.get_cmdline_user_args().has("--quick-add-test"):
		_run_quick_add_test.call_deferred()
	if OS.get_cmdline_user_args().has("--terrain-test"):
		_run_terrain_test.call_deferred()
	if OS.get_cmdline_user_args().has("--face-gizmo-test"):
		_run_face_gizmo_test.call_deferred()

func _push_button(parent: Node, mode := "face") -> void:
	var button := Button.new()
	button.text = {"face": "选中面", "edge": "选中线", "point": "选中点"}[mode]
	button.toggle_mode = true
	button.tooltip_text = "选中元素后在其中心拖动操作轴；Esc／点击空白恢复物体轴。"
	button.toggled.connect(func(value: bool):
		if value and radial_tool != null: radial_tool.cancel()
		if value:
			if measurement != null: measurement.cancel()
			if terrain_tool != null: terrain_tool.cancel()
			push_pull.set_mode(mode)
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
		show_message("步长请输入 0.001–1000 之间的数字。")

func _set_edit_step(value: float) -> bool:
	if not is_finite(value) or value < 0.001 or value > 1000: return false
	edit_step = snappedf(value, 0.001)
	step_input.text = String.num(edit_step, 3)
	EditorInterface.get_editor_settings().set_project_metadata(STEP_METADATA, "step", edit_step)
	_configure_snap()
	return true

func _configure_snap() -> void:
	var configured := preload("res://addons/godot_level_editor/modules/godot_level_editor/native_snap.gd").configure(edit_step)
	show_message("移动／推拉／放置步长已设为 %s 米。" % String.num(edit_step, 3) if configured else "请在三维视口的“变换 → 配置吸附”中将平移设为 %s，并开启吸附。" % String.num(edit_step, 3), not configured)

func show_message(text: String, notify := true) -> void:
	if is_instance_valid(spatial_tools): spatial_tools.tooltip_text = text
	if text == last_message: return
	last_message = text
	if notify: EditorInterface.get_editor_toaster().push_toast(text)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if performance_point_pick.is_valid() and _pick_performance_point(camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if radial_tool != null and radial_tool.input(camera, event): return EditorPlugin.AFTER_GUI_INPUT_STOP
	if terrain_tool != null and terrain_tool.input(camera, event): return EditorPlugin.AFTER_GUI_INPUT_STOP
	if measurement != null and measurement.input(camera, event): return EditorPlugin.AFTER_GUI_INPUT_STOP
	if push_pull.input(camera, event): return EditorPlugin.AFTER_GUI_INPUT_STOP
	if push_pull.uses_native_gizmo(): return EditorPlugin.AFTER_GUI_INPUT_CUSTOM
	return EditorPlugin.AFTER_GUI_INPUT_PASS
func _pick_performance_point(camera: Camera3D, event: InputEvent) -> bool:
	var finish := performance_point_pick
	if event.is_action_pressed("ui_cancel"):
		performance_point_pick = Callable()
		finish.call_deferred(null)
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit: Dictionary = radial_tool.pick_surface(camera, event.position, EditorInterface.get_edited_scene_root()) if radial_tool != null else {}
		if hit.is_empty():
			show_message("请在可见的地面上选点，或按 Esc 取消。")
		else:
			performance_point_pick = Callable()
			finish.call_deferred(hit.position)
		return true
	return false

func _forward_3d_force_draw_over_viewport(control: Control) -> void:
	if push_pull != null: push_pull.draw(control)
	if radial_tool != null: radial_tool.draw(control)
	if measurement != null: measurement.draw(control)
	if terrain_tool != null: terrain_tool.draw(control)

func _process(delta: float) -> void:
	if not _legacy_dock_checked:
		_legacy_dock_checked = true
		_retire_legacy_dock()
	# Tool scripts can reload while the user keeps unsaved level edits open.
	if entity_inspector == null:
		entity_inspector = preload("res://addons/godot_level_editor/modules/godot_level_editor/entity_inspector.gd").new(); entity_inspector.plugin = self; add_inspector_plugin(entity_inspector)
	if entity_gizmos == null:
		entity_gizmos = preload("res://addons/godot_level_editor/modules/godot_level_editor/entity_gizmo.gd").new(); add_node_3d_gizmo_plugin(entity_gizmos)
	if radial_tool != null: radial_tool.process()
	if measurement != null: measurement.process()
	if terrain_tool != null: terrain_tool.process(delta)
	if asset_drop_tool == null and radial_tool != null:
		asset_drop_tool = preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_drop_tool.gd").new()
		asset_drop_tool.plugin = self
	if asset_drop_tool != null: asset_drop_tool.sync()

func _retire_legacy_dock() -> void:
	# A tool-script reload can leave controls registered by the previous version.
	for legacy in EditorInterface.get_base_control().find_children("关卡摆放", "ScrollContainer", true, false):
		for mode in selection_buttons:
			selection_buttons[mode] = selection_buttons[mode].filter(func(button: Button): return is_instance_valid(button) and not legacy.is_ancestor_of(button))
		push_buttons.assign(push_buttons.filter(func(button: Button): return is_instance_valid(button) and not legacy.is_ancestor_of(button)))
		remove_control_from_docks(legacy)
		legacy.queue_free()

func _build() -> bool:
	if measurement != null: measurement.cancel()
	if radial_tool != null: radial_tool.cancel()
	if terrain_tool != null: terrain_tool.cancel()
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
	performance_point_pick = Callable()
	if measurement != null: measurement.cancel()
	if radial_tool != null: radial_tool.cancel()
	if terrain_tool != null: terrain_tool.cancel()
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
	if measurement != null: measurement.update_selection(nodes)
	if push_pull != null and not push_pull.selecting and not push_pull.dragging and not push_pull.picked.is_empty() and not nodes.has(push_pull.picked.get("block")): push_pull.clear()
	if nodes.size() == 1:
		panel.focus_object(nodes[0])

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
		if properties != null and properties.get_script() == preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_binding.gd"):
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

func _exit_tree() -> void:
	if vehicle_gizmos != null: remove_node_3d_gizmo_plugin(vehicle_gizmos)
	if vehicle_inspector != null: remove_inspector_plugin(vehicle_inspector)
	if entity_gizmos != null: remove_node_3d_gizmo_plugin(entity_gizmos)
	if entity_inspector != null: remove_inspector_plugin(entity_inspector)
	if radial_tool != null: radial_tool.dispose()
	if terrain_tool != null: terrain_tool.dispose()
	if asset_drop_tool != null: asset_drop_tool.dispose()
	if push_pull != null and push_pull.dragging: push_pull.finish(true)
	if push_pull != null: push_pull.clear()
	if gizmos != null: gizmos.face_tool = null
	if is_instance_valid(spatial_tools):
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, spatial_tools)
		spatial_tools.queue_free()
	if debugger != null: remove_debugger_plugin(debugger)
	if gizmos != null: remove_node_3d_gizmo_plugin(gizmos)
	if is_instance_valid(panel): panel.queue_free()

func _run_smoke() -> void:
	get_tree().create_timer(60, true).timeout.connect(func(): get_tree().quit(2))
	var smoke: Script = load("res://tools/level_editor/editor_smoke.gd")
	await smoke.run(self)

func _run_quick_add_test() -> void:
	await load("res://tools/level_editor/test_quick_add.gd").new().run(self)

func _run_terrain_test() -> void:
	await load("res://tools/level_editor/test_terrain.gd").new().run(self)

func _run_face_gizmo_test() -> void:
	await load("res://tools/level_editor/test_face_gizmo.gd").new().run(self)

func _in_suite() -> bool:
	return "res://addons/godot_level_editor/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())

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
	# An assembly has both a level-object reference and a component instance ID.
	# Repair each identity on the new node; existing authored nodes stay untouched.
	var keys: Array = ["room_id"] if node.get_script() == FACTORY.ROOM else ["object_id", "instance_id", "enemy_instance_id"]
	var scope: Node = node.get_parent()
	while GROUPS.is_group(scope): scope = scope.get_parent()
	for key in keys:
		var value: Variant = node.get(key)
		if not value is String: continue
		var used := {}
		for sibling in GROUPS.contents(scope):
			if sibling != node and sibling.get(key) is String: used[sibling.get(key)] = true
		if value.is_empty() or used.has(value):
			var prefix := "room" if key == "room_id" else "object" if key == "object_id" else "instance"
			var replacement := GRAPH.fresh_id(prefix)
			while used.has(replacement): replacement = GRAPH.fresh_id(prefix)
			node.set(key, replacement)
			EditorInterface.mark_scene_as_unsaved()
	if node.get_script() == FACTORY.ROOM and node.uses_topology and root.get_script() == WORLD and root.rooms().size() == 1 and root.start_room_id != node.room_id:
		root.start_room_id = node.room_id
		EditorInterface.mark_scene_as_unsaved()
