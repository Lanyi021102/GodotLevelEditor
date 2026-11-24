@tool
extends EditorNode3DGizmoPlugin
const VEHICLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_vehicle/vehicle.gd")

func _init() -> void:
	create_material("body", Color("#6ba6e5"))
	create_material("seat", Color("#f1b452"))
	create_material("entry", Color("#78c5f0"))
	create_material("exit", Color("#65c9a9"))

func _get_gizmo_name() -> String:
	return "载具"

func _has_gizmo(node: Node3D) -> bool:
	return node is VEHICLE and not node.has_meta("godot_level_editor_radial_preview")

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var vehicle := gizmo.get_node_3d() as VEHICLE
	var size := vehicle.body_size
	var box := AABB(vehicle.body_center - size * 0.5, size)
	var edges := PackedVector3Array()
	for corner in 8:
		for axis in 3:
			var other := corner ^ (1 << axis)
			if corner < other:
				edges.append(box.get_endpoint(corner))
				edges.append(box.get_endpoint(other))
	gizmo.add_collision_segments(edges)
	var arrow := vehicle.body_center + Vector3(0, 0, -size.z * 0.5)
	var nose := arrow + Vector3.FORWARD * 0.35
	edges.append_array(PackedVector3Array([arrow, nose, nose, arrow + Vector3.LEFT * 0.15, nose, arrow + Vector3.RIGHT * 0.15]))
	gizmo.add_lines(edges, get_material("body", gizmo))
	gizmo.add_lines(_point(vehicle.seat_point), get_material("seat", gizmo))
	gizmo.add_lines(_point(vehicle.boarding_point), get_material("entry", gizmo))
	var exits := _point(vehicle.exit_left)
	exits.append_array(_point(vehicle.exit_right))
	gizmo.add_lines(exits, get_material("exit", gizmo))

func _point(position: Vector3) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		lines.append(position - axis * 0.12)
		lines.append(position + axis * 0.12)
	return lines
