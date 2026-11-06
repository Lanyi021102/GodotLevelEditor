@tool
extends EditorNode3DGizmoPlugin

func _init() -> void:
	create_material("patrol_route", Color("80e6d6"))

func _get_gizmo_name() -> String:
	return "EnemyPatrolRoute"

func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() != null and node.get_script().resource_path == "res://scripts/stealth/guard_ai.gd"

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var guard := gizmo.get_node_3d()
	var points: Array[Vector3] = []
	var path: NodePath = guard.get("patrol_route")
	var route := guard.get_node_or_null(path) if not path.is_empty() else null
	if route != null:
		for point in route.get_children():
			if point is Marker3D: points.append(guard.to_local(point.global_position))
	else:
		for point in guard.get("patrol_points"): points.append(guard.to_local(point))
	if points.is_empty(): return
	var lines := PackedVector3Array()
	for i in points.size():
		var point := points[i] + Vector3.UP * 0.12
		lines.append(point + Vector3.LEFT * 0.2)
		lines.append(point + Vector3.RIGHT * 0.2)
		lines.append(point + Vector3.FORWARD * 0.2)
		lines.append(point + Vector3.BACK * 0.2)
		if points.size() > 1:
			lines.append(point)
			lines.append(points[(i + 1) % points.size()] + Vector3.UP * 0.12)
	gizmo.add_lines(lines, get_material("patrol_route", gizmo))
