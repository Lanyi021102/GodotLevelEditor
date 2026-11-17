@tool
extends RefCounted
var checks := 0
var failures := 0
var tree: SceneTree
var output := ""
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", text)
func frames(count := 3) -> void:
	for i in count: await tree.process_frame
func capture(suite: EditorPlugin, name: String) -> void:
	if output.is_empty(): return
	await frames(4); RenderingServer.force_draw(false)
	suite.window.get_texture().get_image().save_png(output.path_join(name + ".png"))
func run(suite: EditorPlugin) -> void:
	tree = suite.get_tree(); tree.create_timer(100).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(4).timeout
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sky-ui-capture="): output = arg.trim_prefix("--sky-ui-capture=")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/ui_motion.gd").enabled = false
	suite.display_adapter.set_user_scale(1.0)
	suite.window.size = Vector2i(1400, 950)
	suite.open_tab("天空")
	var panel: Control = suite.sky_panel
	panel.dirty = false; panel.open_preset("res://addons/godot_level_editor/resources/sky_presets/builtin/sunset.tres")
	check(panel.category_tabs.get_tab_count() == 5, "five parameter categories")
	panel.set_category("时间与太阳")
	check(panel.category_buttons["时间与太阳"].button_pressed, "selected category is visible in navigation")
	check(panel.fields.hour.clock.text == "17:00" and panel.fields.hour.editable, "time uses editable HH:MM")
	check(not panel.field_rows.elevation.visible and not panel.field_rows.azimuth.visible, "time mode hides inactive manual angle values")
	check(panel.solar.text.contains("16.8") and panel.solar.text.contains("255.0"), "read-only solar result matches computed angles")
	check(panel.fields.sun_energy.spin.size.x < 180 and panel.fields.sun_color.picker.custom_minimum_size.x <= 64, "numbers and color swatches use compact inputs")
	await capture(suite, "sun_time")
	var before: Vector2 = panel.draft.solar_angles()
	panel.change("sun_mode", 0)
	check(panel.draft.solar_angles().is_equal_approx(before), "switch to manual preserves current solar position")
	check(panel.field_rows.elevation.visible and not panel.field_rows.hour.visible and panel.fields.elevation.editable, "manual mode exposes editable angles and hides clock")
	panel.undo.undo()
	check(panel.draft.sun_mode == 1 and not panel.field_rows.elevation.visible, "mode and transferred angles undo together")
	panel.fields.hour.clock.text = "07:30"; panel.fields.hour.commit_text()
	check(is_equal_approx(panel.draft.hour, 7.5), "clock text changes stored hour")
	panel.undo.undo(); check(is_equal_approx(panel.draft.hour, 17.0), "clock edit supports undo")
	panel.fields.hour.clock.text = "25:90"; panel.fields.hour.commit_text()
	check(panel.fields.hour.clock.text == "17:00" and panel.draft.hour == 17.0 and panel.status.text.contains("HH:MM"), "invalid time restores previous value with feedback")
	panel.fields.hour.slider.value = 18.25
	check(is_equal_approx(panel.draft.hour, 18.25) and panel.fields.hour.clock.text == "18:15", "time slider and input stay synchronized")
	panel.change("sun_mode", 0)
	await capture(suite, "sun_manual")
	panel.fields.sun_color.code.text = "#33AA88"; panel.fields.sun_color.commit_text()
	check(panel.draft.sun_color.is_equal_approx(Color("33AA88")), "hex color is directly editable")
	panel.undo.undo(); check(panel.fields.sun_color.code.text == "#FFA659", "hex input follows color undo")
	var color: Color = panel.draft.sun_color
	panel.fields.sun_color.code.text = "#WRONG!"; panel.fields.sun_color.commit_text()
	check(panel.draft.sun_color == color and panel.status.text.contains("六位"), "invalid hex does not mutate color")
	panel.set_category("云层")
	check(is_equal_approx(panel.fields.cloud_height.spin.value, panel.draft.cloud_height) and is_equal_approx(panel.fields.cloud_scale.spin.value, panel.draft.cloud_scale), "coarse arrow increments do not shift stored cloud dimensions")
	panel.fields.cloud_coverage.spin.value = 65
	check(is_equal_approx(panel.draft.cloud_coverage, 0.65), "cloud percentage preserves normalized stored value")
	panel.change("clouds_enabled", false)
	check(not panel.field_rows.cloud_height.visible and not panel.field_rows.cloud_color.visible, "cloud toggle hides inactive parameters")
	panel.undo.undo(); check(panel.field_rows.cloud_height.visible, "cloud controls return after undo")
	await capture(suite, "clouds")
	panel.set_category("雾"); panel.change("fog_enabled", true)
	panel.fields.fog_density.spin.value = 42
	check(is_equal_approx(panel.draft.fog_density, 0.42), "fog percentage edits existing data format")
	panel.change("fog_end", panel.draft.fog_begin)
	check(panel._fog_hint.visible, "invalid fog interval gets local feedback")
	panel.undo.undo()
	await capture(suite, "fog")
	panel.set_category("环境光")
	check(is_equal_approx(panel.fields.exposure.spin.value, panel.draft.exposure), "exposure input displays the stored value without step rounding")
	await capture(suite, "ambient")
	panel.change("sky_mode", 1)
	check(not panel.field_rows.ambient_color.visible and panel._ambient_hint.visible, "HDRI source explains why fill color is unavailable")
	panel.change("hdri_lighting", false)
	check(panel.field_rows.ambient_color.visible, "color fill remains editable when selected")
	panel.set_category("天空背景")
	check(not panel._sections.program.get_parent().get_parent().visible and panel._sections.hdri.get_parent().get_parent().visible, "background mode shows only applicable settings")
	await capture(suite, "hdri")
	panel.set_category("云层")
	check(panel._sections.clouds_unavailable.get_parent().get_parent().visible, "HDRI cloud page explains its source")
	panel.set_category("环境光"); panel.dirty = false; panel.open_preset(panel.LIBRARY.DEFAULT)
	check(panel.category_tabs.get_tab_title(panel.category_tabs.current_tab) == "环境光", "preset switch preserves chosen category")
	panel.set_category("天空背景")
	await capture(suite, "template")
	panel.dirty = false; panel.open_preset("res://addons/godot_level_editor/resources/sky_presets/builtin/clear.tres")
	await capture(suite, "background")
	for key in ["天空背景", "时间与太阳", "环境光", "云层", "雾"]:
		panel.set_category(key); await frames()
		check(panel.size.x <= suite.window.size.x and panel.form.get_global_rect().end.x <= suite.window.size.x, key + " fits standard window")
	suite.window.size = Vector2i(1040, 700); await frames(5)
	panel.set_category("时间与太阳")
	await capture(suite, "narrow")
	check(suite.window.size == Vector2i(1040, 700) and panel.form.get_global_rect().end.x <= 1040, "minimum window keeps footer and fields within bounds")
	panel.dirty = false; panel.discard()
	print("SKY_UI_RESULT checks=", checks, " failures=", failures)
	tree.quit(1 if failures else 0)
