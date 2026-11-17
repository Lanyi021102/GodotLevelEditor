@tool
extends RefCounted
## Original procedural geometry; categories reference the published Blockout Tools list.
const LABELS := {"box": "方块", "ramp": "斜坡", "stairs": "直线楼梯", "stairs_manual": "定高楼梯", "cylinder": "圆柱", "cone": "圆锥", "sphere": "球体", "hemisphere": "半球", "skewbox": "倾斜方块", "corner_curved": "弧形墙角", "stairs_curved": "弧形楼梯", "doorway": "门洞", "window": "窗洞", "railing": "栏杆", "tube": "弧形管道", "corner_ramp": "转角斜坡"}

static func mesh_for(kind: String, size: Vector3 = Vector3.ONE, steps: int = 6, thickness: float = 0.2, angle: float = 90.0, skew: float = 0.25) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := clampi(steps, 1, 64)
	var thick := clampf(thickness, 0.05, 0.45)
	match kind:
		"box": _box(st, size, Vector3.ZERO)
		"cylinder", "cone":
			var primitive := CylinderMesh.new()
			primitive.top_radius = 0.0 if kind == "cone" else 0.5
			primitive.bottom_radius = 0.5
			primitive.height = 1
			primitive.radial_segments = 32
			_primitive(st, primitive, size)
		"sphere", "hemisphere":
			var primitive := SphereMesh.new()
			primitive.radius = 0.5
			primitive.height = 0.5 if kind == "hemisphere" else 1.0
			primitive.is_hemisphere = kind == "hemisphere"
			primitive.radial_segments = 32
			primitive.rings = 12
			_primitive(st, primitive, size, Vector3(0, -0.5, 0) * size if kind == "hemisphere" else Vector3.ZERO, Vector3(1, 2, 1) if kind == "hemisphere" else Vector3.ONE)
		"ramp", "skewbox": _wedge(st, size, skew if kind == "skewbox" else 0.0, kind == "skewbox")
		"stairs", "stairs_manual":
			for i in count:
				var h := float(i + 1) / count
				_box(st, Vector3(size.x, size.y * h, size.z / count), Vector3(0, size.y * (h - 1) * 0.5, size.z * (0.5 - (i + 0.5) / count)))
		"doorway", "window":
			for side in [-1.0, 1.0]:
				_box(st, Vector3(size.x * thick, size.y, size.z), Vector3(side * size.x * (0.5 - thick * 0.5), 0, 0))
			_box(st, Vector3(size.x * (1 - thick * 2), size.y * thick, size.z), Vector3(0, size.y * (0.5 - thick * 0.5), 0))
			if kind == "window": _box(st, Vector3(size.x * (1 - thick * 2), size.y * thick, size.z), Vector3(0, -size.y * (0.5 - thick * 0.5), 0))
		"railing":
			for i in count + 1:
				_box(st, Vector3(size.x * 0.06, size.y, size.z * 0.2), Vector3(size.x * (float(i) / count - 0.5), 0, 0))
			_box(st, Vector3(size.x, size.y * 0.12, size.z * 0.3), Vector3(0, size.y * 0.44, 0))
			_box(st, Vector3(size.x, size.y * 0.08, size.z * 0.2), Vector3(0, -size.y * 0.15, 0))
		"corner_curved", "tube", "stairs_curved", "corner_ramp": _arc(st, kind, size, count, thick, deg_to_rad(clampf(angle, 15, 360)))
		_: _box(st, size, Vector3.ZERO)
	st.index()
	var result := st.commit()
	# Normalize the footprint to the chosen dimensions, including quarter-circle shapes.
	var arrays := result.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var box := result.get_aabb()
	var factors := Vector3(size.x / maxf(box.size.x, 0.001), size.y / maxf(box.size.y, 0.001), size.z / maxf(box.size.z, 0.001))
	for i in vertices.size():
		vertices[i] = (vertices[i] - box.get_center()) * factors
		normals[i] = (normals[i] / factors).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var normalized := ArrayMesh.new()
	normalized.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return normalized

