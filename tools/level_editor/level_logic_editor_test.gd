@tool
extends RefCounted
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const LOGIC := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_logic_graph.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)

func frames(tree: SceneTree, count := 8) -> void:
	for i in count: await tree.process_frame

func add(panel: Control, kind: String, at: Vector2) -> String:
	panel.search.text = kind; panel.node_category.select(0); panel._filter_choices()
	panel._add_position = at; panel._add_choice()
	return panel.selected_id

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(60, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.7, true).timeout
	var path := "res://tools/level_editor/.level_logic_editor_%d.tscn" % OS.get_process_id()
	var source := WORLD.new(); source.name = "SandboxLogic"; source.level_id = "2"; source.world_id = "editor_logic"; source.start_room_id = ""
	source.topology = GRAPH.new(); source.topology.graph_id = "editor_topology"; source.topology.graph_kind = "topology"
	source.events = GRAPH.new(); source.events.graph_id = "editor_events"
	source.level_logic = LOGIC.new(); source.level_logic.graph_id = "editor_level_logic"
	for id in ["guide", "task_only"]:
		var npc: Node3D = load("res://addons/godot_level_editor/scenes/narrative/npc.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		npc.name = id; npc.object_id = id; npc.display_name = "关卡接待员" if id == "guide" else "任务专属角色"
		if id == "task_only":
			var profile := PROFILE.new(); profile.lifetime = "task"; profile.task_id = "1001001"; npc.set_meta(PROFILE.META, profile)
		FACTORY.add_owned(source, npc, source)
	check(FACTORY.save_scene(source, path) == OK, "editor fixture saves an isolated sandbox scene")
	source.free()
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	for attempt in 100:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path: break
		if attempt % 20 == 19: EditorInterface.open_scene_from_path(path)
		await tree.create_timer(0.05, true).timeout
	var world := EditorInterface.get_edited_scene_root()
	if world == null or world.scene_file_path != path: check(false, "temporary authored sandbox opens after editor layout loading"); tree.quit(1); return
	suite.level_panel.bind_scene(world); suite.open_tab("关卡图")
	await frames(tree, 12)
	var panel: Control = suite.level_panel.logic_panel
	check(suite.level_panel.mode_stack.current_tab == 1 and panel.world == world and panel.graph == world.level_logic, "level navigation opens its own permanent graph without a room topology mode")
	check(not panel.mode.visible and suite.level_panel.find_children("*", "Tree", true, false).is_empty(), "logic editing removes duplicated inventories and the old graph-mode selector")
	panel.search.text = ""; panel._filter_choices()
	var kinds := []
	for i in panel.choices.item_count: kinds.append(str(panel.choices.get_item_metadata(i)))
	check(kinds.has("npc_interact") and kinds.has("show_dialog") and kinds.has("task_accept") and kinds.has("delay") and kinds.has("branch") and kinds.has("mechanism_state"), "level graph reuses conversation, conditions, flow and mechanism nodes")
	check(not kinds.has("port") and not kinds.has("unlock") and not kinds.has("task_complete") and not kinds.has("task_fail") and not kinds.has("event_complete"), "room connections and task-only lifecycle actions are excluded")
	var npc_id := add(panel, "npc_interact", Vector2(60, 100))
	panel._show_parameters()
	check(not panel.graph.node_by_id(npc_id).params.has("task") and not panel._fields.has("task"), "permanent NPC triggers have no task acceptance scope field")
	var npc_picker: OptionButton = panel._fields.npc
	check(npc_picker.item_count == 2 and npc_picker.get_item_metadata(1) == "$world/guide", "NPC picker contains only the currently placed level-resident NPC")
	npc_picker.select(1); panel._apply_parameters()
	check(panel.graph.node_by_id(npc_id).params.npc == "$world/guide", "applying NPC selection persists a stable scene object reference")
	var accept_id := add(panel, "task_accept", Vector2(760, 100))
	panel._show_parameters()
	var task_picker: Control = panel._fields.task
	check(task_picker.has_method("value") and task_picker.search != null and task_picker.options.item_count > 1, "Accept Task notes expose a searchable catalog picker instead of a free-typed task ID")
	var chosen := str(task_picker.options.get_item_metadata(1))
	task_picker.select_id(chosen)
	var selected: Dictionary = task_picker.catalog.task_by_id(chosen)
	task_picker.search.text = selected.name; task_picker.refresh()
	check(task_picker.options.item_count >= 2 and task_picker.value() == chosen, "task search retains the selected task by stable ID")
	var only_first := true
	for i in range(1, task_picker.options.item_count):
		var task: Dictionary = task_picker.catalog.task_by_id(str(task_picker.options.get_item_metadata(i)))
		only_first = only_first and task_picker.catalog.event_tasks(str(task.event_id))[0].task_id == task.task_id and task.level_id == "2"
	check(only_first, "acceptance choices are first tasks for the current level, with subsequent tasks handled automatically")
	panel._apply_parameters()
	check(panel.graph.node_by_id(accept_id).params.task == chosen, "applying notes persists the chosen task ID")
	var delay_id := add(panel, "delay", Vector2(410, 100))
	panel.connect_ports(StringName(npc_id), 0, StringName(delay_id), 0)
	panel.connect_ports(StringName(delay_id), 0, StringName(accept_id), 0)
	check(panel.graph.edges.size() == 2 and panel.graph.validate().is_empty(), "level graph uses the same typed execution wires as task and mechanism graphs")
	panel.undo.undo()
	check(panel.graph.edges.size() == 1, "graph wire edits remain undoable")
	panel.undo.redo()
	check(panel.graph.edges.size() == 2, "graph wire edits remain redoable")
	var before: Dictionary = panel.graph.snapshot()
	check(panel.save_graph() and not panel.dirty, "Save Graph saves embedded logic in the level scene")
	var saved: Node = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	check(saved.level_logic.node_by_id(npc_id).params.npc == "$world/guide" and saved.level_logic.node_by_id(accept_id).params.task == chosen and saved.level_logic.edges == before.edges, "reopening the scene retains NPC binding, accepted task, and graph wires")
	saved.free()
	panel.save_reload()
	check(panel.graph.edges == before.edges and panel.graph.nodes == before.nodes, "Save and Reload preserves permanent node parameters and IDs")
	var task_panel: Control = suite.task_graph
	task_panel.search.text = "task_accept"; task_panel._filter_choices()
	check(task_panel.choices.item_count == 0, "task graph does not expose the level-only Accept Task node")
	if OS.get_cmdline_user_args().has("--capture"):
		suite.window.size = Vector2i(1504, 1000)
		await panel.fit_graph()
		panel.selected_id = accept_id; panel._show_parameters()
		await tree.create_timer(0.35, true).timeout
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png("res://docs/level_editor/level_logic_2026-11-15/关卡图_接受任务.png")
		panel.selected_id = npc_id; panel._show_parameters()
		await tree.create_timer(0.2, true).timeout
		RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png("res://docs/level_editor/level_logic_2026-11-15/关卡图_常驻NPC.png")
		check(suite.window.size == Vector2i(1504, 1000), "permanent graph and notes fit the standard rendered workspace")
		check(not panel.parameters.get_parent().get_h_scroll_bar().visible, "long task names fit the notes sidebar without horizontal clipping")
	panel.dirty = false
	suite.level_panel.set_mode(0)
	EditorInterface.close_scene()
	await frames(tree)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("LEVEL LOGIC EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
