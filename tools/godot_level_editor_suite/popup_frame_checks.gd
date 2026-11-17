@tool
extends RefCounted
## Exercise the real inherited surfaces, including engine-created popup controls.
static func run(suite: EditorPlugin, check: Callable, output: String) -> void:
	var window: Window = suite.window
	var tree := suite.get_tree()
	print("POPUP compositor_alpha=", DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_TRANSPARENCY))
	check.call(window.theme.get_stylebox("panel", "TooltipPanel").corner_radius_top_left == 0, "tooltip outer surface paints all corners without relying on compositor alpha")
	var host := Control.new()
	window.add_child(host)
	var option := OptionButton.new()
	option.add_item("下拉选项")
	host.add_child(option)
	var picker := ColorPickerButton.new()
	host.add_child(picker)
	var context := PopupMenu.new()
	context.add_item("右键操作")
	host.add_child(context)
	var tooltip := PopupPanel.new()
	tooltip.theme_type_variation = "TooltipPanel"
	tooltip.unfocusable = true
	tooltip.popup_window = false
	tooltip.mouse_passthrough = true
	var label := Label.new()
	label.theme_type_variation = "TooltipLabel"
	label.text = "提示框圆角检查\n正文保持宋体和原有颜色。"
	tooltip.add_child(label)
	host.add_child(tooltip)
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "确认弹窗边角检查"
	host.add_child(dialog)
	var files := EditorFileDialog.new()
	files.use_native_dialog = false
	files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	host.add_child(files)
	var popups: Array[Window] = [tooltip, context, option.get_popup(), picker.get_popup(), dialog, files]
	for i in popups.size():
		var popup := popups[i]
		var title: String = ["提示框", "右键菜单", "下拉菜单", "颜色选择器", "确认弹窗", "文件选择器"][i]
		check.call(is_equal_approx(popup.content_scale_factor, suite.display_adapter.scale_factor), title + " receives centralized display handling before opening")
		if popup is Popup:
			check.call(not popup.transparent and not popup.transparent_bg, title + " uses a consistent opaque native and viewport surface")
		window.grab_focus()
		await tree.create_timer(0.15).timeout
		popup.popup_centered(Vector2i(440, 180) if i == 0 else Vector2i.ZERO)
		await tree.create_timer(0.2).timeout
		if DisplayServer.get_name() != "headless":
			check.call(popup.visible, title + " opens as a rendered window")
			if not popup.visible: continue
			await RenderingServer.frame_post_draw
			var image := popup.get_texture().get_image()
			check.call(image != null, title + " has a readable rendered surface")
			if image == null:
				popup.hide()
				continue
			var clean := true
			for point in [Vector2i(0, 0), Vector2i(image.get_width() - 1, 0), Vector2i(0, image.get_height() - 1), Vector2i(image.get_width() - 1, image.get_height() - 1)]:
				var color := image.get_pixelv(point)
				clean = clean and color.a > 0.99 and color.get_luminance() > 0.65
			check.call(clean, title + " has fully painted light corners, with no black pixels")
			if OS.get_cmdline_user_args().has("--capture"): image.save_png(output + "/" + title + ".png")
		popup.hide()
		await tree.create_timer(0.15).timeout
	# Also exercise Godot's dynamically generated tooltip, rather than only a
	# manually constructed PopupPanel with the same theme variation.
	var probe := Button.new()
	probe.text = "悬停提示检查"
	probe.tooltip_text = "系统自动创建的提示框\n检查四角背景和文字。"
	probe.position = Vector2(320, 200)
	probe.size = Vector2(240, 50)
	window.add_child(probe)
	for frame in 3: await tree.process_frame
	window.grab_focus()
	await tree.create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless": probe.warp_mouse(probe.size / 2.0)
	window.notify_mouse_entered()
	var motion := InputEventMouseMotion.new()
	motion.position = probe.get_global_rect().get_center()
	window.push_input(motion, true)
	await tree.create_timer(1.2).timeout
	var generated: Window
	for candidate in probe.find_children("*", "Window", true, false):
		if candidate.visible and candidate.theme_type_variation == "TooltipPanel": generated = candidate
	check.call(generated != null, "Godot creates the real hover tooltip under the watched workspace")
	if generated != null:
		check.call(not generated.transparent and not generated.transparent_bg, "engine-generated tooltips are configured synchronously before opening")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var actual_image := generated.get_texture().get_image()
			var corner := actual_image.get_pixel(0, 0)
			check.call(corner.a > 0.99 and corner.get_luminance() > 0.65, "real hover tooltip paints its corner rather than leaving transparent black")
			if OS.get_cmdline_user_args().has("--capture"): actual_image.save_png(output + "/自动提示框.png")
	probe.queue_free()
	host.queue_free()
	var table: Tree = suite.modules.narrative.dialogue_panel.table
	var item := table.get_root().get_first_child()
	var colors := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/identity_colors.gd")
	check.call(item != null and item.has_meta("identity_frame_1") and item.get_cell_mode(1) == TreeItem.CELL_MODE_CUSTOM and item.get_custom_draw_callback(1).is_valid(), "NPC names use filled tags while retaining native text rendering")
	check.call(item != null and item.get_custom_color(1) == colors.text_color(colors.ink(item.get_meta("identity_frame_1"))) and item.get_custom_bg_color(1) == Color.BLACK, "NPC text adapts to its tag fill without painting the entire column")
	check.call(item != null and not item.get_text(1).is_empty(), "changing cell rendering preserves the NPC name")
	check.call(colors.text_color(Color("142641")) == Color.WHITE and colors.text_color(Color("e0e7ff")) == colors.DARK_TEXT, "dark fills use white text and light fills use dark text")
	var readable := true
	for fill in colors.PALETTE:
		var a: float = colors.luminance(fill)
		var b: float = colors.luminance(colors.text_color(fill))
		readable = readable and (maxf(a, b) + 0.05) / (minf(a, b) + 0.05) >= 4.5
	check.call(readable, "every identity fill and text pair has at least 4.5 contrast")
