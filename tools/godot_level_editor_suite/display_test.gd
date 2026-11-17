@tool
extends RefCounted
const ADAPTER := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/display_adapter.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(90, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.5, true).timeout
	suite.show_window()
	var window: Window = suite.window
	var adapter: Node = suite.display_adapter
	print("DISPLAY editor_scale=", EditorInterface.get_editor_scale(), " auto=", adapter.scale_factor, " physical=",window.size, " screen=",window.current_screen)
	if DisplayServer.get_name() != "headless": print("SCREEN size=", DisplayServer.screen_get_size(window.current_screen), " usable=",DisplayServer.screen_get_usable_rect(window.current_screen), " scale=",DisplayServer.screen_get_scale(window.current_screen), " dpi=",DisplayServer.screen_get_dpi(window.current_screen))
	check(ADAPTER.choose_scale(2, 2, 220, false, "macOS") == 2, "Retina uses 2x once instead of doubling twice")
	check(ADAPTER.choose_scale(2, 1, 96, false, "macOS") == 1, "moving from Retina to a normal display restores 1x")
	check(ADAPTER.choose_scale(1, 1.5, 144, false, "Windows") == 1.5, "OS fractional display scale is respected")
	check(ADAPTER.choose_scale(1.25, 2, 220, true, "macOS") == 1.25, "explicit native editor scale remains authoritative")
	var actual: float = adapter.scale_factor
	# Isolate simulated display matrices from real OS DPI/focus callbacks.
	adapter.set_process(false)
	window.dpi_changed.disconnect(adapter.refresh)
	window.focus_entered.disconnect(adapter.refresh)
	var output := "res://docs/godot_level_editor_suite/display_refresh_2026-11-16"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): output = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	for scale in [1.0, 1.5, 2.0]:
		adapter.apply_scale(scale)
		window.size = Vector2i(Vector2(1320, 860) * scale)
		await frames(tree)
		check(is_equal_approx(window.get_final_transform().get_scale().x, scale), "logical UI scales uniformly: " + str(scale))
	adapter.apply_scale(actual)
	adapter.restore_geometry(Rect2i(Vector2i.ZERO, Vector2i.ZERO), false)
	window.dpi_changed.connect(adapter.refresh)
	window.focus_entered.connect(adapter.refresh)
	adapter.set_process(true)
	await frames(tree)
	var popup := ConfirmationDialog.new(); window.add_child(popup); await frames(tree)
	check(is_equal_approx(popup.content_scale_factor, actual), "new confirmation dialogs inherit the display scale")
	popup.queue_free()
	await preload("res://tools/godot_level_editor_suite/popup_frame_checks.gd").run(suite, check, output)
	var font: FontFile = window.theme.default_font
	check(font.multichannel_signed_distance_field and window.theme.get_font("title_font", "GraphNode").get("multichannel_signed_distance_field"), "graph title and body use scalable MSDF glyphs")
	check(window.theme.default_font_size == 16, "readable logical base font is 16")
	check(font.get_font_name() in suite.STYLE.SONGTI.FAMILIES and font.get_font_weight() == 400 and suite.STYLE.SONGTI.make(700).get_font_weight() == 700, "Songti resolves real regular and bold faces")
	var missing := ""
	for character in "关卡任务机关敌人对白宋体龘→↔↵⇄−⌄✓":
		if not font.has_char(character.unicode_at(0)): missing += character
	check(missing.is_empty(), "Chinese and UI symbols have real glyphs: " + missing)
	var speaker_colors := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/identity_colors.gd")
	check(speaker_colors.ink("level:1") != speaker_colors.ink("level:2") and speaker_colors.ink("level:1") != speaker_colors.ink("level:6") and speaker_colors.ink("npc:接待员") == speaker_colors.ink("npc:接待员"), "identity colors are stable and separate the current level categories")
	var icon_ok := true
	for button in suite.navigation_buttons.values(): icon_ok = icon_ok and button.icon != null and button.vertical_icon_alignment == VERTICAL_ALIGNMENT_TOP
	check(icon_ok, "all primary sections have a monochrome icon above the label")
	await load("res://tools/narrative/dialogue_layout_checks.gd").run(suite.modules.narrative.dialogue_panel, check)
	suite.open_tab("关卡"); suite.level_panel.set_mode(0)
	await tree.create_timer(0.5, true).timeout
	var warehouse: Control = suite.level_panel
	warehouse.select_level(str(warehouse.catalog.levels[0].level_id))
	warehouse._catalog_scroll.scroll_vertical = 0
	await frames(tree)
	check(warehouse.catalog_grid.columns >= 1 and warehouse._detail_side.size.x >= warehouse._detail_side.custom_minimum_size.x and warehouse.detail.size.x >= 230, "catalog retains its configured responsive detail width")
	var first: Control = warehouse.catalog_grid.get_child(0)
	check(first.scale == Vector2.ONE and first.cover.texture != null, "cards retain stable hit areas and a real or placeholder preview")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		window.get_texture().get_image().save_png(output + "/关卡目录.png")
	suite.open_tab("台本")
	await tree.create_timer(0.4, true).timeout
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		window.get_texture().get_image().save_png(output + "/台本.png")
	suite.open_tab("事件与任务")
	await tree.create_timer(0.35, true).timeout
	var event_panel: Control = suite.event_panel
	var event_row: TreeItem = event_panel.table.get_root().get_first_child()
	var colored := false
	while event_row != null:
		var child := event_row.get_first_child()
		while child != null:
			if not child.get_text(3).is_empty() and child.get_text(3) == event_row.get_text(3) and event_row.has_meta("identity_frame_3"):
				colored = colored or child.get_meta("identity_frame_3", "") == event_row.get_meta("identity_frame_3") and child.get_custom_draw_callback(3).is_valid() and event_row.get_custom_draw_callback(3).is_valid()
			child = child.get_next()
		event_row = event_row.get_next()
	check(colored, "event and task rows use the same outline key for their shared level")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		window.get_texture().get_image().save_png(output + "/所属关卡配色.png")
	suite.open_tab("任务图")
	var panel: Control = suite.task_graph
	var original: Resource = panel.graph
	var was_dirty: bool = panel.dirty
	var graph := GRAPH.new(); graph.graph_id = "display_qa"
	graph.nodes = [{"id": "start", "kind": "start", "params": {}}, {"id": "goal", "kind": "objective", "params": {"text": "开启大门"}}, {"id": "interact", "kind": "object_interacted", "params": {"object": "", "once": false}}]
	graph.positions = {"start": Vector2(60, 130), "goal": Vector2(420, 130), "interact": Vector2(60, 350)}
	graph.edges = [{"id": "edge", "from": "start", "from_port": "then", "to": "goal", "to_port": "run"}]
	panel.dirty = false; panel.open_graph(graph)
	var state := graph.snapshot()
	var ports := []
	for card in panel.canvas.get_children():
		if card is GraphNode: ports.append([card.name, card.get_input_port_count(), card.get_output_port_count(), card.get_child_count()])
	panel.canvas.zoom = 1.6
	await tree.create_timer(0.4, true).timeout
	var unchanged := true
	for row in ports:
		var card: GraphNode = panel.canvas.get_node(NodePath(row[0]))
		unchanged = unchanged and row.slice(1) == [card.get_input_port_count(), card.get_output_port_count(), card.get_child_count()]
	check(unchanged and graph.nodes == state.nodes and graph.edges == state.edges and graph.positions == state.positions, "DPI and graph zoom preserve ports, links and node positions")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		window.get_texture().get_image().save_png(output + "/节点放大.png")
	panel.dirty = false; panel.open_graph(original); panel.dirty = was_dirty
	# Motion must settle after rapid section changes and preserve input bounds.
	var bounds: Rect2 = suite.navigation_buttons["任务"].get_rect()
	for section in ["关卡", "任务图", "台本", "任务图"]: suite.open_tab(section)
	await tree.create_timer(0.45, true).timeout
	check(suite.navigation_buttons["任务"].get_rect() == bounds and suite.navigation_buttons["任务"].scale == Vector2.ONE and suite.navigation_buttons["任务"].button_pressed, "rapid navigation animations settle without changing hit targets")
	print("DISPLAY REFRESH: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
