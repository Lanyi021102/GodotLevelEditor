@tool
extends EditorPlugin
const PanelScript := preload("res://addons/godot_level_editor/modules/enemy_editor/editor_panel.gd")
const DebuggerScript := preload("res://addons/godot_level_editor/modules/enemy_editor/debugger.gd")
var panel: Control
var debugger: EditorDebuggerPlugin
var gizmos: EditorNode3DGizmoPlugin
var scene_guard: Node
var _assign_pending := false
var _test_suite: RefCounted

func _enter_tree() -> void:
	set_meta("godot_level_editor_module", "enemies")
	add_to_group("godot_level_editor_suite_modules")
	panel = PanelScript.new()
	panel.name = "EnemyEditor"
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	panel.scene_validator = _scene_binding_errors.bind(false)
	panel.definition_saved.connect(func(_path: String): EditorInterface.get_resource_filesystem().scan())
	panel.focus_guard_requested.connect(_focus_guard)
	panel.bind_guard_requested.connect(_bind_guard)
	panel.create_route_requested.connect(_create_route)
	gizmos = preload("res://addons/godot_level_editor/modules/enemy_editor/guard_gizmo.gd").new()
	add_node_3d_gizmo_plugin(gizmos)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	scene_changed.connect(func(_root: Node): _queue_assign_ids())
	get_tree().node_added.connect(_node_added)
	_queue_assign_ids()
	debugger = DebuggerScript.new()
	debugger.state_received.connect(panel.receive_runtime)
	debugger.instance_removed.connect(panel.remove_runtime)
	debugger.session_cleared.connect(panel.clear_session)
	debugger.session_pause_changed.connect(panel.set_session_paused)
	add_debugger_plugin(debugger)
	if OS.get_cmdline_user_args().has("--test-enemy-canvas"):
		_test_suite = load("res://tools/enemy_editor/test_canvas.gd").new()
		_test_suite.run.call_deferred(panel, self)
	if OS.get_cmdline_user_args().has("--test-enemy-debugger"):
		_test_suite = load("res://tools/enemy_editor/test_debugger.gd").new()
		_test_suite.run.call_deferred(panel, self)
	if OS.get_cmdline_user_args().has("--test-npc-appearance"):
		_test_suite = load("res://tools/enemy_editor/test_npc_appearance.gd").new()
		_test_suite.run.call_deferred(panel, self)
	if OS.get_cmdline_user_args().has("--test-npc-samples-v1"):
		_test_suite = load("res://tools/enemy_editor/npc_samples_v1/test_editor.gd").new()
		_test_suite.run.call_deferred(panel, self)

func _has_main_screen() -> bool:
	return not _in_suite()

func _get_plugin_name() -> String:
	return "敌人状态机"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("AnimationNodeStateMachine", "EditorIcons")

