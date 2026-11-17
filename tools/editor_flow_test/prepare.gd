extends Node
## Prepare NEW test data only. Deliberately creates no graph connections.
const TASK = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd")
const SPEC = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_nodes.gd")
const CATALOG = preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
const LIB = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd")
const FACTORY = preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const GROUPS = preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
const LEVEL = "res://content/scenes/levels/9_editor_flow_test.tscn"
const FOLDER = "res://content/resources/task_graphs/editor_flow_test"
const BOOK = "res://content/resources/narrative/editor_flow_test.xlsx"

func n(id: String, kind: String, p: Dictionary = {}) -> Dictionary:
	var params: Dictionary = SPEC.defaults(kind)
	params.merge(p, true)
	return {"id": id, "kind": kind, "params": params}

func save_graph(filename: String, nodes: Array, columns := 4) -> void:
	var graph = TASK.new()
	graph.graph_id = "editor_flow_" + filename
	graph.dialogue_xlsx = BOOK
	graph.nodes.assign(nodes)
	for i in nodes.size():
		graph.positions[nodes[i].id] = Vector2(60 + (i % columns) * 440, 80 + (i / columns) * 350)
	assert(graph.edges.is_empty())
	assert(ResourceSaver.save(graph, FOLDER + "/" + filename + ".tres") == OK)

