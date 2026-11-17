@tool
extends EditorPlugin
const ROOT := "res://addons/godot_level_editor/modules/"
const TASK := preload(ROOT + "godot_level_editor_narrative/runtime/task_definition.gd")
const LOGIC := preload(ROOT + "godot_level_editor/runtime/level_logic_graph.gd")
const LEVELS := preload(ROOT + "godot_level_editor_suite/runtime/level_catalog.gd")
const LIBRARY := preload(ROOT + "godot_level_editor_narrative/runtime/dialogue_library.gd")
var suite: EditorPlugin
var checks := 0
var failures := 0
var task_id := ""
var event_id := ""
var level_id := ""
var comment_id := ""
var qa_path := "res://content/scenes/levels/narrative_structure_qa.tscn"
var dialogue_path := "res://content/tables/narrative_structure_qa.xlsx"
var report := {"checks": [], "existing_graphs": []}

func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has("--narrative-structure-qa") or OS.get_cmdline_user_args().has("--narrative-migrated-qa"):
		get_tree().create_timer(115, true).timeout.connect(func(): print("NARRATIVE_STRUCTURE_TIMEOUT"); get_tree().quit(2))
		_run.call_deferred()

func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
	report.checks.append({"ok": ok, "step": label})
	return ok

func finish() -> void:
	if FileAccess.file_exists("res://qa_playing.flag"): DirAccess.remove_absolute("res://qa_playing.flag")
	report["passed"] = checks - failures; report["failed"] = failures
	report["user_dir"] = OS.get_user_data_dir()
	var file := FileAccess.open("user://narrative-structure-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("NARRATIVE_STRUCTURE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func open_scene(path: String) -> Node:
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	for attempt in 120:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path: await frames(8); return root
		await get_tree().create_timer(0.03).timeout
	return null

func add(panel: Control, kind: String, at: Vector2) -> String:
	panel._show_picker()
	panel.search.text = kind; panel._filter_choices()
	for i in panel.choices.item_count:
		if panel.choices.get_item_metadata(i) == kind: panel.choices.select(i); break
	panel._add_position = at
	panel.picker.confirmed.emit()
	panel.picker.hide()
	return panel.selected_id

func params(panel: Control, id: String, values: Dictionary) -> void:
	panel.selected_id = id
	panel._show_parameters()
	for key in values:
		var field: Control = panel._fields.get(key)
		if field is LineEdit: field.text = str(values[key])
		elif field is OptionButton:
			for i in field.item_count:
				if str(field.get_item_metadata(i)) == str(values[key]): field.select(i); break
		elif field is CheckBox: field.button_pressed = bool(values[key])
	panel._apply_parameters()

func wire(panel: Control, from: String, output: int, to: String, input: int) -> void:
	if DisplayServer.get_name() == "headless":
		panel.canvas.connection_request.emit(StringName(from), output, StringName(to), input)
		return
	var a: GraphNode = panel.canvas.get_node(NodePath(from))
	var b: GraphNode = panel.canvas.get_node(NodePath(to))
	# Wait in seconds: the reveal/layout animation can outlast many Metal frames.
	await get_tree().create_timer(0.4).timeout
	var bounds := Rect2(a.position_offset, a.size).merge(Rect2(b.position_offset, b.size))
	panel.canvas.zoom = clampf(minf((panel.canvas.size.x - 100) / bounds.size.x, (panel.canvas.size.y - 150) / bounds.size.y), 0.25, 0.65)
	panel.canvas.scroll_offset = bounds.position * panel.canvas.zoom - Vector2(40, 100)
	suite.window.grab_focus(); await get_tree().create_timer(0.2).timeout
	var start := a.get_global_transform_with_canvas() * a.get_output_port_position(output)
	var end := b.get_global_transform_with_canvas() * b.get_input_port_position(input)
	print("[NATIVE_DRAG] ", from, ":", output, " ", start, " -> ", to, ":", input, " ", end)
	var view := panel.get_viewport()
	view.warp_mouse(start); await get_tree().create_timer(0.08).timeout
	var hover := InputEventMouseMotion.new(); hover.position = start; hover.global_position = start; view.push_input(hover, true)
	var down := InputEventMouseButton.new(); down.position = start; down.global_position = start; down.button_index = MOUSE_BUTTON_LEFT; down.button_mask = MOUSE_BUTTON_MASK_LEFT; down.pressed = true
	view.push_input(down, true); await get_tree().create_timer(0.06).timeout
	for i in range(1, 13):
		var motion := InputEventMouseMotion.new(); motion.position = start.lerp(end, float(i) / 12); motion.global_position = motion.position; motion.relative = (end - start) / 12; motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		view.warp_mouse(motion.position); view.push_input(motion, true); await get_tree().create_timer(0.025).timeout
	await get_tree().create_timer(0.1).timeout
	print("[NATIVE_DRAG_END] mouse=", view.get_mouse_position(), " input=", b.get_global_transform_with_canvas() * b.get_input_port_position(input))
	var release := InputEventMouseButton.new(); release.position = end; release.global_position = end; release.button_index = MOUSE_BUTTON_LEFT; release.button_mask = 0; release.pressed = false
	view.push_input(release, true); await get_tree().create_timer(0.2).timeout

func _run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("GLEStructureNarrative"):
		push_error("Run narrative structure checks in an isolated project with a dedicated GLEStructureNarrative user directory.")
		get_tree().quit(2); return
	qa_path = "res://content/scenes/levels/narrative_qa_%d.tscn" % OS.get_process_id()
	dialogue_path = "res://content/tables/narrative_qa_%d.xlsx" % OS.get_process_id()
	for attempt in 500:
		suite = get_tree().get_first_node_in_group("godot_level_editor_editor_suite")
		if suite != null: break
		await get_tree().process_frame
	if not check(suite != null, "managed suite starts in the isolated project"): finish(); return
	suite.show_window(); await frames(10)
	if OS.get_cmdline_user_args().has("--narrative-migrated-qa"):
		await run_migrated()
		return
	check(not suite._prepared_pages.has("事件与任务") and not suite._prepared_pages.has("台本"), "normal startup keeps unvisited event and dialogue pages lazy")
	suite.open_tab("关卡"); await frames()
	check(not suite._prepared_pages.has("事件与任务"), "opening native level logic does not pre-create event tables")
	# Native inherited scene artifact; registration occurs through Godot Save As.
	var temporary := "res://qa_inherited_%d.tscn" % OS.get_process_id()
	var text := '[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://addons/godot_level_editor/templates/empty_level.tscn" id="1"]\n[node name="NarrativeQA" instance=ExtResource("1")]\n'
	FileAccess.open(temporary, FileAccess.WRITE).store_string(text)
	var world := await open_scene(temporary)
	if not check(world != null, "new inherited blank map opens natively"): finish(); return
	EditorInterface.save_scene_as(qa_path, false)
	await frames(16)
	world = EditorInterface.get_edited_scene_root()
	level_id = str(world.get("level_id"))
	var book := LEVELS.load_book()
	report["native_registration"] = {"level_id": level_id, "file_exists": FileAccess.file_exists(qa_path), "levels": book.catalog.levels if book.catalog != null else [], "errors": book.errors}
	if not check(FileAccess.file_exists(qa_path) and not level_id.is_empty() and book.catalog != null and book.catalog.by_id(level_id).get("scene_path", "") == qa_path, "native Save As registers the new map ID for task selection"): finish(); return
	check(load(qa_path).get_state().get_base_scene_state() != null, "native map keeps the inherited template relation")
	check(suite.event_panel == null, "native save works before the event page is visited")
	# Add a real interactable in the editor, keeping it owned by this new map.
	var npc := preload(ROOT + "godot_level_editor_narrative/runtime/npc.gd").new()
	npc.name = "QAContact"; npc.object_id = "qa_contact"; npc.display_name = "联络员"
	world.add_child(npc); npc.owner = world; npc.position = Vector3(0, 0, 1.2)
	EditorInterface.mark_scene_as_unsaved()
	# Dialogue authoring uses the real new/edit/save/open callbacks.
	suite.open_tab("台本"); await frames()
	var dialogue: Control = suite.modules.narrative.dialogue_panel
	var original_dialogue := FileAccess.get_sha256("res://content/tables/dialogues.xlsx")
	dialogue._new()
	check(dialogue.dirty and dialogue.library.xlsx_path.is_empty(), "new dialogue is an unsaved author draft, separate from the project workbook")
	comment_id = str(dialogue.current_comment().id)
	dialogue.edit_line()
	dialogue.detail_speaker.text = "联络员"; dialogue.detail_content.text = "欢迎进入检查关卡。"
	dialogue.detail_duration.value = 0.1
	dialogue.detail_dialog.confirmed.emit(); dialogue.detail_dialog.hide()
	dialogue.add_line()
	dialogue.set_dialogue_mode(dialogue.li, "stationary")
	dialogue.edit_line(); dialogue.detail_speaker.text = "联络员"; dialogue.detail_content.text = "按 F 完成对话。"
	dialogue.detail_dialog.confirmed.emit(); dialogue.detail_dialog.hide()
	check(dialogue.current_comment().lines.size() == 2 and dialogue.current_comment().lines[1].dialogue_mode == "stationary", "dialogue detail editor authors free and stationary lines")
	dialogue.undo.undo(); dialogue.undo.redo()
	dialogue.save()
	check(dialogue.file.visible and dialogue._mode == "save", "first Save opens the XLSX destination picker")
	dialogue.file.hide(); dialogue.file.file_selected.emit(dialogue_path)
	if not check(not dialogue.dirty and FileAccess.file_exists(dialogue_path), "new dialogue saves under content/tables"): finish(); return
	check(FileAccess.get_sha256("res://content/tables/dialogues.xlsx") == original_dialogue, "saving a new dialogue leaves the existing project workbook intact")
	dialogue._mode = "open"; dialogue.file.file_selected.emit(dialogue_path)
	check(dialogue.current_comment().id == comment_id and dialogue.current_comment().lines.size() == 2, "dialogue reopens with stable comment/line IDs and modes")
	# Event and task creation use the actual form and native level picker.
	suite.open_tab("事件与任务"); await frames()
	var events: Control = suite.event_panel
	var old_tasks: Array = events.catalog.tasks.duplicate(true)
	events.add_event(); event_id = events.selected_id
	events.add_task()
	var level_picker: Control = events.fields.level_id
	level_picker.select_id(level_id)
	check(level_picker.value() == level_id, "new task form can select the newly saved native map")
	events.fields.name.text = "qa_task"; events.fields.display_name.text = "检查任务"
	events.form.confirmed.emit()
	if not check(not events.form.visible and events.selected_kind == "task", "task form creates a task bound to exactly one native map"): finish(); return
	task_id = events.selected_id
	events.undo.undo(); events.undo.redo()
	check(events.catalog.task_by_id(task_id).level_id == level_id, "event/task undo and redo retain stable IDs and native level binding")
	events.save()
	check(not events.dirty and events.catalog.tasks.slice(0, old_tasks.size()) == old_tasks, "saving the new event preserves every existing authored task")
	var task: Dictionary = events.catalog.task_by_id(task_id)
	await suite.edit_task(task)
	var panel: Control = suite.task_graph
	check(suite._prepared_pages.has("任务图") and panel.bound_task_id == task_id and panel.graph.resource_path == task.graph_path and panel.world == world, "Edit lazily opens the correct task graph and binds its native map")
	check(str(task.graph_path).begins_with("res://content/resources/task_graphs/"), "new task graph is stored outside the plugin")
	panel._bind_library()
	check(panel.graph.table_file() == dialogue_path, "task binds the saved dialogue page workbook")
	var show_id := add(panel, "show_dialog", Vector2(400, 100))
	params(panel, show_id, {"dialog_id": comment_id})
	var done_id := add(panel, "dialog_completed", Vector2(80, 350))
	params(panel, done_id, {"dialog_id": comment_id})
	# Fixture layout leaves space between port hot zones, like a user arranging cards.
	panel.graph.positions.complete = Vector2(1100, 100)
	(panel.canvas.get_node("complete") as GraphNode).position_offset = Vector2(1100, 100)
	panel.canvas.connection_request.connect(func(a, ap, b, bp): print("[NATIVE_CONNECTION_REQUEST] ", a, ":", ap, " -> ", b, ":", bp))
	await wire(panel, "start", 0, show_id, 0); await wire(panel, done_id, 0, "complete", 0)
	print("[NATIVE_CONNECTIONS] ", panel.graph.edges)
	check(panel.graph.edges.size() == 2 and panel.graph.node_by_id(done_id).params.task == task_id, "palette, parameters and typed wiring preserve local task ownership")
	panel.undo.undo(); panel.undo.redo()
	check(panel.graph.edges.size() == 2, "task wire undo/redo restores both persisted endpoints")
	# Use the native SceneTree drag payload and the real drop receiver.
	var npc_id := add(panel, "npc_interact", Vector2(70, 600))
	var card: GraphNode = panel.canvas.get_node(NodePath(npc_id))
	var drop: Control
	for control in card.find_children("*", "Control", true, false):
		if control.is_in_group("godot_level_editor_reference_drop"): drop = control; break
	var payload := {"type": "nodes", "nodes": [npc.get_path()]}
	if check(drop != null and drop._can_drop_data(Vector2.ONE, payload), "task NPC reference accepts the native scene-tree drag payload"):
		drop._drop_data(Vector2.ONE, payload); await frames()
		check(panel.graph.node_by_id(npc_id).params.npc == "qa_contact", "drop receiver persists the actual scene NPC ID")
		panel.undo.undo(); panel.undo.redo()
	check(panel.save_graph(), "new task graph validates and saves through the editor")
	var task_hash: String = panel.graph.semantic_hash()
	var other := TASK.new(); other.graph_id = "qa_other"
	var other_path := "res://content/resources/task_graphs/qa_other.tres"
	ResourceSaver.save(other, other_path)
	panel.file_saving = false; panel._task_selected(other_path)
	check(panel.bound_task_id.is_empty() and panel.graph.resource_path == other_path, "opening an unregistered graph clears the previous task owner")
	panel._task_selected(task.graph_path)
	check(panel.bound_task_id == task_id and panel.graph.semantic_hash() == task_hash, "task graph reload restores registered ownership and saved data")
	if DisplayServer.get_name() != "headless":
		panel.fit_graph(); await get_tree().create_timer(0.4).timeout; RenderingServer.force_draw(false)
		suite.window.get_texture().get_image().save_png("user://narrative-structure-editor.png")
	# Permanent logic accepts the task; no automatic event shortcut is used.
	world.level_logic = LOGIC.new(); world.level_logic.graph_id = "qa_acceptance"
	world.level_logic.nodes.assign([{"id": "contact", "kind": "npc_interact", "params": {"npc": "$world/qa_contact"}}, {"id": "accept", "kind": "task_accept", "params": {"task": task_id}}])
	world.level_logic.edges.assign([{"id": "accept_wire", "from": "contact", "from_port": "then", "to": "accept", "to_port": "run"}])
	world.level_logic.positions = {"contact": Vector2(80, 100), "accept": Vector2(500, 100)}
	var probe := Node.new(); probe.name = "StructureRuntimeProbe"
	probe.set_script(preload("res://tools/narrative/structure_qa/runtime_probe.gd"))
	probe.set_meta("task_id", task_id); probe.set_meta("event_id", event_id); probe.set_meta("level_id", level_id)
	world.add_child(probe); probe.owner = world
	EditorInterface.mark_scene_as_unsaved()
	if DisplayServer.get_name() == "headless":
		EditorInterface.save_scene_as(qa_path, false)
		check(FileAccess.file_exists(qa_path), "native scene save persists acceptance logic, NPC and F6 observer")
	else:
		check(EditorInterface.save_scene() == OK, "native scene save persists acceptance logic, NPC and F6 observer")
	var output := "user://narrative-structure-runtime.json"
	if FileAccess.file_exists(output): DirAccess.remove_absolute(output)
	if DisplayServer.get_name() == "headless": ProjectSettings.set_setting("editor/run/main_run_args", "--headless")
	FileAccess.open("res://qa_playing.flag", FileAccess.WRITE).store_string(str(OS.get_process_id()))
	EditorInterface.play_current_scene()
	for attempt in 700:
		if FileAccess.file_exists(output): break
		await get_tree().create_timer(0.03).timeout
	check(EditorInterface.is_playing_scene(), "F6 starts the actual native level through the editor")
	if FileAccess.file_exists(output):
		var runtime: Variant = JSON.parse_string(FileAccess.get_file_as_string(output))
		report["runtime"] = runtime
		check(runtime is Dictionary and runtime.get("failures", 1) == 0, "F6 accepts the task with F, plays both dialogue modes and completes after the next F")
	else: check(false, "F6 observer returns an actual runtime result")
	EditorInterface.stop_playing_scene(); DirAccess.remove_absolute("res://qa_playing.flag"); await frames(12)
	check(not EditorInterface.is_playing_scene(), "stopping F6 leaves the editor and saved authoring data intact")
	finish()

func run_migrated() -> void:
	var path := "res://content/scenes/levels/9_editor_flow_test.tscn"
	var world := await open_scene(path)
	if not check(world != null and str(world.level_id) == "9", "migrated authored map opens with its original level ID"): finish(); return
	var catalog: Dictionary = load(ROOT + "godot_level_editor_suite/runtime/event_catalog.gd").load_book()
	var total: int = world.level_logic.nodes.size()
	var rows: Array = catalog.catalog.event_tasks("1004")
	for task in rows:
		await suite.edit_task(task)
		var panel: Control = suite.task_graph
		var before: String = panel.graph.semantic_hash()
		total += panel.graph.nodes.size()
		check(panel.world == world and panel.graph.validate().is_empty(), "migrated task opens against its original scene: " + str(task.task_id))
		check(panel.save_graph() and panel.graph.semantic_hash() == before, "migrated task saves without changing IDs, parameters or wires: " + str(task.task_id))
	var child: Resource = load("res://content/resources/task_graphs/editor_flow_test/child.tres")
	total += child.nodes.size()
	check(rows.size() == 3 and total == 47, "the existing demo retains 47 nodes across permanent logic, three tasks and child graph")
	# Repeat runs replace only this QA observer; never stack input drivers.
	for child_node in world.get_children():
		if child_node.get_script() == preload("res://tools/narrative/structure_qa/migrated_probe.gd"):
			world.remove_child(child_node); child_node.free()
	var driver := Node.new(); driver.name = "StructureMigratedDriver"
	driver.set_script(preload("res://tools/narrative/structure_qa/migrated_probe.gd"))
	world.add_child(driver); driver.owner = world
	EditorInterface.mark_scene_as_unsaved()
	if DisplayServer.get_name() == "headless": EditorInterface.save_scene_as(path, false)
	else: EditorInterface.save_scene()
	var output := "user://narrative-migrated-runtime.json"
	if FileAccess.file_exists(output): DirAccess.remove_absolute(output)
	if DisplayServer.get_name() == "headless": ProjectSettings.set_setting("editor/run/main_run_args", "--headless")
	FileAccess.open("res://qa_playing.flag", FileAccess.WRITE).store_string(str(OS.get_process_id()))
	EditorInterface.play_current_scene()
	for attempt in 2300:
		if FileAccess.file_exists(output): break
		await get_tree().create_timer(0.03).timeout
	if FileAccess.file_exists(output):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(output))
		report["migrated_runtime"] = data
		check(data is Dictionary and data.get("all_passed", false), "actual F6 drives the migrated 47-node demo to all twelve recorder checks")
	else: check(false, "migrated F6 returns a runtime result")
	EditorInterface.stop_playing_scene(); DirAccess.remove_absolute("res://qa_playing.flag"); await frames(10)
	check(not EditorInterface.is_playing_scene(), "migrated demo F6 stops normally")
	finish()
