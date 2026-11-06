@tool
extends RefCounted
func run(panel: Control, plugin: EditorPlugin) -> void:
	for _i in 20: await panel.get_tree().process_frame
	var flags := {"suspicious": false, "alert": false, "rewound": false, "highlight": false}
	var listener := func(_key: String, packet: Dictionary):
		if packet.get("state_id", "") == "suspicious": flags.suspicious = true
		if packet.get("state_id", "") == "alert": flags.alert = true
		if packet.get("rewound", false): flags.rewound = true
		var node: GraphNode = panel.graph.get_node("s_" + str(packet.state_id))
		if node.get_meta("runtime_active", false) and node.self_modulate == Color.WHITE and node.get_theme_stylebox("titlebar").bg_color == Color("24756e"): flags.highlight = true
	plugin.debugger.state_received.connect(listener)
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--remote-debug", "tcp://127.0.0.1:6017", "--ignore-error-breaks", "--log-file", "/tmp/branch_enemy_debug_child.log", "res://tools/enemy_editor/debug_probe.tscn"]))
	var deadline := Time.get_ticks_msec() + 10000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await panel.get_tree().create_timer(0.1).timeout
	for _i in 5: await panel.get_tree().process_frame
	var failed := 0
	for key in flags:
		print("[PASS] " if flags[key] else "[FAIL] ", "实际调试通道：", key)
		if not flags[key]: failed += 1
	var cleaned: bool = panel.runtime.is_empty()
	print("[PASS] " if cleaned else "[FAIL] ", "真实游戏退出后清除高亮")
	if not cleaned: failed += 1
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
		failed += 1
	plugin.debugger.state_received.disconnect(listener)
	print("ENEMY DEBUGGER: %d passed / %d failed" % [5 - mini(failed, 5), failed])
	panel.get_tree().quit(1 if failed else 0)
