@tool
extends RefCounted
## Render actual editor graphs and attach to an actual separately running demo.
static func run(editor: EditorPlugin) -> bool:
	var tree := editor.get_tree()
	var panel: Control = editor.panel
	# Running from the editor may auto-save touched resources. Keep this visual
	# verification from rewriting any authored scene/graph files.
	var disk_sources := {}
	_snapshot_sources("res://scenes/level_editor", disk_sources)
	_snapshot_sources("res://resources/level_editor", disk_sources)
	EditorInterface.set_main_screen_editor("关卡与世界")
	panel.show()
	editor.hide_bottom_panel()
	var before: Dictionary = panel.graph.snapshot()
	await panel.arrange_all()
	panel.dirty = false
	panel.canvas.zoom = 0.7
	panel.canvas.scroll_offset = Vector2(-25, 160)
	panel.status.text = "分类色表示职责；端口和连线颜色表示连接类型。左侧输入 → 右侧输出。"
	await _capture(editor, "node_colors_editing.png")
	EditorInterface.play_custom_scene("res://scenes/levels/logic_playground.tscn")
	for _i in 80:
		if not panel._packets.is_empty(): break
		await tree.create_timer(0.1, true).timeout
	var connected: bool = not panel._packets.is_empty()
	EditorInterface.set_main_screen_editor("关卡与世界")
	panel.show()
	editor.hide_bottom_panel()
	panel.status.text = "实际试玩实例：执行次数、当前值与最近原因。绿色边框／绿点只表示活动，标题保留职责色。"
	await _capture(editor, "node_colors_running.png")
	print("[PASS] actual EngineDebugger demo packets reach styled graph" if connected else "[FAIL] actual EngineDebugger demo packets reach styled graph")
	EditorInterface.stop_playing_scene()
	await tree.create_timer(0.5, true).timeout
	panel.graph.apply_snapshot(before)
	panel.dirty = false
	EditorInterface.open_scene_from_path("res://scenes/levels/continuous_world.tscn")
	for _i in 10: await tree.process_frame
	panel.use_current_world()
	panel.mode.select(1)
	panel._switch_graph()
	before = panel.graph.snapshot()
	await panel.arrange_all()
	panel.canvas.zoom = 0.7
	panel.canvas.scroll_offset = Vector2(-25, -30)
	panel.status.text = "持续状态＝青绿；目标完成事件＝朱红；动作＝蓝色。节点 ID、资源、连线索引保持不变。"
	await _capture(editor, "node_colors_states.png")
	panel.graph.apply_snapshot(before)
	panel.dirty = false
	panel.mode.select(0)
	panel._switch_graph()
	panel.canvas.zoom = 0.85
	panel.canvas.scroll_offset = Vector2(-25, -30)
	panel.status.text = "紫色：空间接驳引用。左右方向标识表示编辑端口，空间连线仍是双向通路。"
	await _capture(editor, "node_colors_topology.png")
	for path in disk_sources:
		if FileAccess.get_file_as_bytes(path) != disk_sources[path]:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(disk_sources[path])
			file.close()
	return connected

static func _snapshot_sources(directory: String, result: Dictionary) -> void:
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() in ["tscn", "tres"]:
			var path := directory.path_join(file)
			result[path] = FileAccess.get_file_as_bytes(path)
	for child in DirAccess.get_directories_at(directory): _snapshot_sources(directory.path_join(child), result)

static func _capture(editor: EditorPlugin, filename: String) -> void:
	for _i in 8: await editor.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	# Save outside res:// so import scanning cannot obscure the next capture.
	var error := screenshot.save_png("/tmp/godot_level_editor_" + filename)
	print("PRESENTATION CAPTURE: ", filename, " ", error_string(error))
