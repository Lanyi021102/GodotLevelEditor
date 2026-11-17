extends Node
const GROUPS := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_factory.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)
func _ready() -> void:
	var world := WORLD.new(); world.name = "GroupedRuntime"; world.world_id = "grouped_runtime"; world.start_room_id = ""
	world.topology = GRAPH.new(); world.topology.graph_id = "grouped_topology"; world.topology.graph_kind = "topology"
	world.events = GRAPH.new(); world.events.graph_id = "grouped_events"
	var old := FACTORY.block(world, "existing_floor", Vector3(8, 0.4, 8), Vector3(0, -0.2, 0))
	var floor := FACTORY.block(world, "new_floor", Vector3.ONE, Vector3(1, 1, 2))
	GROUPS.group_new_node(world, floor)
	check(old.get_parent() == world and floor.get_parent().name == "Whitebox", "newly authored whitebox groups without moving existing root content")
	var room := FACTORY.room("detection"); room.uses_topology = false; FACTORY.add_owned(world, room, world)
	GROUPS.group_new_node(world, room)
	var local := FACTORY.placement(room, "switch", "lever", Vector3(2, 0, 0)); GROUPS.group_new_node(room, local)
	check(world.rooms() == [room] and world.object_by_id("detection/switch") == local and room.object_by_id("switch") == local, "group wrappers are transparent to Room discovery and legacy Room-local references")
	check(world.object_by_id("$world/new_floor") == floor and world.object_by_id("$world/existing_floor") == old and world.objects().size() == 4, "grouped and legacy root objects preserve their original stable-ID scopes")
	var errors: PackedStringArray = world.validate()
	if not errors.is_empty(): print("VALIDATION ", errors)
	check(errors.is_empty(), "the grouped world validates alongside existing root content")
	var assembly: Node3D = load("res://addons/godot_level_editor/scenes/mechanisms/single_door.tscn").instantiate()
	FACTORY.add_owned(world, assembly, world); GROUPS.group_new_node(world, assembly)
	check(assembly.get_parent().name == "Mechanisms" and world.object_by_id("$world/door") == null, "mechanism grouping does not leak prefab-internal IDs into the world scope")
	var npc: Node3D = load("res://addons/godot_level_editor/scenes/narrative/npc.tscn").instantiate()
	npc.object_id = "grouped_npc"; FACTORY.add_owned(world, npc, world); GROUPS.group_new_node(world, npc)
	check(world.object_by_id("$world/grouped_npc") == npc and npc.get_parent().name == "NPCs", "NPC stable references resolve through the category parent")
	for child in room.find_children("*", "Node", true, false):
		if child.owner == room: child.owner = world
	var packed := PackedScene.new(); var error := packed.pack(world)
	var restored := packed.instantiate()
	check(error == OK and restored.get_node("Whitebox/NewFloor").object_id == "new_floor" and restored.rooms().size() == 1 and restored.object_by_id("detection/switch") != null, "save and reload preserve plain group nodes, ownership and scoped IDs")
	check(restored.get_node("NPCs").get_script() == null and restored.get_node("NPCs").get_class() == "Node3D", "management nodes are empty plain Node3D containers")
	restored.free()
	world.events.nodes = [{"id": "group_room_enter", "kind": "room_enter", "params": {"room": "detection"}}]
	add_child(world)
	for i in 3: await get_tree().process_frame
	check(world.runtime_valid and world.object_by_id("detection/switch").runtime_component != null, "grouped world and Room-local mechanism components initialize at runtime")
	var actor := Node3D.new(); add_child(actor)
	room.player_entered.emit("detection", actor)
	for i in 3: await get_tree().physics_frame
	check(world.runner.counts.get("group_room_enter", 0) == 1, "runtime Room-enter events still reach the world graph through the grouping layer")
	world.queue_free()
	await get_tree().process_frame
	print("SCENE GROUPS RUNTIME: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