func _ready() -> void:
	assert(not FileAccess.file_exists(FOLDER + "/equipment.tres"), "Preparation is one-time only; preserve mouse-created wires")
	DirAccess.make_dir_recursive_absolute(FOLDER)
	# Isolated dialogue workbook, never touches the user's main dialogue table.
	var lib = LIB.new()
	lib.match_speaker("测试员")
	lib.groups.assign([{"id":"flow_dialogue", "name":"编辑器流程测试", "comments":[
		{"id":"flow_accept", "name":"接取说明", "lines":[{"id":"flow_line_1", "speaker":"测试员", "text":"开始流程测试。先检查背包与穿着，再按两次按钮并走进门后的蓝色区域。按 F 继续。", "type":"对白", "dialogue_mode":"stationary", "duration":0.0}]},
		{"id":"flow_equipped", "name":"装备确认", "lines":[{"id":"flow_line_2", "speaker":"测试员", "text":"背包和穿着检查通过。按 F 继续，然后操作左侧按钮两次。", "type":"提示", "dialogue_mode":"stationary", "duration":0.0}]},
		{"id":"flow_done", "name":"测试完成", "lines":[{"id":"flow_line_3", "speaker":"测试员", "text":"区域、机关、并行汇合、变量和子图检查通过，测试任务完成。", "type":"提示", "dialogue_mode":"free", "duration":3.0}]}
	]}])
	assert(lib.write_xlsx(BOOK).is_empty())
	# Keep existing orphan graph resources intact by using a separate directory.
	var result = CATALOG.load_book()
	assert(result.errors.is_empty())
	var catalog = result.catalog
	var event = catalog.event_by_id("1004")
	assert(event.get("name") == "editor_flow_test")
	var first = catalog.task_by_id("1004001")
	assert(first.get("level_id") == "9")
	first.display_name = "检查背包与穿着"
	first.graph_path = FOLDER + "/equipment.tres"
	var second = catalog.add_task("1004", "9")
	second.name = "flow_mechanisms"; second.display_name = "按两次按钮并穿过门"; second.graph_path = FOLDER + "/mechanisms.tres"
	var third = catalog.add_task("1004", "9")
	third.name = "flow_parallel"; third.display_name = "等待流程检查完成"; third.graph_path = FOLDER + "/parallel.tres"
	assert(catalog.save_book().is_empty())
	var world = load(LEVEL).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var npcs = Node3D.new(); npcs.name = "NPCs"; FACTORY.add_owned(world, npcs, world); npcs.set_meta(&"godot_level_editor_content_group", "npc")
	var npc = load("res://addons/godot_level_editor/scenes/narrative/npc.tscn").instantiate()
	npc.name = "Tester"; npc.object_id = "flow_tester"; npc.display_name = "测试员"; npc.position = Vector3(0,0,0)
	FACTORY.add_owned(npcs, npc, world)
	var mechanisms = Node3D.new(); mechanisms.name = "Mechanisms"; FACTORY.add_owned(world, mechanisms, world); mechanisms.set_meta(&"godot_level_editor_content_group", "mechanism")
	for entry in [["button", "Button", Vector3(-2,0,-3)], ["single_door", "Door", Vector3(0,0,-5)]]:
		var object = load("res://addons/godot_level_editor/scenes/mechanisms/" + entry[0] + ".tscn").instantiate()
		object.name = entry[1]; object.object_id = "flow_" + entry[0]; object.instance_id = "flow_" + entry[0]; object.position = entry[2]
		FACTORY.add_owned(mechanisms, object, world)
	var rooms = Node3D.new(); rooms.name = "Rooms"; FACTORY.add_owned(world, rooms, world); rooms.set_meta(&"godot_level_editor_content_group", "room")
	var area = load("res://addons/godot_level_editor/scenes/level_editor/rooms/trigger_room.tscn").instantiate()
	area.name = "FinishArea"; area.room_id = "flow_finish"; area.display_name = "门后区域"; area.position = Vector3(0,1,-7); area.bounds_size = Vector3(4,2,3)
	FACTORY.add_owned(rooms, area, world)
	FACTORY.block(world, "finish_mark", Vector3(4,0.04,3), Vector3(0,0.02,-7))
	for entry in [["按钮按两次", Vector3(-2,2.2,-3)], ["穿过门进入区域", Vector3(0,3.6,-5)]]:
		var label = Label3D.new(); label.text = entry[0]; label.position = entry[1]; label.font_size = 40; label.pixel_size = 0.008; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		FACTORY.add_owned(world, label, world)
	world.level_logic.dialogue_xlsx = BOOK
	world.level_logic.nodes.assign([
		n("interact", "npc_interact", {"npc":"$world/flow_tester"}),
		n("intro", "show_dialog", {"dialog_id":"flow_accept"}),
		n("read", "dialog_completed", {"dialog_id":"flow_accept"}),
		n("accept", "task_accept", {"task":"1004001"})
	])
	for i in 4: world.level_logic.positions[world.level_logic.nodes[i].id] = Vector2(60 + (i % 2) * 600, 100 + (i / 2) * 350)
	assert(world.level_logic.edges.is_empty())
	assert(FACTORY.save_scene(world, LEVEL) == OK)
	world.free()
	save_graph("equipment", [
		n("start","start"), n("objective","objective_start",{"key":"equipment","text":"检查背包与穿着"}), n("item","change_item",{"key":"flow_uniform"}), n("equip","equip_item",{"key":"flow_uniform"}),
		n("has_item","has_item",{"actor":"","key":"flow_uniform","amount":1}), n("has_equipped","has_equipped",{"key":"flow_uniform"}), n("all","all"), n("branch","branch"),
		n("goal","objective_complete",{"key":"equipment"}), n("dialog","show_dialog",{"dialog_id":"flow_equipped"}), n("read","dialog_completed",{"dialog_id":"flow_equipped","task":"1004001"}), n("complete","task_complete",{"task":"1004001"})
	])
	save_graph("mechanisms", [
		n("start","start"), n("objective","objective_start",{"key":"door","text":"按钮按两次，然后穿过门"}), n("button","mechanism_interacted",{"mechanism":"$world/flow_button::button"}), n("count","counter",{"target":2}),
		n("open","mechanism_action",{"mechanism":"$world/flow_single_door::door","action":"open"}), n("wait","wait_mechanism_state",{"mechanism":"$world/flow_single_door::door","state":"open","timeout":10.0}), n("room","room_enter",{"room":"flow_finish","once":true}), n("active","room_active",{"room":"flow_finish"}),
		n("branch","branch"), n("join","wait_all"), n("goal","objective_complete",{"key":"door"}), n("complete","task_complete",{"task":str(second.task_id)})
	])
	save_graph("parallel", [
		n("start","start"), n("checkpoint","checkpoint_save"), n("parallel","parallel"), n("delay","delay",{"seconds":1.0}),
		n("timer","timer",{"seconds":2.0}), n("variable","set_variable",{"key":"flow_count","type":"number","number_value":2.0}), n("join","wait_all"), n("number","get_number",{"key":"flow_count"}),
		n("two","number",{"value":2.0}), n("compare","compare"), n("branch","branch"), n("child","run_subgraph",{"graph_path":FOLDER+"/child.tres"}),
		n("dialog","show_dialog",{"dialog_id":"flow_done"}), n("complete","task_complete",{"task":str(third.task_id)}), n("fail","task_fail",{"task":str(third.task_id),"reason":"并行变量检查失败"})
	])
	save_graph("child", [n("start","start"),n("delay","delay",{"seconds":0.5}),n("end","subgraph_end")],3)
	print("PREPARED: level 9 / event 1004 / tasks ", first.task_id, ", ",second.task_id,", ",third.task_id, "; all graph edges intentionally empty")
	get_tree().quit()
