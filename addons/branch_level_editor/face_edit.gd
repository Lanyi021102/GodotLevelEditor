@tool
extends RefCounted
## Geometry operations shared by viewport interaction and saved whitebox meshes.
const STEP := 0.1
const EPS := 0.00001

static func mesh_from_faces(faces: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, faces.size() - 2, 3):
		var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
		st.set_normal(normal)
		for j in 3: st.add_vertex(faces[i + j])
	st.index()
	return st.commit()

static func point_key(point: Vector3) -> Vector3i:
	return Vector3i((point / EPS).round())

static func edge_key(a: Vector3, b: Vector3) -> String:
	var ka := str(point_key(a))
	var kb := str(point_key(b))
	return ka + ":" + kb if ka < kb else kb + ":" + ka

static func planar_face(faces: PackedVector3Array, triangle: int) -> Dictionary:
	var i := triangle * 3
	if i < 0 or i + 2 >= faces.size(): return {}
	var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
	if normal.is_zero_approx(): return {}
	var plane := Plane(normal, faces[i])
	var edges := {}
	var candidates := {}
	for t in faces.size() / 3:
		var at := t * 3
		var n := (faces[at + 2] - faces[at]).cross(faces[at + 1] - faces[at]).normalized()
		if n.dot(normal) < 0.9999: continue
		if absf(plane.distance_to(faces[at])) > EPS * 4: continue
		candidates[t] = true
		for k in 3:
			var key := edge_key(faces[at + k], faces[at + (k + 1) % 3])
			if not edges.has(key): edges[key] = []
			edges[key].append(t)
	var region := {triangle: true}
	var queue := [triangle]
	while not queue.is_empty():
		var t: int = queue.pop_back()
		for k in 3:
			var key := edge_key(faces[t * 3 + k], faces[t * 3 + (k + 1) % 3])
			for neighbor in edges.get(key, []):
				if not region.has(neighbor): region[neighbor] = true; queue.append(neighbor)
	var points := {}
	var selected := PackedVector3Array()
	for t in region:
		for k in 3:
			var p := faces[t * 3 + k]
			points[point_key(p)] = true
			selected.append(p)
	return {"normal": normal, "triangles": region.keys(), "points": points, "faces": selected, "center": _center(selected)}

static func _center(points: PackedVector3Array) -> Vector3:
	var total := Vector3.ZERO
	for p in points: total += p
	return total / maxf(1, points.size())

static func ray_pick(block: Node3D, origin: Vector3, direction: Vector3) -> Dictionary:
	if not block.is_visible_in_tree() or block.get("visual_scene") != null: return {}
	var faces: PackedVector3Array = block.geometry().get_faces()
	var local_origin := block.to_local(origin)
	var local_dir := block.global_basis.inverse() * direction
	var nearest := INF
	var triangle := -1
	var hit_point := Vector3.ZERO
	for i in range(0, faces.size(), 3):
		var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i])
		if normal.dot(local_dir) >= -EPS: continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_dir, faces[i], faces[i + 1], faces[i + 2])
		if hit == null: continue
		var distance := origin.distance_to(block.to_global(hit))
		if distance < nearest: nearest = distance; triangle = i / 3; hit_point = hit
	if triangle < 0: return {}
	return {"block": block, "triangle": triangle, "distance": nearest, "hit": hit_point}

static func capture(block: Node3D) -> Dictionary:
	return {"size": block.size, "mesh_edit": block.mesh_edit.duplicate(true), "transform": block.transform}

static func pushed_state(block: Node3D, faces: PackedVector3Array, face: Dictionary, before: Dictionary, distance: float) -> Dictionary:
	var amount := snappedf(distance, STEP)
	if is_zero_approx(amount): return before.duplicate(true)
	var normal: Vector3 = (block.global_basis.inverse().transposed() * face.normal).normalized()
	var delta: Vector3 = block.global_basis.inverse() * normal * amount
	var changed := faces.duplicate()
	for i in changed.size():
		if face.points.has(point_key(faces[i])): changed[i] += delta
	# Reject collapsed/flipped neighboring surfaces, instead of creating invalid collision.
	for i in range(0, changed.size(), 3):
		var old_n := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i])
		var new_n := (changed[i + 2] - changed[i]).cross(changed[i + 1] - changed[i])
		if old_n.length_squared() > EPS * EPS and (new_n.length_squared() < EPS * EPS or old_n.normalized().dot(new_n.normalized()) <= 0.001): return {}
	var bounds := AABB(changed[0], Vector3.ZERO)
	for p in changed: bounds = bounds.expand(p)
	if bounds.size.x < STEP - EPS or bounds.size.y < STEP - EPS or bounds.size.z < STEP - EPS: return {}
	var dimensions := bounds.size.snapped(Vector3.ONE * STEP).max(Vector3.ONE * STEP)
	for i in changed.size(): changed[i] = (changed[i] - bounds.get_center()) / dimensions
	var moved: Transform3D = before.transform
	moved.origin += moved.basis * bounds.get_center()
	return {"size": dimensions, "transform": moved, "mesh_edit": {"version": 1, "signature": block.geometry_signature(), "vertices": changed}}