static func _primitive(st: SurfaceTool, mesh: PrimitiveMesh, size: Vector3, offset: Vector3 = Vector3.ZERO, extra: Vector3 = Vector3.ONE) -> void:
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var factor := size * extra
	for i in indices:
		st.set_normal((normals[i] / factor).normalized())
		st.add_vertex(vertices[i] * factor + offset)

static func _box(st: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var primitive := BoxMesh.new()
	primitive.size = size
	_primitive(st, primitive, Vector3.ONE, at)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (c - a).cross(b - a).dot(outward) < 0:
		var swap := b
		b = c
		c = swap
	var normal := (c - a).cross(b - a).normalized()
	if normal.length_squared() < 0.01: return
	for point in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(point)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_tri(st, a, b, c, outward)
	_tri(st, a, c, d, outward)

static func _wedge(st: SurfaceTool, s: Vector3, skew: float, full: bool) -> void:
	var a := Vector3(-0.5, -0.5, -0.5) * s
	var b := Vector3(0.5, -0.5, -0.5) * s
	var c := Vector3(0.5, -0.5, 0.5) * s
	var d := Vector3(-0.5, -0.5, 0.5) * s
	var e := Vector3(-0.5 + skew, 0.5, -0.5) * s
	var f := Vector3(0.5 + skew, 0.5, -0.5) * s
	_quad(st, a, b, c, d, Vector3.DOWN)
	_quad(st, a, e, f, b, Vector3.FORWARD)
	if full:
		var g := Vector3(0.5 + skew, 0.5, 0.5) * s
		var h := Vector3(-0.5 + skew, 0.5, 0.5) * s
		_quad(st, e, h, g, f, Vector3.UP)
		_quad(st, a, d, h, e, Vector3.LEFT)
		_quad(st, b, f, g, c, Vector3.RIGHT)
		_quad(st, d, c, g, h, Vector3.BACK)
	else:
		_quad(st, e, d, c, f, Vector3(0, 1, 1))
		_tri(st, a, d, e, Vector3.LEFT)
		_tri(st, b, f, c, Vector3.RIGHT)

static func _arc(st: SurfaceTool, kind: String, s: Vector3, steps: int, thickness: float, angle: float) -> void:
	var segments := maxi(12, ceili(angle * 12))
	if kind == "stairs_curved": segments = steps
	var inner := 0.5 - thickness
	if kind == "corner_ramp": inner = 0.0
	for i in segments:
		var a := float(i) / segments * angle
		var b := float(i + 1) / segments * angle
		var ha := 0.5
		var hb := 0.5
		if kind == "stairs_curved":
			ha = float(i + 1) / segments - 0.5
			hb = ha
		elif kind == "corner_ramp":
			ha = float(i) / segments - 0.5
			hb = float(i + 1) / segments - 0.5
		var p0 := Vector3(cos(a) * 0.5, -0.5, sin(a) * 0.5) * s
		var p1 := Vector3(cos(b) * 0.5, -0.5, sin(b) * 0.5) * s
		var p2 := Vector3(cos(b) * inner, -0.5, sin(b) * inner) * s
		var p3 := Vector3(cos(a) * inner, -0.5, sin(a) * inner) * s
		var q0 := Vector3(p0.x, ha * s.y, p0.z)
		var q1 := Vector3(p1.x, hb * s.y, p1.z)
		var q2 := Vector3(p2.x, hb * s.y, p2.z)
		var q3 := Vector3(p3.x, ha * s.y, p3.z)
		_quad(st, p0, p1, p2, p3, Vector3.DOWN)
		_quad(st, q0, q3, q2, q1, Vector3.UP)
		_quad(st, p0, q0, q1, p1, Vector3(cos((a + b) * 0.5), 0, sin((a + b) * 0.5)))
		if inner > 0: _quad(st, p3, p2, q2, q3, -Vector3(cos((a + b) * 0.5), 0, sin((a + b) * 0.5)))
		_quad(st, p0, p3, q3, q0, Vector3(sin(a), 0, -cos(a)))
		_quad(st, p1, q1, q2, p2, Vector3(-sin(b), 0, cos(b)))
