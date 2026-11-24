@tool
extends RefCounted
# Node creation, editing and wiring use Window input, never connection signals/API.
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const LOGIC := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_logic_graph.gd")
const LEVEL_FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/factory.gd")
const STORE := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd")
var checks := 0
var failures := 0
var tree: SceneTree
var output := "res://docs/narrative_editor/task_toolbar_2026-11-16"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)

func frames(count := 8) -> void:
	for i in count: await tree.process_frame

func mouse(view: Viewport, at: Vector2, pressed: bool, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = at; event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed; event.double_click = double
	view.push_input(event, true)

func click(control: Control, at := Vector2(-1, -1), double := false) -> void:
	if not is_instance_valid(control):
		check(false, "mouse click target exists")
		return
	# A human scrolls offscreen parameters into view before clicking.
	var ancestor := control.get_parent()
	while ancestor != null and not ancestor is Window:
		if ancestor is ScrollContainer:
			for step in 18:
				var bounds: Rect2 = ancestor.get_global_rect()
				var rect := control.get_global_rect()
				if rect.position.y >= bounds.position.y and rect.end.y <= bounds.end.y: break
				var view := control.get_viewport()
				var position := bounds.get_center()
				if DisplayServer.get_name() != "headless": view.warp_mouse(position)
				var event := InputEventMouseButton.new()
				event.position = position
				event.button_index = MOUSE_BUTTON_WHEEL_DOWN if rect.end.y > bounds.end.y else MOUSE_BUTTON_WHEEL_UP
				event.pressed = true; event.factor = 1.0
				view.push_input(event, true)
				var release := event.duplicate() as InputEventMouseButton
				release.pressed = false
				view.push_input(release, true)
				await frames(3)
		ancestor = ancestor.get_parent()
	if at.x < 0: at = control.size / 2
	var point := control.get_global_transform_with_canvas() * at
	control.get_window().grab_focus()
	control.get_viewport().warp_mouse(point)
	await frames(3)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	control.get_viewport().push_input(motion, true)
	mouse(control.get_viewport(), point, true, double)
	await frames(2)
	mouse(control.get_viewport(), point, false)
	await frames()

func button(parent: Node, title: String) -> Button:
	for child in parent.find_children("*", "Button", true, false):
		if child.text == title and child.is_visible_in_tree(): return child
	return null

func press_key(view: Viewport, code: Key, unicode := 0) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.unicode = unicode; event.pressed = down
		view.push_input(event, true)
	await frames(2)

func type_text(field: LineEdit, value: String) -> void:
	await click(field)
	for i in value.length(): await press_key(field.get_viewport(), KEY_NONE, value.unicode_at(i))
	await frames()

func add_node(panel: Control, kind: String, position: Vector2, mechanism := false) -> String:
	var add_button := button(panel, "添加节点")
	if add_button == null: check(false, "visible add-node button exists"); return ""
	await click(add_button)
	var dialog: Window = panel._picker if mechanism else panel.picker
	var search: LineEdit = panel._search if mechanism else panel.search
	var choices: ItemList = panel._kinds if mechanism else panel.choices
	check(dialog.visible, "mouse click opens " + ("mechanism" if mechanism else "level") + " node search")
	await type_text(search, kind)
	var index := -1
	for i in choices.item_count:
		if str(choices.get_item_metadata(i)) == kind: index = i; break
	if index < 0: check(false, "typed search finds " + kind); dialog.hide(); return ""
	# Placement is fixture layout only; item activation still follows the UI path.
	if mechanism: panel._popup_position = position
	else: panel._add_position = position
	await click(choices, choices.get_item_rect(index).get_center(), true)
	var id: String = panel.selected_id
	var entry: Dictionary = panel.assembly.definition.find_node(id) if mechanism else panel.graph.node_by_id(id)
	check(not dialog.visible and entry.get("kind", "") == kind, "double click creates " + kind)
	return id

func drag(graph: GraphEdit, from: String, out_index: int, to: String, in_index: int) -> void:
	var a := graph.get_node_or_null(NodePath(from)) as GraphNode
	var b := graph.get_node_or_null(NodePath(to)) as GraphNode
	if a == null or b == null: check(false, "drag endpoints exist"); return
	if not a.is_visible_in_tree() or not b.is_visible_in_tree() or a.get_output_port_count() <= out_index or b.get_input_port_count() <= in_index:
		check(false, "drag endpoints expose visible native ports")
		return
	# Pan/zoom are view setup, not graph mutations.
	graph.zoom = 0.65
	graph.scroll_offset = Vector2(0, minf(a.position_offset.y, b.position_offset.y) * graph.zoom - 80)
	await frames(12)
	var start := a.get_global_transform_with_canvas() * a.get_output_port_position(out_index)
	var end := b.get_global_transform_with_canvas() * b.get_input_port_position(in_index)
	check(graph.get_global_rect().has_point(start) and graph.get_global_rect().has_point(end), "both actual ports are visible before mouse drag")
	print("[DRAG] ", from, ":", out_index, " ", start, " -> ", to, ":", in_index, " ", end)
	var view := graph.get_viewport()
	(view as Window).grab_focus()
	view.warp_mouse(start)
	await frames(3)
	var hover := InputEventMouseMotion.new()
	hover.position = start
	view.push_input(hover, true)
	mouse(view, start, true)
	await frames(3)
	for i in range(1, 13):
		var motion := InputEventMouseMotion.new()
		motion.position = start.lerp(end, float(i) / 12.0)
		motion.global_position = motion.position
		motion.relative = (end - start) / 12.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		view.warp_mouse(motion.position)
		view.push_input(motion, true)
		await frames(2)
	mouse(view, end, false)
	await frames(12)

func open_scene(path: String) -> Node:
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	for i in 160:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path: await frames(16); return root
		await tree.create_timer(0.05).timeout
	return null

func capture(window: Window, filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute(output)
	window.get_texture().get_image().save_png(output + "/" + filename + ".png")

func run(suite: EditorPlugin) -> void:
	tree = suite.get_tree()
	if DisplayServer.get_name() == "headless":
		print("LIVE MOUSE WIRING BLOCKED: requires a rendered, focused editor window")
		tree.quit(2); return
	tree.create_timer(180, true).timeout.connect(func(): print("LIVE WIRING TIMEOUT"); tree.quit(2))
	suite._make_visible(true)
	if OS.get_cmdline_user_args().has("--manual-focus"):
		suite.window.title = "连线检查（隔离工程）"
	# Window.size is physical pixels; controls and mouse coordinates are logical.
	var scale_factor := float(suite.window.get_meta("ui_display_scale", 1.0))
	suite.window.size = Vector2i(Vector2(1400, 850) * scale_factor)
	await tree.create_timer(0.6).timeout
	suite.window.grab_focus()
	await frames(12)
	if OS.get_cmdline_user_args().has("--manual-focus"):
		for attempt in 300:
			if suite.window.has_focus(): break
			await tree.create_timer(0.1).timeout
	if not suite.window.has_focus():
		print("LIVE MOUSE WIRING BLOCKED: unlock the desktop and bring this test editor to the foreground")
		tree.quit(2); return
	if OS.get_cmdline_user_args().has("--npc-wire"):
		await load("res://tools/narrative/npc_mouse_editor_test.gd").new().run(suite, self)
		return
	# Scenes are isolated fixtures, never user-authored sources.
	var folder := "res://tools/narrative/.live_wire_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder)
	var level_path := folder + "/level.tscn"
	var inherited := folder + "/inherited.tscn"
	FileAccess.open(inherited, FileAccess.WRITE).store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://addons/godot_level_editor/templates/empty_level.tscn" id="1"]\n[node name="MouseWiringLevel" instance=ExtResource("1")]\n')
	var world := await open_scene(inherited)
	if world == null: check(false, "level fixture opens"); tree.quit(1); return
	EditorInterface.save_scene_as(level_path, false)
	await frames(12)
	check(FileAccess.file_exists(level_path) and not str(world.level_id).is_empty(), "native Save As saves an isolated inherited map with a stable level ID")
	suite.open_tab("关卡")
	suite.level_panel.set_mode(1)
	await frames(20)
	var level: Control = suite.level_panel.logic_panel
	check(level.world == world and level.graph == world.level_logic, "native level editor binds the current scene without a map-card workflow")
	# Opening a scene activates the native editor. Focus the empty canvas before
	# starting assertions, as a user does when returning to the tool window.
	await click(level.canvas, Vector2(15, 140))
	await frames(12)
	var start := await add_node(level, "start", Vector2(40, 90))
	var constant := await add_node(level, "constant", Vector2(40, 320))
	var branch := await add_node(level, "branch", Vector2(540, 150))
	if start.is_empty() or constant.is_empty() or branch.is_empty(): tree.quit(1); return
	await drag(level.canvas, start, 0, branch, 0)
	check(level.graph.edges.size() == 1, "level event connection is created by mouse drag")
	await drag(level.canvas, constant, 0, branch, 1)
	check(level.graph.edges.size() == 2, "level boolean connection is created by mouse drag")
	await drag(level.canvas, constant, 0, branch, 0)
	check(level.graph.edges.size() == 2, "level rejects boolean into event input without corrupting wires")
	var card := level.canvas.get_node(NodePath(constant)) as GraphNode
	await click(card, Vector2(card.size.x / 2, 18))
	await click(level._fields.value)
	await click(button(level.parameters, "应用参数"))
	check(level.graph.node_by_id(constant).params.value, "level checkbox and Apply persist true through real UI events")
	await click(button(level, "撤销"))
	check(not level.graph.node_by_id(constant).params.value, "level mouse-click Undo reverses parameters")
	await click(button(level, "重做"))
	check(level.graph.node_by_id(constant).params.value, "level mouse-click Redo restores parameters")
	await click(button(level, "保存"))
	check(not level.dirty and level.status.text == "已保存关卡图", "level GUI Save accepts the connected graph without a local task ID")
	var saved: Node = ResourceLoader.load(level_path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	check(saved.level_logic.edges.size() == 2 and saved.level_logic.node_by_id(constant).params.value, "level disk reload retains mouse-created wires and parameter")
	saved.free()
	level.fit_graph(); await frames(12)
	await capture(suite.window, "关卡鼠标连线")

	var mechanism_path := folder + "/button.tscn"
	var root := FACTORY.standalone("button")
	root.definition.positions.component = Vector2(1050, 80)
	# A configured component reference belongs to fixture setup. Its wire is
	# still drawn through the native GraphEdit mouse path below.
	root.definition.nodes.append({"id": "object_fixture", "kind": "object", "params": {"object_id": "button"}})
	root.definition.positions.object_fixture = Vector2(40, 920)
	check(STORE.save_pair(root, mechanism_path).ok, "isolated single-button fixture saved")
	root.free()
	var assembly := await open_scene(mechanism_path)
	if assembly == null: check(false, "mechanism fixture opens"); tree.quit(1); return
	suite.open_tab("机关")
	suite.asset_panels["机关"].set_mode(1)
	var mechanism: Control = suite.modules.mechanisms.panel
	mechanism.bind_scene(assembly)
	await frames(20)
	await click(mechanism.graph, Vector2(15, 140))
	await frames(12)
	# Each native drag exercises a different typed port, including component binding.
	var bool_id := await add_node(mechanism, "bool", Vector2(40, 80), true)
	var not_id := await add_node(mechanism, "not", Vector2(540, 80), true)
	var event_id := await add_node(mechanism, "interacted", Vector2(40, 350), true)
	var action_id := await add_node(mechanism, "perform_action", Vector2(540, 350), true)
	var number_id := await add_node(mechanism, "number", Vector2(40, 620), true)
	var greater_id := await add_node(mechanism, "greater", Vector2(540, 620), true)
	var object_id := "object_fixture"
	var read_id := await add_node(mechanism, "read_power", Vector2(540, 920), true)
	if [bool_id, not_id, event_id, action_id, number_id, greater_id, object_id, read_id].has(""): tree.quit(1); return
	await drag(mechanism.graph, bool_id, 0, not_id, 0)
	check(assembly.definition.edges.size() == 1, "mechanism boolean connection is created by mouse drag")
	await drag(mechanism.graph, event_id, 0, action_id, 0)
	check(assembly.definition.edges.size() == 2, "mechanism event connection is created by mouse drag")
	await drag(mechanism.graph, number_id, 0, greater_id, 0)
	check(assembly.definition.edges.size() == 3, "mechanism numeric connection is created by mouse drag")
	await drag(mechanism.graph, object_id, 0, read_id, 0)
	check(assembly.definition.edges.size() == 4, "mechanism object connection is created by mouse drag")
	await click(button(mechanism, "保存"))
	check(mechanism.dirty and mechanism.status.text.contains("输入端口未连接") and mechanism.status.text.contains(greater_id + ".b"), "mechanism Save explains the remaining required input instead of accepting an incomplete graph")
	await drag(mechanism.graph, number_id, 0, read_id, 0)
	check(assembly.definition.edges.size() == 4, "mechanism rejects numeric data into object input")
	check(not str(assembly.definition.find_node(event_id).params.object_id).is_empty() and not str(assembly.definition.find_node(action_id).params.action).is_empty(), "component event/action defaults bind the actual fixture component")
	check(str(assembly.definition.find_node(object_id).params.object_id) == "button", "connected object fixture retains its actual component ID")
	await click(button(mechanism, "撤销"))
	check(assembly.definition.edges.size() == 3, "mechanism GUI Undo reverses the last wire")
	await click(button(mechanism, "重做"))
	check(assembly.definition.edges.size() == 4, "mechanism GUI Redo restores the last wire")
	await drag(mechanism.graph, number_id, 0, greater_id, 1)
	check(assembly.definition.edges.size() == 5, "mouse drag fills the remaining numeric input")
	mechanism.graph.scroll_offset = Vector2(0, -100)
	await frames(12)
	var bool_card := mechanism.graph.get_node(NodePath(bool_id)) as GraphNode
	await click(bool_card, Vector2(bool_card.size.x / 2, 18))
	var checkbox: CheckBox
	for child in mechanism.details.get_children():
		if child is CheckBox: checkbox = child; break
	if checkbox != null: await click(checkbox)
	check(assembly.definition.find_node(bool_id).params.value, "mechanism checkbox changes the selected node using mouse input")
	await click(button(mechanism, "保存"))
	check(not mechanism.dirty and mechanism.status.text.begins_with("已保存场景与图定义"), "mechanism GUI Save validates all four port types and object bindings")
	var restored: Node = STORE.load_pair(mechanism_path)
	check(restored.definition.edges.size() == 5 and restored.definition.find_node(object_id).params.object_id == "button" and restored.definition.find_node(bool_id).params.value, "mechanism disk reload retains dragged wires, edited value and component reference")
	restored.free()
	mechanism._fit_graph(false); await frames(12)
	await capture(suite.window, "机关鼠标连线")
	# Saved source switching must rebind both scene and graph, without stale ownership.
	await open_scene(level_path)
	suite.open_tab("关卡"); suite.level_panel.set_mode(1); await frames(16)
	check(level.world == EditorInterface.get_edited_scene_root() and level.graph.edges.size() == 2, "switching back rebinds the saved level graph")
	await open_scene(mechanism_path)
	suite.open_tab("机关"); suite.asset_panels["机关"].set_mode(1); await frames(16)
	check(mechanism.assembly == EditorInterface.get_edited_scene_root() and mechanism.assembly.definition.edges.size() == 5, "switching back rebinds the saved mechanism graph")
	print("LIVE MOUSE WIRING: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
