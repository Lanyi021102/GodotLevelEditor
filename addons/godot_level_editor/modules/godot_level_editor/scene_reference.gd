@tool
extends RefCounted
## Authoring adapter: scene-tree paths are resolved once, only stable IDs are stored.
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const LOGIC := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_logic_graph.gd")
const NPC := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/npc.gd")
const ACCESS := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/state_access.gd")
const CAPTIONS := {"object": "场景对象", "room": "房间", "npc": "NPC", "actor": "角色", "mechanism": "机关 / 组件"}

static func keys(node: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in CAPTIONS:
		if node.get("params", {}).has(key): result.append(key)
	return result

static func choices(world: Node, graph: Resource, node: Dictionary, key: String) -> Dictionary:
	var result := {}
	if not is_instance_valid(world): return result
	if key == "room":
		for room in world.rooms(): result[room.room_id] = room
	elif key == "npc":
		if graph.is_level_logic(): return LOGIC.permanent_npcs(world)
		# The legacy task service discovers narrative NPCs inside prefabs as well.
		for object in world.find_children("*", "Node3D", true, false):
			if NPC.supports(object):
				var id := NPC.speaker_id(object)
				if not id.is_empty(): result[id] = object
	elif key == "mechanism":
		# Descriptions also include uninstantiated component_scene previews.
		for entry in ACCESS.descriptions(world): result[entry.reference] = world.object_by_id(str(entry.reference).split(ACCESS.SEPARATOR)[0])
	else:
		for id in world.objects():
			var object: Node = world.object_by_id(id)
			if key == "actor" or (node.kind == "port" and object.get_script() == WORLD.PORT) or (node.kind in ["goal", "region_enter", "region_exit"] and object.get_script() == WORLD.REGION) or (node.kind in ["source", "object", "set_switch", "enemy_patrol"] and object.get_script() == WORLD.PLACE) or (node.kind in ["set_visibility", "object_interacted"] and object is Node3D): result[id] = object
	return result

static func resolve(world: Node, graph: Resource, node: Dictionary, key: String, data: Variant) -> String:
	if not is_instance_valid(world) or not world.is_inside_tree() or not data is Dictionary or data.get("type") != "nodes": return ""
	var paths: Variant = data.get("nodes", [])
	if not (paths is Array or paths is PackedStringArray) or paths.size() != 1: return ""
	if not (paths[0] is NodePath or paths[0] is String): return ""
	var dragged := world.get_node_or_null(NodePath(paths[0]))
	if dragged == null or not world.is_ancestor_of(dragged): return ""
	var available := choices(world, graph, node, key)
	var matches: Array[String] = []
	for reference in available:
		var anchor: Node = available[reference]
		if key == "mechanism":
			var component := ACCESS.resolve(world, reference)
			if component != null and (component == dragged or component.is_ancestor_of(dragged)): return reference
		if anchor == dragged or anchor.is_ancestor_of(dragged): matches.append(reference)
	if matches.size() == 1: return matches[0]
	# A composed mechanism may expose a designated output component.
	if key == "mechanism" and not matches.is_empty():
		var output := ACCESS.resolve_anchor(available[matches[0]])
		if output != null:
			for reference in matches:
				if ACCESS.resolve(world, reference) == output: return reference
	return ""
