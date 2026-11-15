@tool
extends RefCounted
## Logical vertices and crease edges; coplanar triangulation diagonals are omitted.
const EDIT := preload("res://addons/godot_level_editor/face_edit.gd")

static func build(faces: PackedVector3Array) -> Dictionary:
	var vertices := {}
	var edges := {}
	for at in range(0, faces.size(), 3):
		var normal := (faces[at + 2] - faces[at]).cross(faces[at + 1] - faces[at]).normalized()
		for k in 3:
			var id := at + k
			var point := faces[id]
			var key := EDIT.point_key(point)
			if not vertices.has(key): vertices[key] = {"id": id, "point": point, "normals": []}
			vertices[key].normals.append(normal)
			var end := faces[at + (k + 1) % 3]
			var edge_key := EDIT.edge_key(point, end)
			if not edges.has(edge_key): edges[edge_key] = {"id": id, "a": point, "b": end, "normals": []}
			edges[edge_key].normals.append(normal)
	var creases: Array[Dictionary] = []
	for edge in edges.values():
		var crease: bool = edge.normals.size() == 1
		for normal in edge.normals:
			if normal.dot(edge.normals[0]) < 0.9999: crease = true; break
		if crease and edge.a.distance_to(edge.b) > EDIT.EPS: creases.append(edge)
	return {"vertices": vertices.values(), "edges": creases, "all_edges": edges}

static func selection(faces: PackedVector3Array, mode: String, id: int, topology: Dictionary = {}) -> Dictionary:
	if mode == "face": return EDIT.planar_face(faces, id)
	if id < 0 or id >= faces.size(): return {}
	var points := PackedVector3Array([faces[id]])
	var normal := Vector3.UP
	if mode == "edge":
		var end := (id / 3) * 3 + (id % 3 + 1) % 3
		points.append(faces[end])
		if topology.is_empty(): topology = build(faces)
		var edge: Dictionary = topology.all_edges.get(EDIT.edge_key(points[0], points[1]), {})
		normal = Vector3.ZERO
		for n in edge.get("normals", []): normal += n
		if normal.is_zero_approx(): normal = Vector3.UP
		normal = normal.normalized()
	var keys := {}
	var center := Vector3.ZERO
	for point in points: keys[EDIT.point_key(point)] = true; center += point
	return {"points": keys, "center": center / points.size(), "normal": normal, "vertices": points, "faces": PackedVector3Array(), "kind": mode}

static func frame(element: Dictionary) -> Transform3D:
	if element.is_empty(): return Transform3D.IDENTITY
	if element.get("kind", "face") == "face": return EDIT.face_transform(element)
	if element.kind == "point": return Transform3D(Basis.IDENTITY, element.center)
	var tangent: Vector3 = (element.vertices[1] - element.vertices[0]).normalized()
	var normal: Vector3 = element.normal
	# The edge may become planar during an edit; retain a nondegenerate frame.
	normal = normal - tangent * normal.dot(tangent)
	if normal.length_squared() < 0.001:
		normal = tangent.cross(Vector3.UP if absf(tangent.y) < 0.9 else Vector3.RIGHT)
	normal = normal.normalized()
	return Transform3D(Basis(tangent, normal.cross(tangent).normalized(), normal), element.center)

static func front_facing(normals: Array, block: Node3D, camera: Camera3D, point: Vector3) -> bool:
	var ray := camera.project_ray_normal(camera.unproject_position(block.to_global(point)))
	var local_direction := block.global_basis.inverse() * ray
	for normal in normals:
		if normal.dot(local_direction) < -EDIT.EPS: return true
	return false
