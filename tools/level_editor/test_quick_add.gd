@tool
extends RefCounted
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_catalog.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const GROUPS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const SPAWN := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/spawn_marker.gd")
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const CARD := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_card.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)

func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame

func run(editor: EditorPlugin) -> void:
	var tree := editor.get_tree()
	tree.create_timer(90, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.5, true).timeout
	var suite := tree.get_first_node_in_group("godot_level_editor_editor_suite")
	if suite != null: suite.window.hide()
	check(EditorInterface.get_base_control().find_children("关卡摆放", "", true, false).is_empty(), "retired placement dock is not registered in the native editor")
	var old_controls := ["打开触发／操作／判断示例", "打开首版连续世界", "新建房间 .tscn", "实例化房间到世界", "添加所选物件", "复制所选（新对象 ID）", "保存场景并重载校验"]
	check(EditorInterface.get_base_control().find_children("*", "Button", true, false).all(func(button: Button): return button.text not in old_controls), "legacy sidebar actions are removed instead of hidden")
	check(editor.spatial_tools.is_inside_tree() and editor.selection_buttons.keys().size() == 3 and is_instance_valid(editor.step_input), "wheel, face/edge/point controls and step input stay in the native toolbar")
	check(not FileAccess.file_exists("res://addons/godot_level_editor/modules/godot_level_editor/palette_item.gd") and not editor.has_method("_add_spatial") and not editor.has_method("_choose_file") and not editor.has_method("_save_scene"), "legacy card and dock-only authoring paths are deleted")
	var stale_dock := ScrollContainer.new(); stale_dock.name = "关卡摆放"; editor.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, stale_dock)
	var stale_button := Button.new(); stale_dock.add_child(stale_button); editor.push_buttons.append(stale_button); editor.selection_buttons.face.append(stale_button)
	editor._retire_legacy_dock()
	await frames(tree, 2)
	check(not is_instance_valid(stale_dock) and editor.push_buttons.all(func(button: Button): return is_instance_valid(button)) and editor.selection_buttons.face.size() == 1, "hot reload removes an old dock and stale button references without rebuilding the active toolbar")
	var tool: RefCounted = editor.radial_tool
	# A user shortcut such as CapsLock may be synthesized when native windows
	# gain focus. Keep the test's keyboard input independent of that preference.
	var original_shortcut: InputEventKey = tool.shortcut.duplicate()
	tool.shortcut = InputEventKey.new(); tool.shortcut.keycode = KEY_QUOTELEFT
	var original_step: float = editor.edit_step
	editor._set_edit_step(0.1)
	var original_recent: PackedStringArray = tool.recent.duplicate()
	var source_hashes := {}
	for category in CATALOG.CATEGORIES:
		for asset in CATALOG.assets(category): source_hashes[asset.path] = FileAccess.get_sha256(asset.path)
	var path := "res://tools/level_editor/quick_add_probe_%d.tscn" % OS.get_process_id()
	var source := WORLD.new(); source.name = "QuickAddProbe"; source.world_id = "quick_add_probe"; source.start_room_id = ""
	FACTORY.block(source, "floor", Vector3(20, 0.4, 20), Vector3(0, -0.2, 0))
	var spawn := SPAWN.new(); spawn.name = "PlayerSpawn"; spawn.object_id = "player_spawn"; spawn.position = Vector3(0, 0.1, 3)
	FACTORY.add_owned(source, spawn, source)
	FACTORY.save_scene(source, path); source.free()
	EditorInterface.get_resource_filesystem().update_file(path)
	for i in 200:
		if not EditorInterface.get_resource_filesystem().is_scanning(): break
		await tree.create_timer(0.05, true).timeout
	await frames(tree, 10)
	EditorInterface.open_scene_from_path(path)
	for attempt in 200:
		var candidate := EditorInterface.get_edited_scene_root()
		if candidate != null and candidate.scene_file_path == path: break
		if attempt % 20 == 19: EditorInterface.open_scene_from_path(path)
		await tree.create_timer(0.05, true).timeout
	EditorInterface.set_main_screen_editor("3D")
	await frames(tree, 10)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		push_error("QUICK ADD: fixture did not open; actual=" + (root.scene_file_path if root != null else "null")); tree.quit(1); return
	var view := EditorInterface.get_editor_viewport_3d(0)
	var camera := view.get_camera_3d()
	print("QUICK ADD viewport: ", view.size, " container=", view.get_parent().get_class(), " size=", view.get_parent().size)
	check(CATALOG.assets("Layout 白盒").size() == 16, "shared catalog exposes all sixteen existing whitebox shapes")
	check(CATALOG.assets("常驻 Room").size() == 1 and CATALOG.assets("常驻 Room")[0].path.ends_with("trigger_room.tscn"), "Room catalog contains a trigger-box preset without complete room scenes")
	check(not CATALOG.assets("常驻机关").is_empty() and CATALOG.assets("常驻 NPC").size() >= 2, "authored mechanism and NPC scenes are included")
	check(CATALOG.assets("常驻 NPC").all(func(asset: Dictionary): return not CATALOG.preview_path(asset).is_empty()), "NPC assets resolve the same saved thumbnail paths as the NPC editor")
	check(CATALOG.assets("常驻机关").all(func(asset: Dictionary): return not CATALOG.preview_path(asset).is_empty()), "mechanism assets resolve the same saved thumbnail paths as the mechanism editor")
	var manager := editor.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(root))
	var before_version := history.get_version()
	var before_count := root.get_child_count()
	tool.open_wheel(camera, Vector2(2, 2))
	var window := EditorInterface.get_base_control().get_window()
	window.focus_exited.emit()
	check(not tool.menu.visible, "leaving the editor window cancels the wheel")
	# Other editor regression processes may open native windows concurrently.
	# Test cancellation above, then isolate the remaining input assertions.
	window.focus_exited.disconnect(tool.cancel)
	tool.open_wheel(camera, Vector2(2, 2))
	check(tool.menu.visible and tool.menu.categories.size() == 6, "wheel opens over the native viewport with six fixed categories")
	check(tool.menu.wheel_center.x >= tool.menu.radius and tool.menu.wheel_center.y >= tool.menu.radius, "wheel clamps away from the viewport edges")
	tool.menu.hover_at(tool.menu.wheel_center + Vector2.RIGHT * tool.menu.radius * 0.8)
	tool.menu.select_category(1)
	tool.menu.confirm_selection()
	check(tool.menu.page == "assets" and tool.menu.sector_count() == 8 and tool.menu.sector_thumbnails.size() == 8 and tool.menu.page_count() == 2, "clicking Layout opens an eight-shape wheel with two pages")
	var first_page: Array = tool.menu.entries.slice(0, 8).map(func(asset: Dictionary): return asset.path)
	var old_path: String = tool.menu.current_asset().path
	tool.menu.cycle(1)
	check(tool.menu.page_index == 1 and tool.menu.sector_thumbnails.size() == 8 and not first_page.has(tool.menu.current_asset().path), "scrolling replaces all eight shapes with the next page")
	tool.menu.cycle(1)
	check(tool.menu.page_index == 0 and tool.menu.current_asset().path == old_path, "scrolling wraps through the complete shape catalog")
	for shape_page in 2:
		for slot in 8:
			tool.menu.hover_at(tool.menu.wheel_center + Vector2.from_angle(-PI * 0.5 + slot * TAU / 8) * tool.menu.radius * 0.75)
			check(tool.menu.current_asset().path == tool.menu.entries[shape_page * 8 + slot].path, "each radial thumbnail selects its own shape on page %d slot %d" % [shape_page + 1, slot + 1])
		tool.menu.cycle(1)
	tool.menu._click_at(tool.menu.wheel_center)
	check(tool.active_asset.is_empty() and tool.menu.page == "assets", "clicking the transparent center never selects or places an asset")
	check(tool.menu.get_children().all(func(child: Control): return not child.is_visible_in_tree() or not child.get_rect().has_point(tool.menu.wheel_center)), "the center contains no preview, background control or return button")
	tool.menu.go_back(); tool.menu.select_category(4); tool.menu.confirm_selection()
	tool.menu.hover_at(tool.menu.wheel_center + Vector2.from_angle(-PI * 0.5 + 2 * TAU / 3) * tool.menu.radius * 0.75)
	tool.menu.confirm_selection()
	check(tool.menu.chooser.visible, "the existing-assets sector opens the NPC library without a footer button")
	tool.menu.search.text = "不存在的素材"; tool.menu.search.text_changed.emit(tool.menu.search.text)
	check(tool.menu.chooser.visible and tool.menu.grid.get_children().all(func(child: Control): return not child.visible), "all-assets panel filters the same catalog by name")
	tool.menu.show_catalog(); await frames(tree, 5)
	print("CATALOG LAYOUT grid=", tool.menu.grid.get_rect(), " child_count=", tool.menu.grid.get_child_count(), " first=", tool.menu.grid.get_child(0).get_rect(), " visible=", tool.menu.grid.get_child(0).is_visible_in_tree())
	check(tool.menu.grid.size.y > 0 and tool.menu.grid.get_child(0).is_visible_in_tree(), "reopening all-assets resets filtering and lays out visible cards")
	check(tool.menu.grid.get_children().all(func(card: Button): return card.icon == CARD.preview_texture(str(card.get_meta("editor_preview_path", "")))), "NPC library buttons immediately display the editor's cached preview textures")
	tool.cancel()
	check(root.get_child_count() == before_count and history.get_version() == before_version, "browsing and cancelling the wheel creates no objects or undo actions")
	tool.open_wheel(camera)
	var hover_window := EditorInterface.get_base_control().get_window()
	for sector in 6:
		var position: Vector2 = tool.menu.get_global_transform_with_canvas() * (tool.menu.wheel_center + Vector2.from_angle(-PI * 0.5 + sector * TAU / 6) * tool.menu.radius * 0.76)
		var hover := InputEventMouseMotion.new(); hover.position = position; hover.global_position = position
		hover_window.push_input(hover, true)
		check(tool.menu.category == sector, "real mouse hover selects sector " + str(sector) + " independently of the last used tool")
	tool.menu.set_meta("quick_add_ui_revision", 0)
	tool.process()
	check(tool.menu.get_meta("quick_add_ui_revision", 0) == tool.menu.UI_REVISION, "hot reload rebuilds stale wheel controls while preserving the open level")
	tool.open_wheel(camera)
	tool.menu.select_category(1)
	await frames(tree, 3)
	await tree.create_timer(0.3, true).timeout
	# Hover every sector through real window input, including non-whitebox previews.
	# After each injected motion, hold input steady while checking its animation.
	# This avoids unrelated physical pointer motion from concurrent editor tests.
	for index in 6:
		var hover_point: Vector2 = tool.menu.get_global_transform() * (tool.menu.wheel_center + Vector2.from_angle(-PI * 0.5 + index * TAU / 6) * tool.menu.radius * 0.76)
		var hover_motion := InputEventMouseMotion.new(); hover_motion.position = hover_point; hover_motion.global_position = hover_point
		window.push_input(hover_motion, true)
		tool.menu.interaction_enabled = false
		await tree.create_timer(0.16, true).timeout
		await frames(tree, 2)
		if tool.menu.category != index or tool.menu._weights[index] <= 0.95:
			print("HOVER DIAGNOSTIC expected=", index, " actual=", tool.menu.category, " weight=", tool.menu._weights[index], " hovered=", tool.menu.hovered, " open=", tool.menu.is_open(), " focus=", window.has_focus(), " tween=", tool.menu._hover_tween.is_running() if is_instance_valid(tool.menu._hover_tween) else false)
		check(tool.menu.category == index and tool.menu._weights[index] > 0.95, "real mouse hover highlights wheel sector %s" % tool.menu.categories[index])
		tool.menu.interaction_enabled = true
	tool.menu.select_category(1); tool.menu.confirm_selection()
	var wheel_point: Vector2 = tool.menu.get_global_transform() * (tool.menu.wheel_center + Vector2.UP * tool.menu.radius * 0.75)
	var wheel_event := InputEventMouseButton.new(); wheel_event.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel_event.pressed = true; wheel_event.position = wheel_point; wheel_event.global_position = wheel_point
	old_path = tool.menu.current_asset().path
	window.push_input(wheel_event, true)
	await frames(tree, 2)
	check(tool.menu.page_index == 1 and tool.menu.current_asset().path != old_path, "real viewport mouse-wheel input changes the eight-shape page")
	wheel_event.button_index = MOUSE_BUTTON_MIDDLE; window.push_input(wheel_event, true)
	check(tool.menu.page_index == 0, "pressing the wheel button also switches to the next shape page")
	wheel_event.pressed = false; window.push_input(wheel_event, true)
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel_event.pressed = true; window.push_input(wheel_event, true)
	var selection_click := InputEventMouseButton.new(); selection_click.button_index = MOUSE_BUTTON_LEFT; selection_click.pressed = true; selection_click.position = wheel_point; selection_click.global_position = wheel_point
	window.push_input(selection_click, true)
	await frames(tree, 2)
	check(not tool.active_asset.is_empty() and not tool.menu.is_open(), "real mouse click selects the hovered asset and enters placement")
	var count_before_selection := root.get_child_count()
	var repeated_press: InputEventMouseButton = selection_click.duplicate(); repeated_press.position = Vector2(view.size) * 0.5
	editor._forward_3d_gui_input(camera, repeated_press)
	check(root.get_child_count() == count_before_selection, "the menu selection press cannot also place an object through the viewport")
	selection_click.pressed = false; window.push_input(selection_click, true)
	tool.cancel()
	var side := InputEventMouseButton.new(); side.button_index = MOUSE_BUTTON_XBUTTON1; side.pressed = true; side.position = Vector2(view.size) * 0.5
	editor._forward_3d_gui_input(camera, side)
	check(tool.menu.is_open(), "short side-button press opens the wheel")
	side.pressed = false; window.push_input(side, true)
	check(tool.menu.is_open() and tool.active_asset.is_empty(), "releasing the side button keeps the wheel open without selecting")
	# Reproduce motion routed to the native overlay instead of the wheel GUI.
	tool.menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 6:
		var hover_point: Vector2 = tool.menu.get_global_transform() * (tool.menu.wheel_center + Vector2.from_angle(-PI * 0.5 + index * TAU / 6) * tool.menu.radius * 0.76)
		var hover_motion := InputEventMouseMotion.new(); hover_motion.position = hover_point; hover_motion.global_position = hover_point
		window.push_input(hover_motion, true)
		tool.menu.interaction_enabled = false
		await tree.create_timer(0.16, true).timeout
		await frames(tree, 2)
		if tool.menu.category != index or tool.menu._weights[index] <= 0.95:
			print("OVERLAY HOVER DIAGNOSTIC expected=", index, " actual=", tool.menu.category, " weight=", tool.menu._weights[index], " hovered=", tool.menu.hovered, " open=", tool.menu.is_open(), " focus=", window.has_focus(), " tween=", tool.menu._hover_tween.is_running() if is_instance_valid(tool.menu._hover_tween) else false)
		check(tool.menu.category == index and tool.menu._weights[index] > 0.95, "side-key wheel hover survives native GUI interception for %s" % tool.menu.categories[index])
		tool.menu.interaction_enabled = true
	tool.menu.mouse_filter = Control.MOUSE_FILTER_STOP
	check(tool.menu.find_children("*", "OptionButton", true, false).is_empty(), "the unnecessary placement-parent selector is removed")
	side.pressed = true; window.push_input(side, true)
	check(not tool.menu.is_open() and tool.menu.closing, "the next short side-button press starts the closing animation")
	side.pressed = false; window.push_input(side, true)
	await tree.create_timer(0.2, true).timeout
	check(not tool.menu.visible, "closing animation finishes and releases the viewport")
	tool.open_wheel(camera); tool.menu.select_category(4); tool.menu.confirm_selection()
	check(tool.menu.page == "scope" and tool.menu.current_asset().lifetime == "level", "NPC sector opens the persistent versus task secondary wheel")
	await tree.create_timer(0.25, true).timeout
	check(tool.menu.page == "scope" and tool.menu._weights.size() == 3 and (tool.menu.is_open() or not window.has_focus()), "secondary wheel keeps scope and existing-assets sectors after animation")
	if not tool.menu.is_open(): tool.open_wheel(camera); tool.menu.select_category(4); tool.menu.open_submenu()
	tool.menu.hover_at(tool.menu.wheel_center + Vector2.from_angle(PI / 6) * tool.menu.radius * 0.75)
	await tree.create_timer(0.15, true).timeout
	check(tool.menu._weights[1] > 0.95 and tool.menu.current_asset().lifetime == "task", "hover animation finishes on the task sector without changing scene data")
	tool.menu.lifetime_index = 1; tool.menu.confirm_selection()
	check(tool.active_asset.lifetime == "task" and tool.ghost.get_meta(PROFILE.META).kind == "npc", "task NPC selection enters model placement with task scope")
	tool.cancel()
	var environment_path := "res://tools/level_editor/.quick_add_environment_%d.tscn" % OS.get_process_id()
	var environment_source := FACTORY.ROOM.new(); environment_source.name = "EnvironmentProbe"
	var environment_node := WorldEnvironment.new(); environment_node.environment = Environment.new(); FACTORY.add_owned(environment_source, environment_node, environment_source)
	var prefab_camera := Camera3D.new(); prefab_camera.current = true; FACTORY.add_owned(environment_source, prefab_camera, environment_source)
	FACTORY.save_scene(environment_source, environment_path); environment_source.free()
	tool.open_wheel(camera)
	var environment_before: Environment = camera.get_world_3d().environment
	tool.begin_asset({"path": environment_path, "title": "环境预览检查", "category": "常驻 Room", "kind": ""})
	check(camera.get_world_3d().environment == environment_before and view.get_camera_3d() == camera, "prefab preview leaves the editor environment and active camera intact")
	tool.cancel(); DirAccess.remove_absolute(ProjectSettings.globalize_path(environment_path))
	tool.open_wheel(camera)
	var box: Dictionary = CATALOG.assets("Layout 白盒")[0]
	tool.menu.select_category(1)
	tool.menu.confirm_selection()
	tool.menu.indices[1] = 0
	tool.menu.confirm_selection()
	check(tool.active_asset.path == box.path and is_instance_valid(tool.ghost) and not root.is_ancestor_of(tool.ghost) and tool.ghost.owner == null, "confirmation creates a passive ghost outside the authored scene")
	var point := camera.unproject_position(Vector3(2.2, 0, 1.3))
	tool.update_preview(camera, point)
	check(tool.placement_valid and is_equal_approx(tool.placement_transform.origin.y, 0.5), "surface picking rests a unit box on the existing floor")
	check(tool.placement_transform.origin.is_equal_approx(tool.placement_transform.origin.snapped(Vector3.ONE * 0.1)), "placement uses the existing 0.1 metre grid")
	for value in [0.5, 1.0, 0.25]:
		editor._set_edit_step(value)
		tool.update_preview(camera, camera.unproject_position(Vector3(2.2, 0, 1.3)))
		check(tool.placement_transform.origin.is_equal_approx(tool.placement_transform.origin.snapped(Vector3.ONE * value)), "wheel placement follows editing step %s" % value)
	editor._set_edit_step(0.1)
	tool.update_preview(camera, point)
	var first: Node3D = tool.place()
	check(first != null and first.owner == root and first.scene_file_path == box.path and GROUPS.is_group(first.get_parent()) and first.get_parent().get_parent() == root and first.get_parent().name == "Whitebox", "placement creates an owned instance under the whitebox management node")
	var first_transform: Transform3D = first.global_transform
	check(not tool.active_asset.is_empty(), "whitebox placement remains active for continuous adding")
	history.undo()
	check(not first.is_inside_tree() and GROUPS.find_group(root, "whitebox") == null, "one native undo removes the first instance and newly created group")
	history.redo()
	check(first.is_inside_tree() and first.global_transform.is_equal_approx(first_transform), "native redo restores the exact instance and transform")
	tool.update_preview(camera, camera.unproject_position(Vector3(-2, 0, 0)))
	var second: Node3D = tool.place()
	check(second != null and second.object_id != first.object_id and second.get_parent() == first.get_parent(), "repeated additions reuse one category group and get unique stable object IDs")
	check(tool.recent[0] == box.path and tool.recent.count(box.path) == 1, "recent assets contain successful placements without duplicates")
	tool.cancel()
	tool.open_wheel(camera)
	tool.menu.select_category(2); tool.menu.confirm_selection()
	check(tool.menu.sector_count() == 2, "Room wheel offers trigger scopes without a complete-scene library")
	tool.begin_asset(CATALOG.assets("常驻 Room")[0])
	tool.update_preview(camera, camera.unproject_position(Vector3(4, 0, -3)))
	var room: Node3D = tool.place()
	check(room.bounds_size == Vector3.ONE and room.get_node("RoomPreview").mesh is BoxMesh and room.get_node("RoomPreview").material_override.albedo_color == room.preview_color(), "new Room is a one-metre translucent trigger cube")
	check(room != null and not room.uses_topology and room.owner == root and room.get_parent() == GROUPS.find_group(root, "room") and root.rooms().has(room), "grouped permanent Room remains visible to world detection and uses the original scope")
	await frames(tree, 2)
	check(root.start_room_id.is_empty(), "permanent detection Room does not acquire a topology starting-room binding")
	room.position = Vector3(3, 0, -2); room.rotation.y = PI * 0.5
	tool.target_parent = room
	tool.begin_asset(box)
	tool.update_preview(camera, camera.unproject_position(Vector3(5, 0, -2)))
	var expected: Transform3D = tool.placement_transform
	var nested: Node3D = tool.place()
	check(nested.get_parent() == GROUPS.find_group(root, "whitebox") and nested.owner == root and nested.global_transform.is_equal_approx(expected), "new whitebox placement uses its level group even when a Room was previously selected")
	tool.cancel()
	tool.open_wheel(camera); tool.begin_asset({"path": "res://content/scenes/level_editor/rooms/new_room.tscn", "category": "常驻 Room", "title": "旧房间兼容检查", "kind": ""})
	tool.update_preview(camera, camera.unproject_position(Vector3(7, 0, -5)))
	var linked_room: Node3D = tool.place()
	check(linked_room != null and root.start_room_id == linked_room.room_id, "the first topology Room establishes the starting-room binding")
	history.undo()
	check(root.start_room_id.is_empty() and not linked_room.is_inside_tree(), "undo restores both the Room and its starting-room binding atomically")
	tool.cancel()
	var original_spawn: Node3D = root.get_node("PlayerSpawn")
	var spawn_transform: Transform3D = original_spawn.global_transform
	tool.open_wheel(camera); tool.begin_asset(CATALOG.assets("玩家出生点")[0])
	tool.update_preview(camera, camera.unproject_position(Vector3(-3, 0, 2)))
	tool.yaw = PI * 0.5; tool.update_preview(camera, tool.last_mouse)
	var moved: Node3D = tool.place()
	check(moved == original_spawn and root.find_children("*", "Marker3D", true, false).size() == 1 and not moved.global_transform.is_equal_approx(spawn_transform), "player-spawn placement moves the existing marker without adding another")
	check(tool.active_asset.is_empty() and not is_instance_valid(tool.ghost), "spawn placement ends and disposes the temporary preview")
	history.undo()
	check(original_spawn.global_transform.is_equal_approx(spawn_transform), "undo restores the existing spawn position and orientation")
	history.redo()
	tool.open_wheel(camera)
	var mechanism: Dictionary = CATALOG.find_asset("res://addons/godot_level_editor/scenes/mechanisms/single_door.tscn")
	tool.begin_asset(mechanism); tool.update_preview(camera, camera.unproject_position(Vector3(-5, 0, -3)))
	var assembly: Node3D = tool.place()
	check(assembly != null and not str(assembly.instance_id).is_empty() and assembly.get_children().any(func(child: Node): return child.get("object_id") == "door"), "mechanism addition replaces instance scope and preserves local graph bindings")
	tool.cancel()
	var node_count := root.get_child_count()
	tool.open_wheel(camera); tool.begin_asset(CATALOG.template("常驻 NPC", "level"))
	var cancel_event := InputEventMouseButton.new(); cancel_event.button_index = MOUSE_BUTTON_RIGHT; cancel_event.pressed = true
	check(editor._forward_3d_gui_input(camera, cancel_event) == EditorPlugin.AFTER_GUI_INPUT_STOP and tool.active_asset.is_empty() and root.get_child_count() == node_count, "right click cancels preview without authoring a node")
	cancel_event.pressed = false; editor._forward_3d_gui_input(camera, cancel_event)
	check(editor._forward_3d_gui_input(camera, cancel_event) == EditorPlugin.AFTER_GUI_INPUT_PASS, "idle wheel leaves native viewport navigation available")
	tool.open_wheel(camera); tool.begin_asset(CATALOG.template("常驻 NPC", "level"))
	EditorInterface.get_selection().clear()
	point = Vector2(view.size) * 0.5
	var click_point: Vector2 = view.get_parent().get_global_transform() * point
	var mouse_motion := InputEventMouseMotion.new(); mouse_motion.position = click_point; mouse_motion.global_position = click_point
	window.push_input(mouse_motion, true)
	selection_click.position = click_point; selection_click.global_position = click_point; selection_click.pressed = true
	window.push_input(selection_click, true)
	selection_click.pressed = false; window.push_input(selection_click, true)
	print("NATIVE PLACE before=", node_count, " after=", root.get_child_count(), " point=", click_point, " valid=", tool.placement_valid)
	check(root.get_child_count() == node_count + 1, "real native viewport click commits the preview into the level")
	tool.cancel()
	var npc: Node3D = EditorInterface.get_selection().get_selected_nodes()[0]
	check(npc.get_meta(PROFILE.META).model_id == "default" and npc.get_node("EntityProperties").owner == root, "new NPC uses its imported model with a persisted instance adapter")
	check(npc.get_node("ModelRoot").get_script() == preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd") and npc.get_node("EntityProperties").visual == null, "default placement keeps the authored model without a primitive overlay")
	EditorInterface.edit_node(npc); await frames(tree, 12)
	var inspector := EditorInterface.get_inspector().find_child("LevelEntityInspector", true, false)
	check(inspector != null and inspector.fields.has("model_id") and inspector.fields.has("faction") and inspector.fields.has("default_action"), "native Inspector exposes model ID, faction and default action fields")
	if inspector != null:
		inspector._commit("faction", "hostile")
		check(npc.get_meta(PROFILE.META).faction == "hostile", "Inspector faction change updates instance configuration")
		history.undo(); check(npc.get_meta(PROFILE.META).faction == "friendly", "native undo restores Inspector properties")
		history.redo(); check(npc.get_meta(PROFILE.META).faction == "hostile", "native redo restores Inspector properties")
		check(inspector.fields.model_id.item_count == 2 and inspector.fields.model_id.get_item_metadata(0) == "default" and inspector.fields.model_id.get_item_metadata(1) == "custom", "NPC model picker offers original and custom models without legacy primitives")
		inspector._commit("default_action", "walk")
		inspector._commit("model_scene", load("res://addons/godot_level_editor/assets/characters/npc_samples_v1/imported/human_medium_female.scn"))
		inspector._commit("model_id", "custom")
		check(npc.get_meta(PROFILE.META).default_action == "walk" and npc.get_node("EntityProperties").visual != null, "custom model scene keeps default action configuration")
		history.undo(); history.undo()
	EditorInterface.edit_node(room); await frames(tree, 8)
	inspector = EditorInterface.get_inspector().find_child("LevelEntityInspector", true, false)
	check(inspector != null and inspector.fields.has("bounds_0") and inspector.fields.has("volume_material") and inspector.fields.has("keep_active_on_exit") and not inspector.fields.has("model_id"), "Room Inspector exposes volume dimensions, material and activation rule rather than a model scene")
	if inspector != null: inspector._commit_property("bounds_size", Vector3(8, 3, 5))
	check(room.bounds_size == Vector3(8, 3, 5), "Room dimensions change through native scene undo history")
	tool.open_wheel(camera); tool.begin_asset(CATALOG.template("常驻机关", "level")); tool.update_preview(camera, camera.unproject_position(Vector3(-4, 0, 4)))
	var placeholder: Node3D = tool.place(); tool.cancel()
	EditorInterface.edit_node(placeholder); await frames(tree, 8)
	inspector = EditorInterface.get_inspector().find_child("LevelEntityInspector", true, false)
	check(inspector != null and inspector.fields.has("component_scene"), "mechanism placeholder exposes the shared Inspector and a real component scene slot")
	if inspector != null: inspector._component_changed(load("res://addons/godot_level_editor/scenes/mechanisms/button.tscn"))
	check(placeholder.component_scene != null and placeholder.get_meta(PROFILE.META).model_id == "default", "mechanism scene selection preserves the existing reusable component contract")
	tool.open_wheel(camera); tool.begin_asset(CATALOG.template("常驻 NPC", "task")); tool.update_preview(camera, Vector2(view.size) * 0.5)
	var task_npc: Node3D = tool.place(); tool.cancel()
	check(task_npc.get_meta(PROFILE.META).lifetime == "task" and not task_npc.get_meta(PROFILE.META).validate().is_empty(), "task NPC retains its task-binding slot and reports a missing task selection")
	check(CATALOG.recent_assets(tool.recent)[0].lifetime == "task", "recent assets preserve task versus persistent scope")
	tool.open_wheel(camera); tool.begin_asset(box)
	var packed := PackedScene.new(); packed.pack(root)
	var saved := packed.instantiate()
	check(saved.find_children("*QuickAdd*", "Node", true, false).is_empty() and saved.find_children("*", "Marker3D", true, false).size() == 1, "packing the level excludes the ghost and keeps only authored objects")
	saved.free(); tool.cancel()
	EditorInterface.save_scene_as(path, false)
	var disk_scene: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var disk_root: Node3D = disk_scene.instantiate()
	var disk_room: Node3D = disk_root.get_node(root.get_path_to(room))
	check(disk_room.has_node("EntityProperties") and disk_root.get_node(root.get_path_to(nested)).object_id == nested.object_id and disk_room.transform.is_equal_approx(room.transform), "native save and disk reload preserve placements, instance adapters and stable IDs")
	var disk_npc: Node = disk_root.get_node(root.get_path_to(npc))
	check(disk_npc.get_meta(PROFILE.META).faction == "hostile" and disk_npc.get_meta(PROFILE.META).default_action == "walk" and disk_npc.has_node("EntityProperties"), "Inspector model and behavior attributes survive native save and reload")
	disk_root.free()
	tool.open_wheel(camera); tool.begin_asset(box)
	editor._build()
	check(not is_instance_valid(tool.ghost) and not tool.menu.visible, "starting F5/F6 disposes the wheel and ghost before game launch")
	if OS.get_cmdline_user_args().has("--capture-trigger-rooms"):
		var capture_dir := "res://docs/level_editor/room_triggers_2026-11-16"
		DirAccess.make_dir_recursive_absolute(capture_dir)
		for content in GROUPS.contents(root):
			if content is Node3D and content != root.get_node("Floor") and content != room: content.hide()
		room.position = Vector3(-0.8, 0, 0); room.rotation = Vector3.ZERO; room.bounds_size = Vector3.ONE; room.refresh_volume(); room.show()
		tool.open_wheel(camera); tool.begin_asset(CATALOG.template("常驻 Room", "task"))
		tool.placement_transform = Transform3D(Basis.IDENTITY, Vector3(0.8, 0, 0)); tool.placement_valid = true
		var task_volume: Node3D = tool.place(); tool.cancel()
		check(task_volume.preview_color().g > room.preview_color().g and task_volume.get_node("RoomPreview").material_override.albedo_color.a < 0.5, "task Room has a translucent light-green material distinct from the level Room")
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(room); EditorInterface.get_selection().add_node(task_volume)
		await frames(tree, 8); _frame_selection(view, window); await tree.create_timer(0.3, true).timeout
		tool.cancel()
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(room); EditorInterface.edit_node(room)
		if editor.has_method("hide_bottom_panel"): editor.call("hide_bottom_panel")
		await frames(tree, 8)
		var room_pick: Vector2 = view.get_parent().get_global_transform() * camera.unproject_position(room.global_position + Vector3.UP * 0.5)
		EditorInterface.get_selection().clear()
		var room_motion := InputEventMouseMotion.new(); room_motion.position = room_pick; room_motion.global_position = room_pick; window.push_input(room_motion, true)
		var room_click := InputEventMouseButton.new(); room_click.button_index = MOUSE_BUTTON_LEFT; room_click.pressed = true; room_click.position = room_pick; room_click.global_position = room_pick
		window.push_input(room_click, true); room_click.pressed = false; window.push_input(room_click, true)
		await frames(tree, 5)
		print("ROOM PICK selected=", EditorInterface.get_selection().get_selected_nodes().map(func(node: Node): return str(node.name)), " at=", room_pick, " wheel=", tool.menu.visible, " shortcut=", tool.shortcut.as_text())
		check(EditorInterface.get_selection().get_selected_nodes().has(room), "clicking a translucent Room face selects its authored trigger and Inspector")
		RenderingServer.force_draw(false)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_dir + "/room_volumes.png")
	if OS.get_cmdline_user_args().has("--capture-library-thumbnails"):
		var capture_dir := "res://docs/level_editor/asset_thumbnails_2026-11-16"
		DirAccess.make_dir_recursive_absolute(capture_dir)
		for category in [4, 3]:
			tool.open_wheel(camera); tool.menu.interaction_enabled = false; tool.menu.select_category(category); tool.menu.open_submenu(); tool.menu.show_catalog()
			await tree.create_timer(0.4, true).timeout; await frames(tree, 5); RenderingServer.force_draw(false)
			check(tool.menu.grid.get_children().all(func(card: Button): return card.icon != null and card.icon == CARD.preview_texture(str(card.get_meta("editor_preview_path", "")))), "rendered library uses saved editor images for category %d" % category)
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_dir + ("/npc_library.png" if category == 4 else "/mechanism_library.png"))
			tool.cancel()
	if OS.get_cmdline_user_args().has("--capture-quick-add"):
		var capture_dir := "res://docs/level_editor/radial_pages_2026-11-16"
		DirAccess.make_dir_recursive_absolute(capture_dir)
		var ignore := FileAccess.open(capture_dir + "/.gdignore", FileAccess.WRITE); ignore.close()
		for node in GROUPS.contents(root):
			if node is Node3D and node != root.get_node("Floor") and node != npc: node.hide()
		npc.position = Vector3.ZERO; npc.show(); EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(npc); EditorInterface.edit_node(npc)
		await frames(tree, 8)
		_frame_selection(view, window)
		await tree.create_timer(0.3, true).timeout
		var cleanup_dir := "res://docs/enemy_editor/legacy_cleanup_2026-11-16"
		DirAccess.make_dir_recursive_absolute(cleanup_dir)
		RenderingServer.force_draw(false)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(cleanup_dir + "/default_npc.png")
		EditorInterface.get_selection().clear(); await frames(tree, 3)
		var pick_at: Vector2 = view.get_parent().get_global_transform() * camera.unproject_position(npc.global_position + Vector3.UP * 0.85)
		var pick_motion := InputEventMouseMotion.new(); pick_motion.position = pick_at; pick_motion.global_position = pick_at; window.push_input(pick_motion, true)
		var pick_click := InputEventMouseButton.new(); pick_click.button_index = MOUSE_BUTTON_LEFT; pick_click.pressed = true; pick_click.position = pick_at; pick_click.global_position = pick_at; window.push_input(pick_click, true)
		pick_click.pressed = false; window.push_input(pick_click, true); await frames(tree, 5)
		print("NPC PICK selected=", EditorInterface.get_selection().get_selected_nodes().map(func(node: Node): return str(node.name)), " pixel=", pick_at, " camera=", camera.global_position)
		check(EditorInterface.get_selection().get_selected_nodes().has(npc), "clicking the visible model selects its authored NPC and Inspector")
		if editor.has_method("hide_bottom_panel"): editor.call("hide_bottom_panel")
		tool.open_wheel(camera); tool.menu.interaction_enabled = false; tool.menu.select_category(1)
		await tree.create_timer(0.3, true).timeout; RenderingServer.force_draw(false)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_dir + "/wheel.png")
		tool.menu.confirm_selection(); await tree.create_timer(0.3, true).timeout; RenderingServer.force_draw(false)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_dir + "/whitebox_page_1.png")
		tool.menu.cycle(1); await tree.create_timer(0.3, true).timeout; RenderingServer.force_draw(false)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_dir + "/whitebox_page_2.png")
		tool.menu.select_category(4); tool.menu.open_submenu(); await tree.create_timer(0.3, true).timeout; RenderingServer.force_draw(false)
		print("CAPTURE SUBMENU page=", tool.menu.page, " sectors=", tool.menu._weights.size(), " alpha=", tool.menu.modulate.a)
		check(tool.menu.page == "scope" and tool.menu._weights.size() == 3, "rendered NPC wheel contains scope and existing-assets sectors")
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_dir + "/npc_submenu.png")
		tool.cancel()
		for content in GROUPS.contents(root):
			if content is Node3D: content.hide()
		first.show(); first.position = Vector3.ZERO
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(first); EditorInterface.edit_node(first)
		await frames(tree, 8); _frame_selection(view, window)
		await tree.create_timer(0.3, true).timeout; RenderingServer.force_draw(false)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_dir + "/whitebox_selection.png")
		first.hide(); root.get_node("Floor").show()
		for pair in [[npc, "npc_inspector"], [room, "room_inspector"], [placeholder, "mechanism_inspector"]]:
			npc.hide(); room.hide(); placeholder.hide(); pair[0].show(); pair[0].position = Vector3.ZERO
			EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(pair[0]); EditorInterface.edit_node(pair[0])
			await frames(tree, 8); _frame_selection(view, window)
			await tree.create_timer(0.3, true).timeout
			RenderingServer.force_draw(false)
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture_dir + "/" + pair[1] + ".png")
	tool.cancel(); tool.recent = original_recent
	editor._set_edit_step(original_step)
	EditorInterface.get_editor_settings().set_project_metadata(tool.METADATA, "recent", original_recent)
	EditorInterface.save_scene_as(path, false)
	EditorInterface.close_scene()
	await frames(tree, 5)
	EditorInterface.open_scene_from_path("res://content/scenes/main.tscn")
	await frames(tree, 10)
	check(not is_instance_valid(tool.ghost) and not tool.menu.visible, "changing scenes cleans up all wheel and preview state")
	check(source_hashes.keys().all(func(asset_path: String): return FileAccess.get_sha256(asset_path) == source_hashes[asset_path]), "all existing source Room, mechanism, NPC and palette files remain byte-identical")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	window.focus_exited.connect(tool.cancel)
	tool.shortcut = original_shortcut
	print("QUICK ADD: ", checks, " checks, ", failures, " failures")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-native-capture=") and DisplayServer.get_name() != "headless":
			RenderingServer.force_draw(false)
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--qa-native-capture="))
	tree.quit(0 if failures == 0 else 1)

func _frame_selection(view: SubViewport, window: Window) -> void:
	var surface: Control = view.get_parent()
	while surface.get_parent() is Control and surface.get_class() != "Node3DEditorViewport": surface = surface.get_parent()
	for candidate in surface.find_children("*", "Control", true, false):
		if candidate.is_visible_in_tree() and candidate.focus_mode == Control.FOCUS_ALL and candidate.size.x > surface.size.x * 0.9 and candidate.size.y > surface.size.y * 0.9:
			candidate.grab_focus(); break
	var key := InputEventKey.new(); key.keycode = KEY_F; key.pressed = true
	window.push_input(key, true); key.pressed = false; window.push_input(key, true)
