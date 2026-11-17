@tool
extends Node
const ROOT := "res://addons/godot_level_editor"
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const GROUPS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
var output := ""
var hold_camera := false
var view_camera: Camera3D

func _process(_delta: float) -> void:
	if hold_camera and is_instance_valid(view_camera):
		view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		view_camera.size = 31
		view_camera.global_position = Vector3(23, 19, 25)
		view_camera.look_at(Vector3(0, 0.8, -1))

func frames(count := 12) -> void:
	for i in count: await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout

func save_view(name: String, viewport: Viewport) -> void:
	var result := viewport.get_texture().get_image().save_png(output + "/" + name + ".png")
	if result != OK: push_error("Capture failed: " + name)
	else: print("MEDIA_SAVED: ", name)

func run(entry: EditorPlugin) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--media-output="): output = arg.trim_prefix("--media-output=")
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(150).timeout.connect(func(): get_tree().quit(2))
	print("MEDIA_STEP: workspace")
	await frames()
	var suite = get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
	suite.prepare_all_pages()
	print("MEDIA_STEP: showcase")
	_make_showcase()
	EditorInterface.open_scene_from_path("res://content/scenes/levels/whitebox_courtyard.tscn")
	EditorInterface.set_main_screen_editor("3D")
	await frames(30)
	view_camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	hold_camera = true
	suite.window.hide()
	EditorInterface.get_selection().clear()
	await frames(20)
	save_view("01_whitebox_editor", EditorInterface.get_base_control().get_window())
	var level = suite.modules.level
	level.radial_tool.open_wheel(view_camera)
	level.radial_tool.menu.select_category(1)
	level.radial_tool.menu.open_submenu()
	await frames(20)
	save_view("02_quick_add_wheel", EditorInterface.get_base_control().get_window())
	level.radial_tool.cancel()
	hold_camera = false
	print("MEDIA_STEP: mechanisms")
	suite.open_tab("机关")
	var mechanisms = suite.asset_panels["机关"]
	mechanisms.select_asset(ROOT + "/scenes/mechanisms/double_door.tscn")
	EditorInterface.open_scene_from_path(ROOT + "/scenes/mechanisms/double_door.tscn")
	await frames(25)
	suite.modules.mechanisms.panel.bind_scene(EditorInterface.get_edited_scene_root())
	mechanisms._activate(ROOT + "/scenes/mechanisms/double_door.tscn")
	suite.modules.mechanisms.panel._fit_graph(false)
	await frames(15)
	save_view("03_mechanism_graph", suite.window)
	suite.open_tab("敌人")
	suite.asset_panels["敌人"].select_asset(ROOT + "/resources/enemies/samples_v1/human_medium_female.tres")
	await frames(20)
	save_view("04_npc_library", suite.window)
	_make_task(suite)
	await frames(20)
	suite.task_graph.fit_graph()
	await frames(15)
	save_view("05_task_graph", suite.window)
	suite.open_tab("天空")
	suite.sky_panel.open_preset(ROOT + "/resources/sky_presets/builtin/morning.tres")
	await frames(20)
	save_view("06_sky_editor", suite.window)
	reparent(get_tree().root)
	EditorInterface.set_plugin_enabled("godot_level_editor", false)
	await frames(5)
	print("MEDIA_EDITOR_OK")
	get_tree().quit()

func _make_showcase() -> void:
	var world: Node3D = load(ROOT + "/templates/empty_level.tscn").instantiate()
	world.name = "Courtyard"
	world.level_id = "2"
	world.world_id = "level_2"
	world.sky_preset = load(ROOT + "/resources/sky_presets/builtin/morning.tres")
	for key in ["topology", "events", "level_logic"]:
		var graph: Resource = world.get(key).duplicate(true)
		graph.graph_id = "showcase_" + str(key)
		world.set(key, graph)
	world.get_node("Whitebox/Floor").size = Vector3(32, 3.6, 26)
	world.get_node("PlayerSpawn").position = Vector3(0, 0.1, 8)
	var blocks := [
		["left_wall", Vector3(1, 3, 10), Vector3(-8, 1.5, -2)],
		["back_left", Vector3(6, 3, 0.7), Vector3(-5, 1.5, -6)],
		["back_right", Vector3(6, 3, 0.7), Vector3(5, 1.5, -6)],
		["lintel", Vector3(4, 0.8, 0.7), Vector3(0, 3.4, -6)],
		["raised_platform", Vector3(5, 1.4, 6), Vector3(6, 0.7, -2)],
		["steps", Vector3(3, 1.4, 4), Vector3(6, 0.7, 3)],
		["left_platform", Vector3(4, 0.6, 4), Vector3(-5, 0.3, 2)],
		["tower_left", Vector3(1.2, 4, 1.2), Vector3(-8, 2, -7)],
		["tower_right", Vector3(1.2, 4, 1.2), Vector3(8, 2, -7)]]
	for item in blocks:
		var block := FACTORY.block(world, str(item[0]), item[1], item[2])
		if item[0] == "steps": block.shape_kind = "stairs"
		GROUPS.group_new_node(world, block)
	for spec in [["double_door", Vector3(0, 0, -6)], ["button", Vector3(2.5, 0, 3.5)], ["pressure_plate", Vector3(0, 0.03, 1)]]:
		var mechanism: Node3D = load(ROOT + "/scenes/mechanisms/" + str(spec[0]) + ".tscn").instantiate()
		mechanism.position = spec[1]
		FACTORY.add_owned(world, mechanism, world)
		GROUPS.group_new_node(world, mechanism)
	for spec in [["v1_human_medium_female", Vector3(-4.5, 0.6, 2)], ["v1_human_medium_male", Vector3(5.2, 1.4, -2)]]:
		var actor: Node3D = load(ROOT + "/scenes/npcs/" + str(spec[0]) + ".tscn").instantiate()
		actor.position = spec[1]
		actor.rotation.y = 0.4
		FACTORY.add_owned(world, actor, world)
		GROUPS.group_new_node(world, actor)
	var path := "res://content/scenes/levels/whitebox_courtyard.tscn"
	FACTORY.save_scene(world, path)
	world.free()
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_registry.gd").saved(path)
	EditorInterface.get_resource_filesystem().scan()

func _make_task(suite: EditorPlugin) -> void:
	var catalog_script = load(ROOT + "/modules/godot_level_editor_suite/runtime/event_catalog.gd")
	var book: Dictionary = catalog_script.load_book()
	var event: Dictionary = book.catalog.add_event()
	event.display_name = "探索庭院"
	var task: Dictionary = book.catalog.add_task(str(event.event_id), "2")
	task.display_name = "等待片刻后完成"
	var graph = load(ROOT + "/modules/godot_level_editor_narrative/runtime/task_definition.gd").new()
	graph.graph_id = "showcase_task"
	graph.nodes.assign([{"id": "start", "kind": "start", "params": {}}, {"id": "wait", "kind": "delay", "params": {"seconds": 2.0, "scope": ""}}, {"id": "complete", "kind": "task_complete", "params": {"task": task.task_id}}])
	graph.positions = {"start": Vector2(60, 120), "wait": Vector2(420, 120), "complete": Vector2(800, 120)}
	graph.edges.assign([{"id": "edge_start", "from": "start", "from_port": "then", "to": "wait", "to_port": "run"}, {"id": "edge_end", "from": "wait", "from_port": "then", "to": "complete", "to_port": "run"}])
	var errors = graph.validate()
	assert(errors.is_empty(), str(errors))
	ResourceSaver.save(graph, str(task.graph_path))
	book.catalog.save_book()
	suite.event_panel.reload_book()
	suite.edit_task(task)
