@tool
extends RefCounted
func run(suite: EditorPlugin) -> void:
	var panel: Control = suite.task_graph
	var world: Node = load("res://content/scenes/levels/whitebox_world.tscn").instantiate()
	suite.add_child(world)
	var graph := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/task_definition.gd").new()
	graph.graph_id = "qa06_editor"
	graph.nodes = [{"id": "talk", "kind": "npc_interact", "params": {"npc": "qa_deleted", "task": "1001001"}}]
	var path := "user://qa06_editor_%d.tres" % OS.get_process_id()
	ResourceSaver.save(graph, path)
	graph.take_over_path(path)
	panel.dirty = false
	panel.open_graph(graph)
	panel.world = world
	panel.bound_task_id = ""
	panel.dirty = true
	var original := FileAccess.get_file_as_bytes(path)
	var rejected: bool = not panel.save_graph() and panel.dirty and panel.status.text.contains("NPC 不存在") and original == FileAccess.get_file_as_bytes(path)
	print("[PASS] " if rejected else "[FAIL] ", "QA06 editor rejects dangling NPC without modifying the saved graph")
	var npc: Node = load("res://addons/godot_level_editor/scenes/narrative/npc.tscn").instantiate()
	npc.object_id = "qa_deleted"
	world.add_child(npc)
	var accepted: bool = panel.save_graph()
	if not accepted: print(panel.status.text)
	print("[PASS] " if accepted else "[FAIL] ", "QA06 editor saves when the NPC reference exists")
	DirAccess.remove_absolute(path)
	print("QA06 TASK EDITOR: 2 checks, ", (0 if rejected else 1) + (0 if accepted else 1), " failures")
	suite.get_tree().quit(0 if rejected and accepted else 1)
