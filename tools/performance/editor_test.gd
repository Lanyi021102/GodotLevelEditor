@tool
extends RefCounted

const TEMPLATE := preload("res://addons/godot_level_editor/templates/empty_level.tscn")
const ROOM := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/room.gd")
const NPC := preload("res://addons/godot_level_editor/scenes/npcs/v1_human_medium_male.tscn")
const BOX := preload("res://addons/godot_level_editor/modules/godot_level_editor/palette_assets/box.tscn")
const DATA := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sequence.gd")
var fixture := "res://tools/performance/.fixture_%d.tscn" % OS.get_process_id()
const ACTOR := "$world/test_resident"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func frames(tree: SceneTree, count := 3) -> void:
	for i in count: await tree.process_frame

func prepare() -> int:
	var world := TEMPLATE.instantiate()
	var npc := NPC.instantiate()
	npc.name = "大厅居民"
	npc.enemy_instance_id = "test_resident"
	npc.position = Vector3(-2, 0, -1)
	_add(world, npc)
	var room := ROOM.new()
	room.name = "入口"
	room.room_id = "entry"
	room.uses_topology = false
	room.position = Vector3(0, 0, -2)
	room.bounds_size = Vector3(2.0, 2.0, 2.0)
	_add(world, room)
	for x in [-2.7, 2.7]:
		var block := BOX.instantiate()
		block.name = "WallL" if x < 0 else "WallR"
		block.object_id = "wall_l" if x < 0 else "wall_r"
		block.size = Vector3(3.0, 2.6, 0.3)
		block.position = Vector3(x, 1.3, -4.0)
		_add(world, block)
	world.topology.graph_id = "performance_fixture_topology"
	world.events.graph_id = "performance_fixture_events"
	world.level_logic.graph_id = "performance_fixture_logic"
	var scene := PackedScene.new()
	var result := scene.pack(world)
	world.free()
	return ResourceSaver.save(scene, fixture) if result == OK else result

func _add(root: Node, child: Node) -> void:
	root.add_child(child)
	child.owner = root

