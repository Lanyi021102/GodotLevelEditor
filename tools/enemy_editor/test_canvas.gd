@tool
extends RefCounted
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func run(panel: Control, plugin: EditorPlugin) -> void:
	for _i in 12: await panel.get_tree().process_frame
	panel.show()
	for _i in 2: await panel.get_tree().process_frame
	check(panel.graph.get_connection_list().size() == 9, "画布显示实际转换端点")
	var presentation = load("res://addons/enemy_editor/graph/node_presentation.gd")
	var expected_colors := {"condition": "94700e", "trigger": "a34439", "state": "24756e", "action": "345f96", "data": "71508f", "flow": "9b592b"}
	var palette_ok := true
	for key in expected_colors:
		palette_ok = palette_ok and presentation.CATEGORIES[key].color.to_html(false) == expected_colors[key]
	check(palette_ok, "复用机关蓝图六类职责色")
	check(panel.get_node("CategoryLegend").get_child_count() == 7, "画布提供六类文字颜色图例及连接类型说明")
	var all_states := true
	var ports_unchanged := true
	for child in panel.graph.get_children():
		if child is GraphNode:
			all_states = all_states and child.get_meta("node_category") == "state" and child.title.begins_with("状态 · ")
			ports_unchanged = ports_unchanged and child.get_input_port_count() == 1 and child.get_output_port_count() == 1 and child.get_input_port_slot(0) == 1 and child.get_output_port_slot(0) == 1 and child.get_input_port_type(0) == 0 and child.get_output_port_type(0) == 0 and not child.is_slot_enabled_left(0) and not child.is_slot_enabled_right(0)
	var template_nodes: Array = panel.graph.get_children().filter(func(child: Node): return child is GraphNode)
	var no_overlap := true
	for i in template_nodes.size():
		for j in range(i + 1, template_nodes.size()):
			no_overlap = no_overlap and not Rect2(template_nodes[i].position_offset, template_nodes[i].size).intersects(Rect2(template_nodes[j].position_offset, template_nodes[j].size))
	check(no_overlap, "默认四状态排版新增标识后不遮挡其他节点")
	check(all_states, "持续敌人状态按状态分类，不误标为触发或动作")
	check(ports_unchanged, "标识行无端口，启用端口连接索引仍为 0，类型不变")
	var patrol: GraphNode = panel.graph.get_node("s_patrol")
	check(patrol.get_node("PortDirections/InputDirection").text == "输入 →" and patrol.get_node("PortDirections/OutputDirection").text == "→ 输出", "两侧方向文字靠近对应输入输出")
	check(patrol.get_node("TransitionPorts/InputLabel").tooltip_text.contains("state_enter") and patrol.get_node("TransitionPorts/OutputLabel").tooltip_text.contains("state_exit"), "保留端口稳定 ID 与悬停语义")
	var only_output = presentation.Shared.direction_row(false, true)
	check(only_output.get_node("InputDirection").text.is_empty() and only_output.get_node("OutputDirection").text == "→ 输出", "无端口侧不显示方向标识")
	only_output.free()
	patrol.selected = true
	check(patrol.get_theme_stylebox("titlebar").bg_color == Color("24756e") and patrol.get_theme_stylebox("titlebar_selected").bg_color == Color("24756e"), "选中保留状态分类色")
	panel.selected_state = "patrol"
	panel._set_state("speed", 2.6)
	check(is_equal_approx(panel.definition.state_by_id("patrol").speed, 2.6), "参数编辑仍然生效")
	panel.history.undo()
	check(is_equal_approx(panel.definition.state_by_id("patrol").speed, 2.0), "参数编辑可撤销")
	var old_count: int = panel.definition.states.size()
	panel.add_state()
	check(panel.definition.states.size() == old_count + 1, "画布添加节点")
	panel.history.undo()
	check(panel.definition.states.size() == old_count, "撤销添加")
	panel.history.redo()
	check(panel.definition.states.size() == old_count + 1, "重做添加")
	panel._connect_nodes("s_patrol", 0, "s_state1", 0)
	check(panel.definition.transitions.back().to == "state1", "端口连线写入可执行定义")
	panel._disconnect_nodes("s_patrol", 0, "s_state1", 0)
	check(not panel.definition.transitions.any(func(t: Dictionary): return t.to == "state1"), "断线删除实际转换")
	panel.history.undo()
	check(panel.definition.transitions.back().to == "state1", "撤销断线")
	panel._delete_nodes(["s_state1"])
	check(panel.definition.state_by_id("state1").is_empty() and not panel.definition.transitions.any(func(t: Dictionary): return t.to == "state1"), "删除节点级联移除相关转换")
	panel.history.undo()
	check(not panel.definition.state_by_id("state1").is_empty(), "撤销级联删除")
	var node = panel.graph.get_node("s_state1")
	node.selected = true
	panel._copy_selected()
	panel._paste_selected()
	check(panel.definition.states.size() == old_count + 2 and panel.definition.validate().is_empty(), "复制粘贴分配新稳定 ID")
	panel.graph.scroll_offset = Vector2(100, 120)
	panel.graph.zoom = 0.8
	panel._capture_view()
	panel._save_to("res://tools/enemy_editor/.canvas_roundtrip.tres")
	check(not panel.dirty, "保存清除未保存状态")
	panel.add_state()
	panel._load("res://tools/enemy_editor/.canvas_roundtrip.tres")
	check(panel.definition.states.size() == old_count + 2 and is_equal_approx(panel.definition.layout.zoom, 0.8), "重载恢复图与画布视图")
	panel.receive_runtime("1:guard", {"instance": "/root/Guard", "definition": panel.file_path, "state_id": "alert", "timer": 3.0, "last_transition": "patrol_expose", "rewound": true, "session": 1, "alert": 100.0})
	var active: GraphNode = panel.graph.get_node("s_alert")
	check(active.get_meta("runtime_active") and panel.runtime_label.text.contains("回溯") and active.get_node("RuntimeValue").text.contains("回溯"), "运行状态与回溯边框、绿点、文字高亮")
	check(active.self_modulate == Color.WHITE and active.modulate == Color.WHITE and active.get_theme_stylebox("titlebar").bg_color == Color("24756e"), "回溯不整节点染色或淡化分类色")
	active.selected = true
	check(active.get_theme_stylebox("panel_selected").border_color == presentation.ACTIVE and active.get_theme_stylebox("titlebar_selected").bg_color == Color("24756e"), "活动且选中时保留分类色和绿色边框")
	var signature: String = panel._signature()
	panel.receive_runtime("1:guard", {"instance": "/root/Guard", "definition": panel.file_path, "state_id": "alert", "timer": 2.0, "last_transition": "patrol_expose", "last_reason": "巡逻 → 警戒 · 警觉 ≥ 100", "rewound": false, "session": 1, "alert": 100.0})
	check(active.get_node("RuntimeValue").text.contains("运行中") and active.get_node("RuntimeMetrics").text.contains("警觉 100") and active.get_node("RuntimeValue").tooltip_text.contains("警觉 ≥ 100"), "保留实际执行、当前数值与最近转换原因")
	plugin.debugger.session_pause_changed.emit(1, true)
	check(active.get_node("RuntimeValue").text.contains("暂停") and active.get_theme_stylebox("titlebar_selected").bg_color == Color("24756e"), "调试暂停保留分类色和活动提示")
	plugin.debugger.session_pause_changed.emit(1, false)
	check(active.get_node("RuntimeValue").text.contains("运行中") and panel._signature() == signature, "恢复显示且运行呈现不修改定义资源")
	panel.clear_session(1)
	check(panel.runtime.is_empty() and not panel.graph.get_node("s_alert").get_meta("runtime_active") and panel.graph.get_node("s_alert").self_modulate == Color.WHITE, "结束会话清理高亮")
	panel.search_edit.text = "巡逻"
	panel._search_nodes()
	check(panel.search_results.item_count == 1, "搜索过滤行为节点")
	var scene_root := EditorInterface.get_edited_scene_root()
	check(scene_root != null and scene_root.name == "EnemyBlueprintSample", "独立三维样例在编辑器打开")
	if scene_root != null and scene_root.has_node("Guard"):
		var guard := scene_root.get_node("Guard")
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(guard)
		await panel.get_tree().process_frame
		await panel.get_tree().process_frame
		check(plugin.scene_guard == guard and panel.file_path.ends_with("guard_default.tres"), "场景对象选择定位对应蓝图")
		panel._load("res://tools/enemy_editor/.canvas_roundtrip.tres")
		plugin._bind_guard()
		check(guard.get("enemy_definition").resource_path == panel.file_path, "蓝图资源绑定到真实三维守卫")
		var history_id := plugin.get_undo_redo().get_object_history_id(guard)
		var scene_history := plugin.get_undo_redo().get_history_undo_redo(history_id)
		scene_history.undo()
		check(guard.get("enemy_definition").resource_path.ends_with("guard_default.tres"), "场景绑定支持编辑器撤销")
		scene_history.redo()
		check(guard.get("enemy_definition").resource_path == panel.file_path, "场景绑定支持编辑器重做")
		var old_path: NodePath = guard.get("patrol_route")
		guard.set("patrol_route", NodePath())
		plugin._create_route()
		var route := guard.get_node_or_null(guard.get("patrol_route"))
		check(route != null and route.name == "PatrolRoute2" and route.get_child_count() == 2, "创建巡逻路点避免覆盖同名对象")
		scene_history.undo()
		check(not guard.has_node("PatrolRoute2"), "巡逻路点创建可撤销")
		guard.set("patrol_route", old_path)
		guard.set("patrol_route", NodePath("MissingRoute"))
		check(not plugin._scene_binding_errors().is_empty(), "校验缺失三维对象引用")
		guard.set("patrol_route", old_path)
		var packed := PackedScene.new()
		var pack_error := packed.pack(scene_root)
		var scene_path := "user://enemy_canvas_scene_roundtrip.tscn"
		var save_error := ResourceSaver.save(packed, scene_path)
		var reloaded := (ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		check(pack_error == OK and save_error == OK and reloaded.get_node("Guard").get("enemy_definition").resource_path == panel.file_path, "场景保存重载保持蓝图绑定")
		check(reloaded.get_node("Guard/PatrolRoute").get_child_count() == 4 and reloaded.get_node("Guard").get("enemy_instance_id") == guard.get("enemy_instance_id"), "场景重载保持巡逻对象及稳定实例 ID")
		reloaded.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(scene_path))
		var copy := guard.duplicate()
		scene_root.add_child(copy, true)
		copy.owner = scene_root
		plugin._assign_ids()
		check(copy.get("enemy_instance_id") != guard.get("enemy_instance_id"), "复制三维守卫自动分配新实例标识")
		scene_root.remove_child(copy)
		copy.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tools/enemy_editor/.canvas_roundtrip.tres"))
	await panel.get_tree().process_frame
	print("ENEMY CANVAS: %d passed / %d failed" % [passed, failed])
	panel.get_tree().quit(1 if failed else 0)
