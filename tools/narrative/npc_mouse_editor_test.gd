@tool
extends RefCounted
const DEFINITION := preload("res://addons/godot_level_editor/modules/enemy_editor/runtime/enemy_definition.gd")

func fixture(prefix: String) -> Resource:
	var value := DEFINITION.new()
	value.display_name = "鼠标连线检查 " + prefix
	value.initial_state = prefix + "_a"
	for suffix in ["a", "b"]:
		value.states.append({"id": prefix + "_" + suffix, "label": "待机 " + suffix, "behavior": "idle", "speed": 0.0, "duration": 1.0, "scan_degrees": 0.0})
	value.layout.nodes = {prefix + "_a": Vector2(40, 140), prefix + "_b": Vector2(600, 140)}
	return value

func run(suite: EditorPlugin, input: RefCounted) -> void:
	var folder := "res://tools/narrative/.npc_mouse_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "/first.tres"
	var other_path := folder + "/second.tres"
	input.check(ResourceSaver.save(fixture("first"), path) == OK and ResourceSaver.save(fixture("second"), other_path) == OK, "two isolated NPC definitions save valid stable state IDs")
	suite.open_tab("敌人")
	var panel: Control = suite.modules.enemies.panel
	panel.request_open(path)
	suite.asset_panels["敌人"].set_mode(1)
	panel.workspaces.current_tab = 1
	await input.frames(20)
	await input.click(panel.graph, Vector2(15, 140))
	await input.drag(panel.graph, "s_first_a", 0, "s_first_b", 0)
	input.check(panel.definition.transitions.size() == 1 and panel.definition.transitions[0].from == "first_a" and panel.definition.transitions[0].to == "first_b", "NPC mouse drag creates the actual state transition")
	if panel.definition.transitions.size() != 1: suite.get_tree().quit(1); return
	input.check(panel.definition.validate().is_empty(), "mouse-created NPC transition retains valid ports, event and conditions")
	await input.click(input.button(panel, "撤销"))
	input.check(panel.definition.transitions.is_empty(), "NPC GUI Undo removes the transition")
	await input.click(input.button(panel, "重做"))
	input.check(panel.definition.transitions.size() == 1, "NPC GUI Redo restores the transition")
	await input.click(input.button(panel, "+ 搜索节点"))
	input.check(panel.search_dialog.visible, "NPC GUI opens behavior search")
	await input.type_text(panel.search_edit, "idle")
	input.check(panel.search_results.item_count == 1, "NPC English search isolates the idle behavior")
	await input.click(panel.search_results, panel.search_results.get_item_rect(0).get_center(), true)
	input.check(panel.definition.states.size() == 3 and panel.selected_state == "state1", "NPC double click creates a new stable state ID")
	# Only layout is arranged directly; transition creation remains a mouse drag.
	panel.definition.layout.nodes.state1 = Vector2(40, 430)
	panel._render_graph()
	await input.frames(12)
	var bar: TabBar = panel.tabs.get_tab_bar()
	await input.click(bar, bar.get_tab_rect(0).get_center())
	var field: LineEdit
	for child in panel.details.get_children():
		if child is LineEdit: field = child; break
	if field == null:
		input.check(false, "NPC state name field is visible")
		suite.get_tree().quit(1); return
	await input.click(field)
	var view := field.get_viewport()
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_A; key.meta_pressed = OS.get_name() == "macOS"; key.ctrl_pressed = OS.get_name() != "macOS"; key.pressed = down
		view.push_input(key, true)
	await input.press_key(view, KEY_BACKSPACE)
	var name_text := "连线检查状态"
	for i in name_text.length(): await input.press_key(view, KEY_NONE, name_text.unicode_at(i))
	await input.press_key(view, KEY_ENTER)
	input.check(panel.definition.state_by_id("state1").label == name_text, "NPC typing and Enter rename the label without changing the state ID")
	await input.click(input.button(panel, "保存"))
	input.check(not panel.dirty and panel.status.text.begins_with("已保存"), "NPC GUI Save accepts the edited graph without a task identifier")
	var saved: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	input.check(saved.transitions.size() == 1 and saved.states.size() == 3 and saved.state_by_id("state1").label == name_text, "NPC disk reload retains dragged transition and edited label")
	var saved_hash := FileAccess.get_sha256(path)
	await input.capture(suite.window, "NPC鼠标连线")
	panel.request_open(other_path)
	await input.frames(16)
	input.check(panel.file_path == other_path and panel.definition.initial_state == "second_a" and not panel.discard_dialog.visible, "NPC opens the second definition without stale state ownership")
	await input.click(panel.graph, Vector2(15, 140))
	await input.drag(panel.graph, "s_second_a", 0, "s_second_b", 0)
	await input.click(input.button(panel, "保存"))
	var other: Resource = ResourceLoader.load(other_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	input.check(not panel.dirty and other.transitions.size() == 1 and other.transitions[0].from == "second_a", "second NPC definition also supports mouse wiring and saving")
	input.check(FileAccess.get_sha256(path) == saved_hash, "editing the second NPC definition preserves the first file")
	print("NPC MOUSE WIRING: %d checks, %d failures" % [input.checks, input.failures])
	suite.get_tree().quit(1 if input.failures else 0)
