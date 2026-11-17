@tool
extends RefCounted
const NPC := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/npc.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")

static func validate(world: Node, graph: Resource, task_id := "", expected_level := "", depth := 0) -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_instance_valid(world) or graph == null: return errors
	if not expected_level.is_empty():
		var levels := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
		var row: Dictionary = levels.catalog.for_world(world) if levels.catalog != null else {}
		if str(row.get("level_id", "")) != expected_level: return errors
	errors.append_array(graph.validate())
	if not errors.is_empty(): return errors
	var npcs := {}
	var scope: Node = world
	if not Engine.is_editor_hint() and world.level_logic == null and world.get_parent() != null: scope = world.get_parent()
	for candidate in scope.find_children("*", "Node3D", true, false):
		if candidate.get_script() != NPC: continue
		var ancestor: Node = candidate.get_parent()
		while ancestor != null and ancestor.get_script() != WORLD: ancestor = ancestor.get_parent()
		if ancestor != null and ancestor != world: continue
		npcs[str(candidate.object_id)] = candidate
	var rooms := {}
	for room in world.rooms(): rooms[str(room.room_id)] = room
	for node in graph.nodes:
		var target: Node
		var id := ""
		if node.kind == "npc_interact":
			id = str(node.params.get("npc", ""))
			target = npcs.get(id)
			if target == null: errors.append(str(node.id) + "：NPC 不存在：" + id)
		elif node.params.has("room"):
			id = str(node.params.get("room", ""))
			target = rooms.get(id)
			if target == null: errors.append(str(node.id) + "：Room 不存在：" + id)
		if target != null and target.has_meta(PROFILE.META) and not task_id.is_empty():
			var profile: Resource = target.get_meta(PROFILE.META)
			if profile != null and profile.get_script() == PROFILE and profile.lifetime == "task" and str(profile.task_id) != task_id: errors.append(str(node.id) + "：对象属于另一任务：" + id)
		if node.kind == "run_subgraph" and depth < 8 and FileAccess.file_exists(str(node.params.get("graph_path", ""))):
			var child: Resource = load(node.params.graph_path)
			if child != null and child.has_method("load_dialogue"): errors.append_array(validate(world, child, task_id, "", depth + 1))
	return errors
