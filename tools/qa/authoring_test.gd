@tool
extends RefCounted
## Invoked by run_structure_flow.py in a disposable project.
var checks := 0
var failures := 0
var output := ""
var visual := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)

func frames(tree: SceneTree, count := 8) -> void:
	for i in count: await tree.process_frame

func capture(window: Window, name: String) -> void:
	if visual:
		RenderingServer.force_draw(false)
		window.get_texture().get_image().save_png(output.path_join(name + ".png"))

func button(parent: Control, title: String) -> Button:
	for child in parent.find_children("*", "Button", true, false):
		if child.text == title: return child
	return null

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(90, true).timeout.connect(func(): tree.quit(2))
	visual = DisplayServer.get_name() != "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="): output = arg.trim_prefix("--qa-output=")
	await tree.create_timer(1, true).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await tree.process_frame
	suite.show_window()
	await frames(tree)
	check(suite._prepared_pages.size() == 1 and button(suite.home_panel, "新建关卡") != null, "Workbench creation is available before other pages initialize")
	button(suite.home_panel, "新建关卡").pressed.emit()
	await frames(tree, 15)
	var root := EditorInterface.get_edited_scene_root()
	check(root != null and root.scene_file_path.is_empty() and not suite.window.visible, "Create opens an unsaved inherited map in the native editor")
	if root == null: tree.quit(1); return
	var path := "res://content/scenes/levels/authoring_check.tscn"
	EditorInterface.save_scene_as(path, false)
	await frames(tree, 25)
	suite.open_tab("工作台")
	await frames(tree)
	check(suite.recent_level() == path and not suite.home_panel.resume_button.disabled, "A native save records the last map")
	capture(suite.window, "workbench")
	suite.home_panel.resume_button.pressed.emit()
	await frames(tree)
	check(not suite.window.visible and EditorInterface.get_edited_scene_root().scene_file_path == path, "Continue returns to the saved native scene")
	suite.open_tab("关卡")
	var panel: Control = suite.level_panel
	panel.set_mode(0)
	var browser: Control = panel.browser
	browser.search.text = "no_such_level_239"; browser._filter()
	check(browser.selected_path.is_empty() and browser.open_button.disabled and browser.logic_button.disabled and browser.locate_button.disabled, "Zero results clear the level selection and disable every detail action")
	browser.search.text = "authoring_check"; browser._filter()
	check(browser.selected_path == path, "Filtering selects the first visible map")
	browser.logic_button.pressed.emit()
	await frames(tree)
	check(suite.window.visible and panel.mode_stack.current_tab == 1 and panel.logic_panel.world == root, "Edit persistent logic stays in the workspace with the selected map")
	panel.set_mode(0)
	browser.open_button.pressed.emit()
	await frames(tree)
	check(not suite.window.visible, "Open scene returns focus to the native viewport")
	for section in ["机关", "敌人"]:
		suite.open_tab(section)
		var library: Control = suite.asset_panels[section]
		library.set_mode(0)
		library.source_filter.select(2); library._filter()
		check(library.cards.has(library.selected_path) and library.selected_path.begins_with("res://addons/"), section + " has a selectable built-in asset")
		library.search.text = "no_such_asset_239"; library._filter()
		check(library.selected_path.is_empty() and library.enter_button.disabled and library.detail_cover.texture == null, section + " clears hidden selection and preview")
		check(button(library, "新建" + library.kind).is_visible_in_tree(), section + " creation remains visible with zero results")
		library.search.clear(); library.source_filter.select(1); library._filter()
		check(library.selected_path.is_empty() or library.selected_path.begins_with("res://content/"), section + " personal filter excludes built-ins")
	suite.open_tab("事件与任务")
	var events: Control = suite.event_panel
	events.add_event()
	await frames(tree)
	var row: TreeItem = events.table.get_selected()
	check(row != null and row.get_text(5) == "添加任务", "A new event exposes its Add Task action")
	if row != null:
		events.table.ensure_cursor_is_visible()
		await frames(tree)
		var action_rect: Rect2 = events.table.get_item_area_rect(row, 5)
		var point: Vector2 = events.table.get_global_transform_with_canvas() * action_rect.get_center()
		var viewport: Viewport = events.table.get_viewport()
		for down in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = down
			click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			click.position = point
			click.global_position = point
			viewport.push_input(click, true)
			await tree.process_frame
		check(events.form.visible and events._form_event_id == str(row.get_metadata(0)), "Row action opens a task bound to the clicked event")
		events.form.hide()
	events.undo.undo()
	suite.open_tab("天空")
	await frames(tree, 25)
	if visual:
		var sky: Control = suite.sky_panel
		var hashes := {}
		for i in sky.items.item_count:
			var icon: Texture2D = sky.items.get_item_icon(i)
			check(icon != null and icon.get_width() == 192, "Rendered preview for " + sky.items.get_item_text(i))
			if icon != null: hashes[hash(icon.get_image().get_data())] = true
		check(hashes.size() > 2, "Different skies produce distinct views of the whitebox")
		capture(suite.window, "sky-library")
	print("AUTHORING FLOW: ", checks, " checks, ", failures, " failures")
	tree.quit(1 if failures else 0)