func click(canvas: Control, start: Vector2, end: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = start
	down.pressed = true
	canvas._gui_input(down)
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(motion)
	var up := down.duplicate() as InputEventMouseButton
	up.position = end
	up.pressed = false
	canvas._gui_input(up)

func pick(suite: EditorPlugin, camera: Camera3D, position: Vector3) -> bool:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = camera.unproject_position(position)
	return suite.modules.level._forward_3d_gui_input(camera, event) == EditorPlugin.AFTER_GUI_INPUT_STOP

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(75.0).timeout.connect(func(): tree.quit(2))
	check(prepare() == OK, "prepare isolated whitebox level")
	EditorInterface.open_scene_from_path(fixture)
	EditorInterface.set_main_screen_editor("3D")
	await frames(tree, 8)
	var world := EditorInterface.get_edited_scene_root() as Node3D
	check(world != null and world.scene_file_path == fixture, "open native fixture")
	if world == null or world.scene_file_path != fixture: tree.quit(1); return
	suite.open_tab("关卡")
	suite.level_panel.set_mode(1)
	suite.level_panel._performance_button.button_pressed = true
	await frames(tree)
	var panel: Control = suite.level_panel.performance_panel
	check(panel != null and panel.visible and not suite.level_panel.logic_panel.visible, "open 演出时间轴 inside 关卡编辑")
	if panel == null: tree.quit(1); return
	panel._create()
	await frames(tree)
	var data: Resource = panel._data()
	check(data != null and world.performances.size() == 1, "create a scene-owned sequence with stable ID")
	if data == null: tree.quit(1); return
	var key: String = data.id
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	camera.look_at_from_position(Vector3(4, 4, 7), Vector3(0, 1, -2))
	panel._capture_camera(false)
	await frames(tree)
	check(panel._data().clips[0].pose.origin.is_equal_approx(Vector3(4, 4, 7)), "capture native 3D camera pose")
	panel._select_clip(panel._data().clips[0].id)
	var canvas: Control = panel._timeline
	click(canvas, Vector2(canvas.HEADER + canvas.SCALE - 4, canvas.RULER + 12), Vector2(canvas.HEADER + 2 * canvas.SCALE - 4, canvas.RULER + 12))
	await frames(tree)
	check(is_equal_approx(panel._data().clips[0].duration, 2.0), "resize the camera clip by dragging its right edge")
	click(canvas, Vector2(canvas.HEADER + 2.5 * canvas.SCALE, 10), Vector2(canvas.HEADER + 2.5 * canvas.SCALE, 10))
	camera.look_at_from_position(Vector3(2.8, 2.25, 1.4), Vector3(0.8, 0.9, -3.6))
	panel._capture_camera(false)
	await frames(tree)
	check(is_equal_approx(panel._data().clips[1].start, 2.5), "place another shot at the playhead")
	click(canvas, Vector2(canvas.HEADER + 2.8 * canvas.SCALE, canvas.RULER + 12), Vector2(canvas.HEADER + 2.3 * canvas.SCALE, canvas.RULER + 12))
	await frames(tree)
	check(is_equal_approx(panel._data().clips[1].start, 2.0), "drag the shot earlier with 0.1-second snapping")
	panel._history(false)
	await frames(tree)
	check(is_equal_approx(panel._data().clips[1].start, 2.5), "native scene undo restores previous clip start")
	panel._history(true)
	await frames(tree)
	check(is_equal_approx(panel._data().clips[1].start, 2.0), "native scene redo restores the edited clip")
	panel._change_clip_time(panel._data().clips[1].id, 1.5, 1.0)
	check(is_equal_approx(panel._data().clips[1].start, 2.0), "reject same-track overlap")
	panel._change_clip_time(panel._data().clips[1].id, 2.0, 3.0)
	await frames(tree)
	panel._add_dropped_actor({"type": "nodes", "nodes": [NodePath("大厅居民")]})
	await frames(tree)
	check(ACTOR in panel._data().actors, "scene-tree drag payload binds non-conversational NPC by stable ID")
	var actor := world.get_node("大厅居民") as Node3D
	var original := actor.global_position
	panel._seek(0.0)
	panel._add_actor_clip(0)
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	suite.modules.level._forward_3d_gui_input(camera, escape)
	await frames(tree, 5)
	check(panel._data().clips.size() == 2, "cancelling the point picker does not add a partial clip")
	panel._add_actor_clip(1)
	camera.look_at_from_position(Vector3(4, 5, 5), Vector3(0, 0, -2))
	check(pick(suite, camera, Vector3(1.5, 0, -3)), "native 3D callback consumes the waypoint pick")
	await frames(tree, 6)
	var move_id: String = panel._clip_id
	check(panel._clip(panel._data()).point.distance_to(Vector3(1.5, 0, -3)) < 0.06, "point pick stores the selected ground position")
	panel._begin_pick("via")
	camera.look_at_from_position(Vector3(4, 5, 5), Vector3(0, 0, -2))
	pick(suite, camera, Vector3(-1, 0, -2.5))
	await frames(tree, 5)
	check(panel._clip(panel._data()).via.size() == 1, "append an intermediate route point")
	panel._seek(2.1)
	panel._add_actor_clip(2)
	camera.look_at_from_position(Vector3(4, 5, 5), Vector3(0, 0, -2))
	pick(suite, camera, Vector3(0, 0, 1))
	await frames(tree, 5)
	panel._seek(2.2)
	panel._add_actor_clip(3)
	await frames(tree)
	var names := DATA.motion_names(actor)
	check("walk" in names and "idle" in names and panel._clip(panel._data()).kind == "action", "select an actual built-in NPC animation")
	panel._update_clip("motion", "idle")
	await frames(tree)
	panel._seek(1.0)
	var preview_actor: Node3D = panel._preview._duplicate.get_node("大厅居民")
	var preview_motion := DATA.motion_player(preview_actor)
	check(preview_actor.get_script() == null and actor.global_position.is_equal_approx(original) and not preview_actor.global_position.is_equal_approx(original), "preview scrubs a detached copy without modifying the authored NPC")
	check(preview_motion != null and preview_motion.assigned_animation == "walk", "walking animation is sampled mid-move")
	if DisplayServer.get_name() == "headless":
		var original_size: Vector2i = suite.window.size
		var original_scale: float = suite.display_adapter.scale_factor
		suite.display_adapter.apply_scale(1.0)
		suite.window.size = Vector2i(1040, 700)
		await frames(tree, 8)
		var tracks: Rect2 = panel._timeline.get_parent().get_global_rect()
		var preview_rect: Rect2 = panel._preview.get_global_rect()
		check(tracks.end.y <= preview_rect.position.y, "the timeline is visible above the preview")
		check(preview_rect.end.y <= suite.window.size.y + 1.0, "timeline and preview both fit the minimum window height")
		suite.display_adapter.apply_scale(original_scale)
		suite.window.size = original_size
	panel._seek(2.6)
	check(panel._preview._sampler.shot.label == "镜头" and is_equal_approx(panel._preview._sampler.shot.start, 2.0), "scrubbing displays the second shot")
	check(preview_actor.global_position.distance_to(Vector3(1.5, 0, -3)) < 0.06 and preview_motion.assigned_animation == "idle", "scrubbing shows destination and selected action")
	panel._seek(0.0)
	check(preview_actor.global_position.is_equal_approx(original), "scrub backwards reconstructs the initial NPC pose")
	panel._toggle_play()
	await frames(tree, 4)
	check(panel._time > 0.0 and panel._playing, "play from the current time")
	panel._toggle_play()
	var paused: float = panel._time
	await frames(tree)
	check(not panel._playing and is_equal_approx(panel._time, paused), "pause retains the current frame")
	var capture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture = arg.trim_prefix("--capture-dir=")
	if not capture.is_empty():
		suite.window.size = Vector2i(1152, 800)
		panel._seek(1.3)
		panel._select_clip(move_id)
		await frames(tree, 15)
		var image: Image = suite.window.get_texture().get_image()
		check(image != null and not image.is_empty() and image.save_png(capture.path_join("performance-timeline.png")) == OK, "capture rendered timeline and map preview")
	panel.stop_preview()
	check(not is_instance_valid(panel._preview._duplicate) and actor.global_position.is_equal_approx(original), "stop preview discards the copy")
	var graph: Resource = world.level_logic
	graph.nodes.assign([
		{"id": "enter", "kind": "room_enter", "params": {"room": "entry", "once": true}},
		{"id": "play", "kind": "play_performance", "params": {"performance": key}},
		{"id": "next", "kind": "objective", "params": {"text": "演出结束"}},
	])
	graph.edges.assign([
		{"id": "enter_play", "from": "enter", "from_port": "then", "to": "play", "to_port": "run"},
		{"id": "play_next", "from": "play", "from_port": "completed", "to": "next", "to_port": "run"},
	])
	suite.level_panel._performance_button.button_pressed = false
	var logic: Control = suite.level_panel.logic_panel
	logic.selected_id = "play"
	logic._show_parameters()
	check(logic._fields.performance.get_item_metadata(logic._fields.performance.selected) == key, "graph dropdown binds by stable ID and shows the sequence name")
	check(graph.validate().is_empty() and graph.validate_bindings(world).is_empty(), "native Room-to-performance graph validates")
	panel._save()
	await frames(tree, 6)
	var saved: Node = ResourceLoader.load(fixture, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(saved.performances.size() == 1 and saved.performances[0].id == key and saved.performances[0].clips.size() == 5, "save and reopen the original asset format with exact clip data")
	check(saved.get_node("大厅居民").position.is_equal_approx(original), "native save retains the original NPC pose")
	saved.free()
	print("PERFORMANCE FIXTURE: ", fixture)
	print("PERFORMANCE EDITOR: ", checks - failures, "/", checks)
	tree.quit(0 if failures == 0 else 1)
