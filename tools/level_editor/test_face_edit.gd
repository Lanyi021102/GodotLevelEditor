extends Node3D
const BLOCK := preload("res://addons/branch_level_editor/runtime/whitebox_block.gd")
const EDIT := preload("res://addons/branch_level_editor/face_edit.gd")
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
	var path := "/tmp/branch_face_edit_%d.tscn" % OS.get_process_id()
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
	block.queue_free()
	for _i in 3: await get_tree().physics_frame
	print("FACE PUSH PULL: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
