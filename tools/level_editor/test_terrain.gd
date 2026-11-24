@tool
extends RefCounted

const MODULE := "res://addons/godot_level_editor/modules/godot_level_editor/terrain/"
const VIEW := preload(MODULE + "editor_view.gd")
const LAYOUT := preload(MODULE + "layout.gd")
const SURFACE := preload(MODULE + "surface.gd")
const TERRAIN := preload(MODULE + "terrain.gd")
const TEMPLATE := "res://addons/godot_level_editor/templates/empty_level.tscn"
const PATH := "res://content/scenes/levels/terrain_probe.tscn"
var checks := 0
var failures := 0
var editor: EditorPlugin
var camera: Camera3D

func check(condition: bool, caption: String) -> void:
	checks += 1
	if not condition: failures += 1
	print("[PASS] " if condition else "[FAIL] ", caption)

func _click(at: Vector2, double_click := false) -> void:
	_button(at, true, double_click)
	_button(at, false)

func _button(at: Vector2, pressed: bool, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double_click
	editor._forward_3d_gui_input(camera, event)

func _motion(at: Vector2, pressed := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	if pressed: event.button_mask = MOUSE_BUTTON_MASK_LEFT
	editor._forward_3d_gui_input(camera, event)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	editor._forward_3d_gui_input(camera, event)

func _screen(at: Vector2) -> Vector2:
	return camera.unproject_position(Vector3(at.x, 0.0, at.y))

func run(plugin: EditorPlugin) -> void:
	editor = plugin
	var tree := editor.get_tree()
	tree.create_timer(75, true).timeout.connect(func(): tree.quit(2))
	while EditorInterface.get_resource_filesystem().is_scanning():
		await tree.create_timer(0.05, true).timeout
	await tree.create_timer(0.4, true).timeout
	EditorInterface.open_scene_from_path(TEMPLATE, true)
	await tree.create_timer(0.55, true).timeout
	EditorInterface.set_main_screen_editor("3D")
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.get_node_or_null("Whitebox/Floor") == null:
		check(false, "inherited blank scene opened")
		tree.quit(1)
		return
	var suite := tree.get_first_node_in_group("godot_level_editor_editor_suite")
	if suite != null and is_instance_valid(suite.window): suite.window.hide()
	camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var tool: RefCounted = editor.terrain_tool
	var original_pose := camera.global_transform
	editor.radial_tool.open_wheel(camera)
	var menu: Control = editor.radial_tool.menu
	menu.select_category(menu.categories.find("地形"))
	menu.confirm_selection()
	await tree.create_timer(0.65, true).timeout
	check(tool.active and tool.mode == tool.Mode.PEAK and root.get_node_or_null("Terrain") == null, "wheel enters drawing mode in an empty scene without adding anything")
	check(VIEW.is_top(camera) and tool.top_button.text == "透视", "terrain starts in the native top view")
	tool._toggle_view()
	await tree.create_timer(0.4, true).timeout
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE and camera.global_transform.origin.distance_to(original_pose.origin) < 1.0, "view toggle returns to the former perspective")
	tool._toggle_view()
	await tree.create_timer(0.45, true).timeout
	# Frame the test layout and then use viewport-space mouse positions.
	camera.global_position = Vector3(0, 78, 0)
	for _i in 6: await tree.process_frame
	var floor := root.get_node("Whitebox/Floor")
	_motion(_screen(Vector2(-17, -13)))
	await tree.create_timer(0.10, true).timeout
	check(is_instance_valid(tool.ghost) and root.get_node_or_null("Terrain") == null, "first hover previews an unowned, non-colliding terrain")
	_click(_screen(Vector2(-17, -13)))
	await tree.process_frame
	var terrain := root.get_node_or_null("Terrain")
	check(terrain != null and terrain.layout.features.size() == 1 and floor.is_covered_by_terrain(), "one click saves the first peak and covers the stock template floor")
	if terrain == null:
		tree.quit(1)
		return
	var undo := editor.get_undo_redo()
	var history := undo.get_history_undo_redo(undo.get_object_history_id(root))
	history.undo()
	await tree.process_frame
	check(root.get_node_or_null("Terrain") == null and not floor.is_covered_by_terrain(), "undo restores the stock floor")
	history.redo()
	await tree.process_frame
	check(floor.is_covered_by_terrain(), "redo covers the stock floor again")
	_motion(_screen(Vector2(17, -13)))
	await tree.create_timer(0.12, true).timeout
	check(terrain.layout.features.size() == 1 and terrain.surface.ridges.size() == 1, "second-peak preview shows a ridge without committing the second peak")
	_click(_screen(Vector2(17, -13)))
	tool.set_mode(tool.Mode.SELECT)
	var ridge: Dictionary = terrain.surface.ridges[0]
	var midpoint: Vector2 = (ridge.a + ridge.b) * 0.5
	var before_saddle: float = terrain.surface.height_at(midpoint)
	var saddle := camera.unproject_position(Vector3(midpoint.x, before_saddle, midpoint.y))
	_button(saddle, true)
	_motion(saddle + Vector2(0, 32), true)
	_button(saddle + Vector2(0, 32), false)
	var lower: float = terrain.surface.height_at(midpoint)
	check(lower < before_saddle - 0.15 and terrain.layout.ridges.has(ridge.key), "dragging lowers the saddle and saves a ridge override")
	history.undo()
	check(absf(terrain.surface.height_at(midpoint) - before_saddle) < 0.01, "one undo restores the original saddle")
	history.redo()
	check(absf(terrain.surface.height_at(midpoint) - lower) < 0.01, "redo restores the edited saddle")
	tool._delete_selected()
	check(terrain.surface.ridges.is_empty(), "the selected ridge can be disconnected")
	history.undo()
	check(terrain.surface.ridges.size() == 1, "undo restores the automatic ridge")

	tool.set_mode(tool.Mode.RIVER)
	for point in [Vector2(-22, 16), Vector2(-4, 20), Vector2(12, 28), Vector2(33, 29)]:
		_click(_screen(point))
	_key(KEY_ENTER)
	check(terrain.layout.features.size() == 3 and terrain.surface.rivers.size() == 1, "four clicks and Enter create an editable river")
	if terrain.surface.rivers.is_empty():
		tree.quit(1)
		return
	var river: Dictionary = terrain.surface.rivers[0]
	var beds: PackedFloat32Array = river.beds
	var descending := true
	for i in range(1, beds.size()):
		descending = descending and beds[i] < beds[i - 1]
	check(descending and terrain.surface.height_at(Vector2(-4, 20)) < -0.8, "river geometry cuts a descending bed below the default floor")

	tool.set_mode(tool.Mode.PLATEAU)
	_button(_screen(Vector2(21, 4)), true)
	_motion(_screen(Vector2(33, 13)), true)
	_button(_screen(Vector2(33, 13)), false)
	var plateau: Dictionary = LAYOUT.find(terrain.layout, tool.selected)
	check(plateau.get("kind") == "plateau" and terrain.surface.height_at(Vector2(27, 8)) >= 8.9, "one drag creates an elevated plateau")
	var edge := _screen(Vector2(27, 13))
	_click(edge)
	_click(edge, true)
	plateau = LAYOUT.find(terrain.layout, tool.selected)
	check(plateau.points.size() == 5, "double-clicking a selected plateau edge adds an editable point")
	tool._duplicate_feature()
	check(terrain.layout.features.size() == 5, "selected terrain features can be copied")
	tool._delete_selected()
	check(terrain.layout.features.size() == 4, "selected terrain features can be deleted")
	tool._choose_preset(0)
	_motion(_screen(Vector2(-16, 23)))
	await tree.create_timer(0.12, true).timeout
	check(terrain.surface.state.features.size() == 6 and terrain.layout.features.size() == 4, "the double-peak preset previews editable terrain without applying")
	_key(KEY_ESCAPE)

	var model := LAYOUT.empty()
	LAYOUT.add(model, LAYOUT.peak(Vector2.ZERO, 28, 25))
	LAYOUT.add(model, LAYOUT.peak(Vector2(4, 0), 12, 25, 1))
	var close_peaks := SURFACE.new(model)
	check(is_equal_approx(close_peaks.height_at(Vector2.ZERO), 28) and is_equal_approx(close_peaks.height_at(Vector2(4, 0)), 12), "nearby peaks keep their authored heights")
	model = LAYOUT.preset(1, Vector2.ZERO)
	check(model.features.size() == 2 and model.features[1].kind == "river", "highland preset contains a plateau and river")

	# Put the test spawn on the plain in front of the saddle, then save it through Godot.
	var spawn := root.get_node("PlayerSpawn") as Node3D
	spawn.position = Vector3(0, 0.15, 10.0)
	var state: Dictionary = terrain.layout.duplicate(true)
	EditorInterface.save_scene_as(PATH, false)
	check(FileAccess.file_exists(PATH), "Godot saves terrain in the native inherited scene")
	var packed := ResourceLoader.load(PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := packed.instantiate()
	var reopened_terrain := reopened.get_node_or_null("Terrain")
	check(reopened_terrain != null and reopened_terrain.get_script() == TERRAIN and reopened_terrain.layout == state and reopened_terrain.get_child_count() == 0, "scene reload reconstructs the exact controls from the authored data")
	reopened.free()

	if OS.get_cmdline_user_args().has("--terrain-capture") and DisplayServer.get_name() != "headless":
		tool._toggle_view()
		camera.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.65, -1)), Vector3(3, 45, 57))
		await tree.create_timer(0.55, true).timeout
		camera.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.65, -1)), Vector3(3, 45, 57))
		await RenderingServer.frame_post_draw
		var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		check(image.save_png("/tmp/gle-terrain-editor.png") == OK, "capture the rendered terrain editor")

	editor._build()
	check(not tool.active and not is_instance_valid(tool.ghost), "F6 preparation exits terrain authoring and clears preview")
	print("TERRAIN EDITOR ", checks - failures, "/", checks)
	tree.quit(0 if failures == 0 else 1)
