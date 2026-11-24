@tool
extends RefCounted
## Preview geometry for a new preset before the designer assigns an imported model.

static func build(mode: int, size: Vector3) -> Node3D:
	var root := Node3D.new()
	var paint := Color("#415b72")
	var dark := Color("#28343d")
	match mode:
		1:
			_box(root, Vector3(0.08, 0.27, 0.55) * size, Vector3(0, 0.64, 0) * size, paint)
			_box(root, Vector3(0.14, 0.16, 0.37) * size, Vector3(0, 0.91, 0.10) * size, dark)
			_box(root, Vector3(0.66, 0.07, 0.08) * size, Vector3(0, 1.22, -0.28) * size, dark)
			_box(root, Vector3(0.36, 0.33, 0.25) * size, Vector3(0, 0.82, -0.13) * size, paint)
			for z in [-0.36, 0.36]:
				_wheel(root, Vector3(0, 0.27 * size.y, z * size.z), 0.27 * size.y, 0.26 * size.x)
		2:
			_box(root, Vector3(0.54, 0.37, 0.86) * size, Vector3(0, 0.36, 0) * size, paint)
			_box(root, Vector3(0.88, 0.10, 0.34) * size, Vector3(0, 0.26, 0.13) * size, dark)
			_box(root, Vector3(0.27, 0.18, 0.30) * size, Vector3(0, 0.64, 0.12) * size, dark)
			for x in [-0.38, 0.38]:
				_box(root, Vector3(0.13, 0.21, 0.55) * size, Vector3(x, 0.22, 0.14) * size, paint)
		_:
			_box(root, Vector3(0.79, 0.33, 0.9) * size, Vector3(0, 0.42, 0) * size, paint)
			_box(root, Vector3(0.73, 0.23, 0.35) * size, Vector3(0, 0.66, -0.24) * size, paint)
			_box(root, Vector3(0.49, 0.14, 0.35) * size, Vector3(0, 0.64, 0.18) * size, dark)
			for x in [-0.43, 0.43]:
				for z in [-0.3, 0.3]:
					_wheel(root, Vector3(x, 0.34, z) * size, 0.34 * size.y, 0.14 * size.x)
	return root

static func _box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_mesh(root, mesh, at, color)

static func _wheel(root: Node3D, at: Vector3, radius: float, width: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 16
	_add_mesh(root, mesh, at, Color("#262c32")).rotation.z = PI * 0.5

static func _add_mesh(root: Node3D, mesh: PrimitiveMesh, at: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	part.mesh = mesh
	part.position = at
	root.add_child(part)
	return part