func _make_visible(value: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = value

func _handles(object: Object) -> bool:
	return object is EnemyDefinition

func _edit(object: Object) -> void:
	if object is EnemyDefinition and not object.resource_path.is_empty():
		panel.request_open(object.resource_path)

func _save_external_data() -> void:
	# Explicit Save in the panel; scene saves must not overwrite a draft.
	pass

func _get_unsaved_status(_for_scene: String) -> String:
	return "敌人状态机有未保存修改，请在插件中保存。" if is_instance_valid(panel) and panel.dirty else ""

func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
	if gizmos != null: remove_node_3d_gizmo_plugin(gizmos)
	if debugger != null:
		remove_debugger_plugin(debugger)
	if is_instance_valid(panel):
		panel.queue_free()


func _is_guard(node: Node) -> bool:
	return is_instance_valid(node) and node.get_script() != null and node.get_script().resource_path == "res://addons/godot_level_editor/scripts/stealth/guard_ai.gd"

func _scene_guards() -> Array[Node]:
	var root := EditorInterface.get_edited_scene_root()
	var result: Array[Node] = []
	if root == null: return result
	if _is_guard(root): result.append(root)
	for node in root.find_children("*", "", true, false):
		if _is_guard(node): result.append(node)
	return result

func _node_added(node: Node) -> void:
	if _is_guard(node): _queue_assign_ids()

func _queue_assign_ids() -> void:
	if _assign_pending: return
	_assign_pending = true
	_assign_ids.call_deferred()

func _assign_ids() -> void:
	_assign_pending = false
	var seen := {}
	var changed := false
	for guard in _scene_guards():
		var id := str(guard.get("enemy_instance_id"))
		if id.is_empty() or seen.has(id):
			id = "enemy_" + Crypto.new().generate_random_bytes(12).hex_encode()
			guard.set("enemy_instance_id", id)
			changed = true
		seen[id] = true
	if changed: EditorInterface.mark_scene_as_unsaved()

func _selection_changed() -> void:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	for node in nodes:
		if _is_guard(node):
			scene_guard = node
			var definition: Resource = node.get("enemy_definition")
			if definition != null and not definition.resource_path.is_empty(): panel.request_open(definition.resource_path)
			elif definition == null: panel.request_open(panel.TEMPLATE_PATH)
			panel.set_scene_guard_label("场景守卫：%s · %s" % [node.name, node.get("enemy_instance_id")])
			return

func _guard_matches_definition(guard: Node) -> bool:
	if not is_instance_valid(guard): return false
	var source: Resource = guard.get("enemy_definition")
	var path := source.resource_path if source != null else str(panel.TEMPLATE_PATH)
	return path == (panel.file_path if not panel.file_path.is_empty() else panel.TEMPLATE_PATH)

func _focus_guard() -> void:
	if not _guard_matches_definition(scene_guard):
		scene_guard = null
		for guard in _scene_guards():
			if _guard_matches_definition(guard):
				scene_guard = guard
				break
	if not is_instance_valid(scene_guard):
		panel.status.text = "当前场景没有关联守卫；请在场景树选择守卫并绑定定义。"
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(scene_guard)
	EditorInterface.edit_node(scene_guard)
	EditorInterface.set_main_screen_editor("3D")
	(scene_guard as Node3D).update_gizmos()

func _bind_guard() -> void:
	if not is_instance_valid(scene_guard):
		panel.status.text = "请先在场景树选择一个守卫。"
		return
	if panel.file_path.is_empty() or panel.dirty:
		panel.status.text = "请先保存当前定义，再绑定到所选守卫。"
		return
	var source := ResourceLoader.load(panel.file_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	var undo := get_undo_redo()
	undo.create_action("绑定敌人定义")
	undo.add_do_property(scene_guard, "enemy_definition", source)
	undo.add_undo_property(scene_guard, "enemy_definition", scene_guard.get("enemy_definition"))
	undo.commit_action()
	panel.status.text = "已绑定到 %s；保存场景后生效。" % scene_guard.name

func _create_route() -> void:
	if not is_instance_valid(scene_guard):
		panel.status.text = "请先选择一个场景守卫。"
		return
	var old_path: NodePath = scene_guard.get("patrol_route")
	if not old_path.is_empty() and scene_guard.get_node_or_null(old_path) != null:
		panel.status.text = "已有路点节点；展开守卫的 PatrolRoute，在三维视口移动 Marker3D。"
		return
	var route := Node3D.new()
	var route_name := "PatrolRoute"
	var suffix := 2
	while scene_guard.has_node(NodePath(route_name)):
		route_name = "PatrolRoute%d" % suffix
		suffix += 1
	route.name = route_name
	var root := EditorInterface.get_edited_scene_root()
	var points: Array = scene_guard.get("patrol_points")
	if points.is_empty(): points = [(scene_guard as Node3D).global_position + Vector3.LEFT * 2, (scene_guard as Node3D).global_position + Vector3.RIGHT * 2]
	for i in points.size():
		var marker := Marker3D.new()
		marker.name = "Point%d" % (i + 1)
		marker.position = (scene_guard as Node3D).to_local(points[i])
		route.add_child(marker)
	var undo := get_undo_redo()
	undo.create_action("创建敌人巡逻路点")
	undo.add_do_method(scene_guard, "add_child", route, true)
	undo.add_do_method(route, "set_owner", root)
	for marker in route.get_children(): undo.add_do_method(marker, "set_owner", root)
	undo.add_do_property(scene_guard, "patrol_route", NodePath(route_name))
	undo.add_do_method(scene_guard, "update_gizmos")
	undo.add_undo_property(scene_guard, "patrol_route", old_path)
	undo.add_undo_method(scene_guard, "remove_child", route)
	undo.add_do_reference(route)
	undo.commit_action()
	panel.status.text = "已创建路点；在三维视口移动 Marker3D，运行时读取真实世界位置。"


func _scene_binding_errors(all_definitions := true) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for guard in _scene_guards():
		if not all_definitions and not _guard_matches_definition(guard): continue
		var source: Resource = guard.get("enemy_definition")
		if source != null and source is EnemyDefinition: errors.append_array(source.validate())
		var id := str(guard.get("enemy_instance_id"))
		if not id.is_empty():
			if seen.has(id): errors.append("守卫实例标识重复：" + id)
			seen[id] = true
		var path: NodePath = guard.get("patrol_route")
		if not path.is_empty():
			var route := guard.get_node_or_null(path)
			if not route is Node3D:
				errors.append("%s：巡逻路点引用不存在" % guard.name)
			elif not route.get_children().any(func(child: Node): return child is Marker3D):
				errors.append("%s：巡逻路线至少需要一个 Marker3D" % guard.name)
		else:
			for point in guard.get("patrol_points"):
				if not (point as Vector3).is_finite(): errors.append("%s：巡逻点坐标无效" % guard.name)
	return errors

func _build() -> bool:
	var errors := _scene_binding_errors()
	if not errors.is_empty():
		push_error("敌人场景验证失败：" + "；".join(errors))
		return false
	return true

func _in_suite() -> bool:
	return "res://addons/godot_level_editor/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
