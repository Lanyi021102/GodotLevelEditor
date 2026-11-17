extends Node3D
const BLOCK := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd")
const EDIT := preload("res://addons/godot_level_editor/modules/godot_level_editor/face_edit.gd")
const ELEMENTS := preload("res://addons/godot_level_editor/modules/godot_level_editor/mesh_elements.gd")
var passed := 0
var failed := 0
func check(value: bool, title: String) -> void:
	if value: passed += 1
	else: failed += 1
	print("[PASS] " if value else "[FAIL] ", title)
func _ready() -> void:
	get_tree().create_timer(40).timeout.connect(func(): get_tree().quit(2))
	var block := BLOCK.new()
	add_child(block)
	var top := EDIT.ray_pick(block, Vector3(0, 3, 0), Vector3.DOWN)
	check(not top.is_empty(), "ray picks the actual visible top face")
	var faces: PackedVector3Array = block.geometry().get_faces()
	var face := EDIT.planar_face(faces, top.triangle)
	check(face.triangles.size() == 2 and face.points.size() == 4, "coplanar triangles select one connected quad")
	check(face.normal.is_equal_approx(Vector3.UP), "selected surface has outward normal")
	var before := EDIT.capture(block)
	var stable_id: String = block.object_id
	var state := EDIT.pushed_state(block, faces, face, before, 0.26)
	block.apply_face_state(state)
	var bounds: AABB = block.geometry().get_aabb()
	check(is_equal_approx(bounds.size.y, 1.3), "push distance rounds to 0.3 rather than continuous drift")
	check(is_equal_approx(block.to_global(bounds.position).y, -0.5), "opposite face stays anchored while the selected face moves")
	check(is_equal_approx(block.to_global(bounds.end).y, 0.8), "selected face moves outward by the snapped distance")
	check(block.object_id == stable_id, "editing keeps the authored object identity")
	check(block.has_mesh_edit(), "face edit produces persistent geometry rather than a visual-only overlay")
	var second_faces: PackedVector3Array = block.geometry().get_faces()
	var second_face := EDIT.planar_face(second_faces, top.triangle)
	var second := EDIT.pushed_state(block, second_faces, second_face, EDIT.capture(block), 0.3)
	check(not second.is_empty() and second_face.points.size() == 4, "a previously pushed quad can be selected and pushed again as one face")
	for _i in 3: await get_tree().physics_frame
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 2, 0), Vector3(0, -1, 0)))
	check(not hit.is_empty() and is_equal_approx(hit.position.y, 0.8), "runtime collision follows the pushed surface")
	var path := "/tmp/godot_level_editor_face_edit_%d.tscn" % OS.get_process_id()
	var scene := PackedScene.new()
	scene.pack(block)
	check(ResourceSaver.save(scene, path) == OK, "pushed geometry saves as a room-compatible tscn object")
	var reloaded: Node3D = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(reloaded.mesh_edit == block.mesh_edit and reloaded.transform == block.transform and reloaded.geometry().get_faces() == block.geometry().get_faces(), "reload preserves exact vertices, position, dimensions and normals source")
	reloaded.free()
	DirAccess.remove_absolute(path)
	block.apply_face_state(before)
	state = EDIT.pushed_state(block, faces, face, before, -0.4)
	block.apply_face_state(state)
	check(is_equal_approx(block.to_global(block.geometry().get_aabb().end).y, 0.1), "inward push actually retracts the selected surface")
	check(EDIT.pushed_state(block, faces, face, before, -1.1).is_empty(), "inverted or collapsed surfaces are rejected")
	block.apply_face_state(before)
	# Translate in the face plane and rotate about its own center, rather than
	# moving the whole block. Shared vertices move once, opposite ones stay fixed.
	var pivot: Transform3D = EDIT.face_transform(face)
	var rotation := Basis(Vector3(1, 0, 1).normalized(), deg_to_rad(17))
	var delta := Transform3D(rotation, pivot.origin - rotation * pivot.origin + Vector3(0.2, 0.1, 0))
	state = EDIT.transformed_state(block, faces, face, before, delta)
	check(not state.is_empty(), "a face supports combined translation and rotation about its center")
	block.apply_face_state(state)
	var transformed_faces: PackedVector3Array = block.geometry().get_faces()
	var all_vertices_match := true
	for i in faces.size():
		var expected: Vector3 = delta * faces[i] if face.points.has(EDIT.point_key(faces[i])) else faces[i]
		all_vertices_match = all_vertices_match and block.to_global(transformed_faces[i]).distance_to(expected) < 0.0001
	check(all_vertices_match, "only selected face vertices move; all copies on neighboring triangles remain welded")
	var rotated_face := EDIT.planar_face(transformed_faces, top.triangle)
	check(rotated_face.points.size() == 4 and rotated_face.normal.distance_to(rotation * Vector3.UP) < 0.0001, "rotation preserves a planar selectable quad and updates its normal")
	check(block.to_global(rotated_face.center).is_equal_approx(pivot.origin + Vector3(0.2, 0.1, 0)), "face pivot follows the translated center after mesh recentering")
	check(EDIT.transformed_state(block, faces, face, before, Transform3D(Basis.IDENTITY, Vector3.DOWN * 2)).is_empty(), "face transforms reject inversion just like normal pushes")
	block.apply_face_state(before)
	block.rotation_degrees.y = 32
	block.scale = Vector3(2, 1.5, 0.5)
	var scaled_before := EDIT.capture(block)
	state = EDIT.pushed_state(block, faces, face, scaled_before, 0.1)
	block.apply_face_state(state)
	check(is_equal_approx(block.to_global(block.geometry().get_aabb().end).y - 0.75, 0.1), "nonuniform scale still pushes by 0.1 world units")
	block.apply_face_state(before)
	block.shape_kind = "ramp"
	faces = block.geometry().get_faces()
	top = EDIT.ray_pick(block, Vector3(0, 3, 0), Vector3.DOWN)
	face = EDIT.planar_face(faces, top.triangle)
	check(face.normal.y > 0.5 and absf(face.normal.z) > 0.5, "inclined ramp surface selects its real normal")
	var ramp_before := EDIT.capture(block)
	state = EDIT.pushed_state(block, faces, face, ramp_before, 0.2)
	check(not state.is_empty(), "inclined face can be pushed without changing the opposite vertices")
	block.apply_face_state(state)
	var ramp_changed: PackedVector3Array = block.geometry().get_faces()
	var displacement: Vector3 = block.transform.origin - ramp_before.transform.origin
	check((ramp_changed[top.triangle * 3] + displacement - faces[top.triangle * 3]).distance_to(face.normal * 0.2) < 0.0001, "ramp vertices move along the actual face normal")
	block.shape_kind = "box"
	check(not block.has_mesh_edit(), "shape parameter change uses its own generated shape")
	block.shape_kind = "ramp"
	check(block.has_mesh_edit(), "undoing a shape choice retains the original face edit data")
	_test_components(block)
	block.queue_free()
	for _i in 3: await get_tree().physics_frame
	print("FACE PUSH PULL: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _test_components(block: Node3D) -> void:
	block.shape_kind = "box"
	block.apply_face_state({"size": Vector3.ONE, "mesh_edit": {}, "transform": Transform3D.IDENTITY})
	var faces: PackedVector3Array = block.geometry().get_faces()
	var before := EDIT.capture(block)
	var data := ELEMENTS.build(faces)
	check(data.vertices.size() == 8, "box topology welds triangle copies into eight editable vertices")
	check(data.edges.size() == 12, "box has twelve selectable edges with no coplanar triangle diagonals")
	for mode in ["edge", "point"]:
		var id: int = data.edges[0].id if mode == "edge" else data.vertices[0].id
		var element := ELEMENTS.selection(faces, mode, id, data)
		check(element.points.size() == (2 if mode == "edge" else 1), "selection identifies only the requested %s vertices" % mode)
		var delta := Transform3D(Basis.IDENTITY, Vector3(0.1, 0.2, 0.1))
		var state := EDIT.transformed_state(block, faces, element, before, delta)
		check(not state.is_empty(), "%s translation produces valid shared geometry" % mode)
		if state.is_empty(): continue
		block.apply_face_state(state)
		var live: PackedVector3Array = block.geometry().get_faces()
		var matches := true
		for i in faces.size():
			var expected: Vector3 = delta * faces[i] if element.points.has(EDIT.point_key(faces[i])) else faces[i]
			matches = matches and block.to_global(live[i]).distance_to(expected) < 0.0001
		check(matches, "%s edit keeps all unselected vertices anchored and shared triangle copies welded" % mode)
		block.apply_face_state(before)
		var rotation := Basis(Vector3.UP, deg_to_rad(15))
		var rotated := Transform3D(rotation, element.center - rotation * element.center)
		state = EDIT.transformed_state(block, faces, element, before, rotated)
		if mode == "point":
			check(state == before, "a vertex rotated around itself is a true no-op without spurious mesh data")
		else:
			check(not state.is_empty() and state != before, "an edge rotates around its midpoint while neighboring triangles remain valid")
