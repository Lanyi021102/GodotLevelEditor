extends Node
const Factory := preload("res://addons/godot_level_editor_mechanisms/factory.gd")
const Store := preload("res://addons/godot_level_editor_mechanisms/store.gd")
const Definition := preload("res://addons/godot_level_editor_mechanisms/graph/definition.gd")
const Schema := preload("res://addons/godot_level_editor_mechanisms/graph/schema.gd")
var passed := 0
var failed := 0
var sample: Node3D

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func _ready() -> void:
	get_tree().create_timer(45, true).timeout.connect(func(): get_tree().quit(2))
	sample = Factory.sample()
	add_child(sample)
	sample.set_physics_process(false)
	for object in sample.bindings.values(): object.set_physics_process(false)
	var lever: Node3D = sample.bindings.lever
	var plate: Node3D = sample.bindings.plate
	var door: Node3D = sample.bindings.door
	check(Store.validate(sample).is_empty(), "sample graph and scene bindings validate")
	check(door is PowerDoor and door.has_method("add_power_source"), "door retains existing PowerDoor interface")
	check(door.position == Vector3(0, 0, -2.5) and door.get_node("Shape").position.y == door.panel_size.y * 0.5, "new door uses a stable floor pivot")
	await _occupancy(plate, false)
	sample.step()
	door.advance(1)
	check(not door.is_open(), "AND starts closed")
	lever.interact()
	sample.step()
	door.advance(1)
	check(not door.is_open(), "lever alone cannot satisfy AND")
	await _occupancy(plate, true)
	sample.step()
	door.advance(1)
	check(door.is_open(), "actual player-layer occupancy AND lever opens physical door")
	var body: CollisionShape3D = door.get_node("Shape")
	check(is_equal_approx(body.position.y, door.panel_size.y * 0.5 + door.open_height), "door collision rises with mesh")
	check(door.position == Vector3(0, 0, -2.5), "door opening never moves its binding origin")
	var checkpoint: Dictionary = sample.tl_capture()
	lever.interact()
	sample.step()
	door.advance(1)
	check(not door.is_open(), "lever off closes door")
	sample.tl_restore(checkpoint)
	check(lever.is_powered() and door.is_open() and sample.frame == checkpoint.frame, "snapshot restores source, door progress and graph frame")
	await _occupancy(plate, false)
	sample.step()
	door.advance(1)
	check(not door.is_open(), "leaving pressure plate closes door")
	var original: Resource = sample.definition
	var bypass: Resource = original.duplicate(true)
	bypass.edges[2] = {"from": "lever_state", "out": "value", "to": "door_target", "in": "powered"}
	sample.definition = bypass
	sample.configure()
	sample.step()
	door.advance(1)
	check(door.is_open(), "rewiring actual graph changes behavior: lever now bypasses AND")
	bypass.edges.remove_at(2)
	sample.configure()
	check(not sample.errors.is_empty(), "missing required input is rejected")
	door.advance(1)
	check(not door.is_open(), "invalid graph withdraws old door command")
	sample.definition = original
	sample.configure()
	_test_validation()
	_test_lever(lever)
	_test_events()
	_test_roundtrip()
	_test_numeric_object()
	for kind in ["lever", "door"]:
		var packed: PackedScene = load("res://scenes/mechanisms/" + kind + ".tscn")
		var instance := packed.instantiate()
		add_child(instance)
		check(instance.has_method("is_powered") and instance.has_method("tl_capture"), kind + " standalone scene loads")
		instance.free()
	sample.free()
	print("MECHANISMS: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

var _actor: CharacterBody3D
func _occupancy(plate: Node3D, value: bool) -> void:
	if not is_instance_valid(_actor):
		_actor = CharacterBody3D.new()
		_actor.collision_layer = 2
		_actor.collision_mask = 0
		_actor.add_to_group("stealth_target")
		var shape := CollisionShape3D.new()
		shape.shape = CapsuleShape3D.new()
		_actor.add_child(shape)
		add_child(_actor)
		_actor.set_physics_process(true)
	_actor.global_position = plate.global_position + (Vector3(0, 0.8, 0) if value else Vector3(20, 0.8, 0))
	for _i in 4: await get_tree().physics_frame
	plate._plate._physics_process(1.0)

func _test_validation() -> void:
	var graph: Resource = sample.definition.duplicate(true)
	graph.format_version = 9
	check(not graph.validate(sample.bindings, true).is_empty(), "unsupported resource version is rejected")
	graph = sample.definition.duplicate(true)
	graph.nodes[0].params = 42
	check(not graph.validate(sample.bindings, true).is_empty(), "malformed node parameter container is rejected without executing")
	graph = sample.definition.duplicate(true)
	graph.nodes[0].params.object_id = "missing"
	check(not graph.validate(sample.bindings, true).is_empty(), "dangling object reference is rejected")
	graph = sample.definition.duplicate(true)
	graph.edges[0].out = "renamed_missing_port"
	check(not graph.validate(sample.bindings, true).is_empty(), "invalid named port is rejected")
	graph = sample.definition.duplicate(true)
	graph.nodes.append({"id": "number", "kind": "number", "params": {"value": 2.0}})
	graph.edges[0].from = "number"
	check(not graph.validate(sample.bindings, true).is_empty(), "numeric-to-boolean mismatch is rejected")
	graph = sample.definition.duplicate(true)
	graph.edges[0].from = "both"
	check(not graph.validate(sample.bindings, true).is_empty(), "unclocked data cycle is rejected")
	var duplicate := Factory.component("lever", "lever")
	sample.add_child(duplicate)
	check(not sample.configure().is_empty(), "duplicate scene object IDs are rejected")
	duplicate.free()
	sample.configure()

func _test_lever(lever: Node3D) -> void:
	lever.mode = 1
	lever.reset_delay = 0.25
	lever.reset_state()
	lever.interact()
	lever.advance(0.1)
	var state: Dictionary = lever.tl_capture()
	lever.advance(1)
	check(not lever.is_powered(), "pulse lever resets using physics time")
	lever.tl_restore(state)
	check(lever.is_powered() and is_equal_approx(lever.remaining, 0.15), "lever timer survives snapshot restore")
	lever.mode = 2
	lever.reset_state()
	check(lever.interact() and not lever.interact(), "one-shot lever refuses repeated interaction")
	lever.mode = 0
	lever.reset_state()
	_actor.position = Vector3(100, 1, 100)
	check(not lever.interact(_actor), "actor outside interaction radius is refused")
	lever.enabled = false
	check(not lever.interact(), "disabled lever is refused")
	lever.enabled = true

func _test_events() -> void:
	var root := Factory.sample()
	add_child(root)
	root.set_physics_process(false)
	for object in root.bindings.values(): object.set_physics_process(false)
	var definition := Definition.new()
	definition.definition_id = "event_test"
	definition.nodes.assign([
		{"id": "constant", "kind": "bool", "params": {"value": true}},
		{"id": "edge", "kind": "rising", "params": {}},
		{"id": "delay", "kind": "delay", "params": {"seconds": 0.05}},
		{"id": "set", "kind": "set_lever", "params": {"value": true, "object_id": "lever"}}
	])
	definition.edges.assign([
		{"from": "constant", "out": "value", "to": "edge", "in": "value"},
		{"from": "edge", "out": "fired", "to": "delay", "in": "trigger"},
		{"from": "delay", "out": "fired", "to": "set", "in": "trigger"}
	])
	root.definition = definition
	check(root.configure().is_empty(), "explicit boolean-to-event and delay graph validates")
	root.step()
	check(not root.bindings.lever.is_powered() and root.pending.size() == 1, "event delay queues work without immediate side effects")
	var snapshot: Dictionary = root.tl_capture()
	for _i in 3: root.step()
	check(root.bindings.lever.is_powered() and root.pending.is_empty(), "due event sets lever exactly after fixed ticks")
	check(root.last_events.has("set") and root.last_events["set"].frame == root.frame, "debug retains actual most recent event reason and frame")
	root.tl_restore(snapshot)
	check(not root.bindings.lever.is_powered() and root.pending.size() == 1, "snapshot restores pending events without firing them")
	for _i in 3: root.step()
	check(root.bindings.lever.is_powered() and root.pending.is_empty(), "restored event fires once on the same due tick")
	root.bindings.lever.set_powered(false)
	for _i in 10: root.step()
	check(not root.bindings.lever.is_powered(), "continuous true state does not repeat one-shot rising event")
	root.free()

func _test_roundtrip() -> void:
	var path := "user://mechanism_roundtrip.tscn"
	sample.definition.view_zoom = 0.8
	sample.definition.view_offset = Vector2(100, 120)
	sample.bindings.door.panel_size = Vector3(4.0, 3.0, 0.6)
	var result := Store.save_pair(sample, path)
	check(result.ok, "scene and graph pair saves")
	# Saving twice exercises resource-cache ownership as well as replace/backup paths.
	check(Store.save_pair(sample, path).ok, "existing scene and graph pair replaces successfully")
	var restored := Store.load_pair(path)
	check(restored != null, "saved pair loads and validates")
	if restored != null:
		add_child(restored)
		check(restored.definition.nodes == sample.definition.nodes and restored.definition.edges == sample.definition.edges, "reload preserves nodes, params and typed edges")
		check(restored.definition.view_zoom == 0.8 and restored.definition.view_offset == Vector2(100, 120), "reload preserves canvas zoom and pan")
		check(restored.bindings.door.panel_size == Vector3(4, 3, 0.6) and restored.bindings.lever.position == sample.bindings.lever.position, "reload preserves geometry parameters and scene placement")
		check(not restored.bindings.lever.is_powered() and restored.bindings.door.open_ratio == 0, "preview/runtime state does not leak into saved definitions")
		check(restored.definition.resource_path.ends_with(".graph.tres"), "scene references separate graph resource")
		restored.free()
	var contents := FileAccess.get_file_as_string(path)
	check(not contents.contains("Generated") and not contents.contains("Shape") and not contents.contains("pending.tres"), "save excludes generated geometry and staging paths")
	var invalid: Resource = sample.definition.duplicate(true)
	invalid.format_version = 99
	var before := FileAccess.get_md5(path)
	var original: Resource = sample.definition
	sample.definition = invalid
	check(not Store.save_pair(sample, path).ok and before == FileAccess.get_md5(path), "invalid definition cannot overwrite existing pair")
	sample.definition = original
	for file in [path, path.get_basename() + ".graph.tres"]: DirAccess.remove_absolute(file)

func _test_numeric_object() -> void:
	var root := Factory.sample()
	add_child(root)
	root.set_physics_process(false)
	var definition := Definition.new()
	definition.definition_id = "number_object_test"
	definition.nodes.assign([
		{"id": "a", "kind": "number", "params": {"value": 3.0}},
		{"id": "b", "kind": "number", "params": {"value": 2.0}},
		{"id": "compare", "kind": "greater", "params": {}},
		{"id": "ref", "kind": "object", "params": {"object_id": "lever"}},
		{"id": "read", "kind": "read_power", "params": {}},
		{"id": "and", "kind": "and", "params": {}},
		{"id": "door", "kind": "door", "params": {"object_id": "door"}}
	])
	definition.edges.assign([
		{"from": "a", "out": "value", "to": "compare", "in": "a"},
		{"from": "b", "out": "value", "to": "compare", "in": "b"},
		{"from": "ref", "out": "value", "to": "read", "in": "target"},
		{"from": "compare", "out": "value", "to": "and", "in": "a"},
		{"from": "read", "out": "value", "to": "and", "in": "b"},
		{"from": "and", "out": "value", "to": "door", "in": "powered"}
	])
	root.definition = definition
	check(root.configure().is_empty(), "numeric and object-reference ports validate")
	root.bindings.lever.set_powered(true)
	root.step()
	root.bindings.door.advance(1)
	check(root.bindings.door.is_open(), "numeric comparison and object power actually control door")
	var semantic: Dictionary = root.tl_capture()
	definition.positions = {"door": Vector2(-3000, 9000)}
	root.step()
	check(root.bindings.door.is_open() and root.values == semantic.values, "moving canvas nodes does not change execution semantics")
	root.free()
