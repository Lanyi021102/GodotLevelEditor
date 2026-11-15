@tool
extends RefCounted
const ROOM := preload("res://addons/godot_level_editor/runtime/room.gd")
const BLOCK := preload("res://addons/godot_level_editor/runtime/whitebox_block.gd")
const PLACE := preload("res://addons/godot_level_editor/runtime/placement.gd")
const PORT := preload("res://addons/godot_level_editor/runtime/connection.gd")
const REGION := preload("res://addons/godot_level_editor/runtime/region.gd")

static func add_owned(parent: Node, node: Node, root: Node) -> Node:
	parent.add_child(node, true)
	node.owner = root
	return node

static func block(root: Node3D, id: String, size: Vector3, at: Vector3) -> Node3D:
	var node := BLOCK.new()
	node.name = id.to_pascal_case()
	node.object_id = id
	node.size = size
	node.position = at
	add_owned(root, node, root)
	return node

static func room(id: String, label: String = "新房间") -> Node3D:
	var root := ROOM.new()
	root.name = id.to_pascal_case()
	root.room_id = id
	root.display_name = label
	block(root, "floor", Vector3(20, 0.4, 20), Vector3(0, -0.2, 0))
	return root

static func port(root: Node3D, id: String, at: Vector3, yaw: float) -> Node3D:
	var node := PORT.new()
	node.name = id.to_pascal_case()
	node.object_id = id
	node.position = at
	node.rotation_degrees.y = yaw
	add_owned(root, node, root)
	return node

static func placement(root: Node3D, id: String, kind: String, at: Vector3) -> Node3D:
	var node := PLACE.new()
	node.name = id.to_pascal_case()
	node.object_id = id
	node.component_kind = kind
	node.position = at
	add_owned(root, node, root)
	return node

static func boundary(root: Node3D, sides: Array[String]) -> void:
	for side in ["north", "south", "east", "west"]:
		var gap := sides.has(side)
		var axis_x: bool = side in ["north", "south"]
		var sign_value := -1.0 if side in ["north", "west"] else 1.0
		if gap:
			for sign_other in [-1.0, 1.0]:
				var at := Vector3(sign_other * 6, 0.65, sign_value * 9.85) if axis_x else Vector3(sign_value * 9.85, 0.65, sign_other * 6)
				block(root, "wall_%s_%s" % [side, "a" if sign_other < 0 else "b"], Vector3(8, 1.3, 0.3) if axis_x else Vector3(0.3, 1.3, 8), at)
		else:
			block(root, "wall_" + side, Vector3(20, 1.3, 0.3) if axis_x else Vector3(0.3, 1.3, 20), Vector3(0, 0.65, sign_value * 9.85) if axis_x else Vector3(sign_value * 9.85, 0.65, 0))

static func save_scene(root: Node, path: String) -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	return ResourceSaver.save(packed, path) if err == OK else err
