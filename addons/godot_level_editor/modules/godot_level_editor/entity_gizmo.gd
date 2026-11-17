@tool
extends EditorNode3DGizmoPlugin
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")

func _init() -> void:
	create_material("entity", Color("5b93df"))

func _get_gizmo_name() -> String: return "LevelEntity"
func _get_priority() -> int: return 1

func _has_gizmo(node: Node3D) -> bool:
	return node.has_meta(PROFILE.META) and node.get_meta(PROFILE.META) is Resource

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	var profile: Resource = node.get_meta(PROFILE.META)
	if profile.kind == "room" and node.get("bounds_size") is Vector3:
		var box := AABB(Vector3(-node.bounds_size.x * 0.5, 0, -node.bounds_size.z * 0.5), node.bounds_size)
		var edges := PackedVector3Array()
		for i in 8:
			for axis in 3:
				var other := i ^ (1 << axis)
				if i < other: edges.append(box.get_endpoint(i)); edges.append(box.get_endpoint(other))
		gizmo.add_collision_segments(edges)
		gizmo.add_lines(edges, get_material("entity", gizmo))
		var volume := BoxMesh.new(); volume.size = node.bounds_size
		var faces := volume.get_faces()
		for i in faces.size(): faces[i].y += node.bounds_size.y * 0.5
		var triangles := TriangleMesh.new(); triangles.create_from_faces(faces)
		gizmo.add_collision_triangles(triangles)
	else:
		var mesh: PrimitiveMesh
		var offset := Vector3.UP * 0.5
		if profile.kind == "npc":
			var capsule := CapsuleMesh.new(); capsule.radius = profile.body_radius; capsule.height = maxf(profile.body_height, profile.body_radius * 2)
			mesh = capsule; offset.y = capsule.height * 0.5
		else: mesh = BoxMesh.new()
		var faces := mesh.get_faces()
		for i in faces.size(): faces[i] += offset
		var triangles := TriangleMesh.new(); triangles.create_from_faces(faces)
		gizmo.add_collision_triangles(triangles)
