@tool
extends RefCounted
const Assembly := preload("res://addons/godot_level_editor_mechanisms/runtime/assembly.gd")
const Definition := preload("res://addons/godot_level_editor_mechanisms/graph/definition.gd")
const Lever := preload("res://addons/godot_level_editor_mechanisms/runtime/lever.gd")
const Plate := preload("res://addons/godot_level_editor_mechanisms/runtime/plate.gd")
const Door := preload("res://addons/godot_level_editor_mechanisms/runtime/door.gd")
const Schema := preload("res://addons/godot_level_editor_mechanisms/graph/schema.gd")
const Stateful := preload("res://addons/godot_level_editor_mechanisms/runtime/stateful_component.gd")

static func component(kind: String, id: String) -> Node3D:
	var object: Node3D
	match kind:
		"lever": object = Lever.new()
		"plate": object = Plate.new()
		"door": object = Door.new()
		_:
			if kind not in Schema.COMPONENT_KINDS: return null
			object = Stateful.new(); object.component_type = kind; object.set_meta("mechanism_kind", kind)
			if kind == "terminal": object.initial_state = "ready"
	object.name = kind.capitalize() + "_" + id.right(6)
	object.object_id = id
	return object

static func sample() -> Node3D:
	var root := Assembly.new()
	root.name = "LeverPlateDoor"
	root.instance_id = Schema.uid("assembly")
	var graph := Definition.new()
	graph.definition_id = Schema.uid("mechanism")
	graph.display_name = "拉杆 + 压力板 → AND → 门"
	graph.nodes.assign([
		{"id": "lever_state", "kind": "lever", "label": "拉杆状态", "params": {"object_id": "lever"}},
		{"id": "plate_state", "kind": "plate", "label": "压力板状态", "params": {"object_id": "plate"}},
		{"id": "both", "kind": "and", "label": "AND · 同时满足", "params": {}},
		{"id": "door_target", "kind": "door", "label": "门目标开合", "params": {"object_id": "door"}}
	])
	graph.edges.assign([
		{"from": "lever_state", "out": "value", "to": "both", "in": "a"},
		{"from": "plate_state", "out": "value", "to": "both", "in": "b"},
		{"from": "both", "out": "value", "to": "door_target", "in": "powered"}
	])
	graph.positions = {"lever_state": Vector2(40, 70), "plate_state": Vector2(40, 280), "both": Vector2(380, 150), "door_target": Vector2(730, 150)}
	root.definition = graph
	var lever := component("lever", "lever")
	lever.position = Vector3(-2.5, 0, 1.5)
	root.add_child(lever)
	lever.owner = root
	var plate := component("plate", "plate")
	plate.position = Vector3(1.5, 0, 1.5)
	root.add_child(plate)
	plate.owner = root
	var door := component("door", "door")
	door.position = Vector3(0, 0, -2.5)
	door.color_closed = Color("283e50")
	door.color_open = Color("5ed8c1")
	root.add_child(door)
	door.owner = root
	return root
