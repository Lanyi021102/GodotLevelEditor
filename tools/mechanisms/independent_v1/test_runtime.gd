extends Node
const STORE := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd")
const SCHEMA := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/graph/schema.gd")
var checks := 0
var failures := 0
var assets := {}
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", title)
func quiet(node: Node) -> void:
	node.set_physics_process(false)
	if node is AnimatableBody3D: node.sync_to_physics = false
	for child in node.get_children(): quiet(child)
func ticks() -> void:
	for i in 5: await get_tree().physics_frame
func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(2))
	var actual: Array = []
	for file in DirAccess.get_files_at("res://addons/godot_level_editor/scenes/mechanisms"):
		if file.ends_with(".tscn"): actual.append(file.get_basename())
	actual.sort(); var expected: Array = SCHEMA.COMPONENT_KINDS.duplicate(); expected.sort()
	check(actual == expected and actual.size() == 5, "mechanism directory contains exactly the five requested assets")
	for kind in SCHEMA.COMPONENT_KINDS:
		var root := STORE.load_pair("res://addons/godot_level_editor/scenes/mechanisms/" + str(kind) + ".tscn")
		check(root != null, str(kind) + " scene and graph load as a valid pair")
		if root == null: continue
		root.position.x = assets.size() * 6; add_child(root); quiet(root); assets[kind] = root
		check(root.bindings.size() == 1 and root.output_component() != null, str(kind) + " contains one independent physical component")
		var local_ids: Array = root.bindings.keys()
		check(root.definition.nodes.all(func(n: Dictionary): return not n.params.has("object_id") or n.params.object_id in local_ids), str(kind) + " graph references only its own component")
	var actor := CharacterBody3D.new(); actor.collision_layer = 2; actor.collision_mask = 0; actor.add_to_group("godot_level_editor_player")
	var shape := CollisionShape3D.new(); shape.shape = CapsuleShape3D.new(); shape.shape.radius = 0.25; shape.shape.height = 1.2; actor.add_child(shape); add_child(actor)
	var button: Node = assets.button.output_component(); actor.position = button.global_position + Vector3(0, 0.5, 1)
	check(button.interact(actor) and button.get_state() == "pressed", "button presses independently without a door binding")
	check(assets.single_door.output_component().get_state() == "close" and assets.double_door.output_component().get_state() == "close" and assets.lift_platform.output_component().get_state() == "at_start", "pressing the button changes neither door nor lift")
	button.advance(1); check(button.get_state() == "idle", "button resets independently")
	for kind in ["single_door", "double_door"]:
		var root: Node = assets[kind]; var door: Node = root.output_component(); actor.position = door.global_position + Vector3(0, 0.5, 1)
		check(door.interact(actor), str(kind) + " accepts its own interaction")
		root.step(); door.advance(0.1); root.step()
		check(door.get_state() == "moving", str(kind) + " starts its own internal curve animation")
		door.advance(2); root.step(); check(door.get_state() == "open" and is_equal_approx(door.angle_degrees(), 90), str(kind) + " completes opening without a button asset")
	var lift: Node = assets.lift_platform.output_component(); actor.position = lift.global_position + Vector3(0, 0.5, 1)
	check(lift.interact(actor) and lift.get_state() == "moving", "lift starts from its own interaction without a terminal")
	lift.advance(2); check(lift.get_state() == "at_end", "independent lift reaches its endpoint")
	actor.position = lift.global_transform * lift.travel_offset + Vector3(0, 0.5, 0)
	check(lift.interact(actor), "lift accepts its own return interaction"); lift.advance(2)
	check(lift.get_state() == "at_start", "independent lift returns to its start")
	var plate: Node = assets.pressure_plate.output_component(); actor.position = plate.global_position + Vector3(0, 0.6, 0); await ticks()
	for i in 4: plate.advance(1.0 / 60.0)
	check(plate.get_state() == "pressed", "independent pressure plate detects actual player occupancy")
	actor.position += Vector3(10, 0, 0); await ticks(); plate.advance(1)
	check(plate.get_state() == "released", "pressure plate releases without controlling any other mechanism")
	for path in ["res://content/scenes/levels/4_TestLevel.tscn", "res://content/scenes/levels/mechanism_whitebox_v1.tscn", "res://content/scenes/levels/dusk_mountain_house.tscn"]:
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		check(packed != null, path.get_file() + " retains loadable dependencies after asset deletion")
		if packed == null: continue
		var level: Node = packed.instantiate()
		var errors: PackedStringArray = level.validate()
		if not errors.is_empty(): print("LEVEL_VALIDATION ", path, " ", errors)
		var has_spawn: bool = level.find_children("*", "Marker3D", true, false).any(func(n: Node): return n.get("object_id") == "player_spawn")
		if path.contains("dusk_mountain"):
			var prior := PackedStringArray(["对象 ID 无效：$world/CourtyardFence_-1", "对象 ID 无效：$world/TerraceSide_-1", "对象 ID 无效：$world/FrontWall_-1", "对象 ID 无效：$world/Roof_-1"])
			check(has_spawn and errors == prior, "authored house has exactly its independently verified pre-cleanup findings, with no new dependency errors")
		else: check(has_spawn and errors.is_empty(), path.get_file() + " preserves valid authored level structure")
		if path.contains("dusk_mountain"):
			check(level.get_node("Mechanisms/inner_door").definition.resource_path.contains("::") and level.get_node("Mechanisms/inner_door/SlidingDoor").object_id == "sliding_door", "authored house keeps private door data and stable task component IDs")
		level.free()
	print("INDEPENDENT MECHANISMS RUNTIME: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
