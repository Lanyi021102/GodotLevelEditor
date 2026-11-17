@tool
extends RefCounted
const MOTION := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/ui_motion.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func wait(tree: SceneTree, seconds: float) -> void:
	await tree.create_timer(seconds, true).timeout
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(90, true).timeout.connect(func(): tree.quit(2))
	await wait(tree, 1.0)
	suite.show_window()
	var settings := EditorInterface.get_editor_settings()
	var old_scale: float = settings.get_project_metadata("godot_level_editor_suite", "ui_scale", 0.0)
	var old_motion: bool = settings.get_project_metadata("godot_level_editor_suite", "animations_enabled", true)
	var graph_hash: String = suite.task_graph.graph.semantic_hash()
	suite.home_panel._animations_changed(true)
	var first: Button = suite.navigation_buttons.values()[0]
	check(first.text == "工作台" and first.has_meta("navigation_icon_motion"), "branded workbench is the first navigation item")
	var output := "res://docs/godot_level_editor_suite/navigation_motion_2026-11-16"
	DirAccess.make_dir_recursive_absolute(output)
	for key in suite.navigation_buttons:
		var button: Button = suite.navigation_buttons[key]
		var icon: TextureRect = button.get_meta("navigation_icon_motion")
		suite.open_tab("工作台" if key != "工作台" else "关卡")
		await wait(tree, 0.5)
		var bounds := button.get_rect()
		var label := button.text
		suite.open_tab("任务图" if key == "任务" else key)
		await wait(tree, 0.11)
		var changed: bool = not icon.scale.is_equal_approx(Vector2.ONE) or not is_zero_approx(icon.rotation) or not icon.position.is_equal_approx(icon._origin)
		check(changed and button.get_rect() == bounds and button.scale == Vector2.ONE and button.text == label, "selection animates only the glyph: " + str(key))
		await wait(tree, 0.48)
		check(icon.scale == Vector2.ONE and is_zero_approx(icon.rotation) and icon.position == icon._origin and icon.self_modulate == Color.WHITE, "selection settles with the selected monochrome color: " + str(key))
		button.pressed.emit()
		await wait(tree, 0.10)
		check(icon._tween != null and icon._tween.is_running(), "clicking the already selected item replays its logo: " + str(key))
		suite.open_tab("关卡" if key == "工作台" else "工作台")
		await wait(tree, 0.08)
		check(icon._tween != null and icon._tween.is_running() and icon.self_modulate != Color.WHITE, "switching away plays the exit gesture: " + str(key))
		await wait(tree, 0.35)
		check(icon.scale == Vector2.ONE and is_zero_approx(icon.rotation) and icon.position == icon._origin, "exit returns to the exact resting pose: " + str(key))
	for key in ["机关", "天空", "任务图", "台本", "工作台", "关卡"]: suite.open_tab(key)
	await wait(tree, 0.6)
	var settled := true
	for button in suite.navigation_buttons.values():
		var icon: TextureRect = button.get_meta("navigation_icon_motion")
		settled = settled and icon.scale == Vector2.ONE and is_zero_approx(icon.rotation) and icon.position == icon._origin
	check(settled and suite.navigation_buttons["关卡"].button_pressed, "rapid switches cancel previous logo tweens and settle consistently")
	suite.home_panel._animations_changed(false)
	suite.open_tab("机关")
	await wait(tree, 0.08)
	var gear: TextureRect = suite.navigation_buttons["机关"].get_meta("navigation_icon_motion")
	check(gear._tween == null and gear.scale == Vector2.ONE and is_zero_approx(gear.rotation), "animation preference stops logo motion immediately")
	suite.home_panel._animations_changed(true)
	suite.navigation_buttons["机关"].pressed.emit()
	await wait(tree, 0.1)
	check(gear._tween != null and gear._tween.is_running(), "animation preference can be re-enabled")
	suite.window.hide(); await wait(tree, 0.05)
	check(gear.scale == Vector2.ONE and is_zero_approx(gear.rotation) and gear._tween == null, "hiding the workspace cancels in-flight icon motion")
	suite.show_window(); suite.open_tab("工作台"); await wait(tree, 0.5)
	var home: Control = suite.home_panel
	home.scale_picker.select(2); home.scale_picker.item_selected.emit(2)
	check(is_equal_approx(suite.display_adapter.scale_factor, 1.25) and is_equal_approx(float(settings.get_project_metadata("godot_level_editor_suite", "ui_scale")), 1.25), "workbench scale preference applies and persists locally")
	settings.set_project_metadata("godot_level_editor_suite", "ui_scale", old_scale)
	suite.display_adapter.refresh(); home._refresh()
	check(home.scale_status.text.contains(str(roundi(suite.display_adapter.scale_factor * 100))), "workbench reports the active scale")
	check(FileAccess.file_exists("res://打开Wiki.command") and FileAccess.file_exists("res://docs/index.md") and home.WIKI.begins_with("https://"), "Wiki entries have existing local targets and an HTTPS destination")
	check(suite.task_graph.graph.semantic_hash() == graph_hash, "preferences and navigation animations preserve graph data")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		suite.window.get_texture().get_image().save_png(output + "/工作台.png")
		# A compact strip of real rendered icon gestures for visual review.
		var background := ColorRect.new(); background.color = Color.WHITE; background.position = Vector2(20,20); background.size = Vector2(suite.window.size.x, 100); background.mouse_filter = Control.MOUSE_FILTER_IGNORE; suite.window.add_child(background)
		var strip := HBoxContainer.new(); strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); strip.position = Vector2(20, 20); strip.mouse_filter = Control.MOUSE_FILTER_IGNORE; suite.window.add_child(strip)
		var samples := []
		for button in suite.navigation_buttons.values():
			var sample := Button.new(); sample.text = button.text; suite.STYLE.navigation(sample); sample.icon = button.icon; sample.expand_icon = true; sample.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; sample.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP; sample.add_theme_constant_override("icon_max_width", 26); strip.add_child(sample)
			preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/navigation_icon.gd").install(sample, button.get_meta("navigation_icon_motion").kind)
			suite.STYLE.select_navigation(sample, true); samples.append(sample)
		await wait(tree, 0.5)
		for frame in 16:
			if frame == 0:
				for sample in samples: sample.get_meta("navigation_icon_motion").play(true)
			await wait(tree, 0.04)
			await RenderingServer.frame_post_draw
			var factor: float = suite.window.content_scale_factor
			var final_sample: Button = samples.back()
			var region := Rect2i(Vector2i(Vector2(20,20) * factor), Vector2i((final_sample.position.x + final_sample.size.x) * factor, 90 * factor))
			suite.window.get_texture().get_image().get_region(region).save_png(output + "/frame_%02d.png" % frame)
		strip.queue_free()
		background.queue_free()
	suite.home_panel._animations_changed(old_motion)
	print("NAVIGATION ICONS: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
