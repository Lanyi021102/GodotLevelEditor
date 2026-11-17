@tool
extends Control
## Whitebox geometry preview for the active placement wheel.
const SHAPES := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_shapes.gd")
var kind := "box"
var title := ""
var _faces: Array = []
func _ready() -> void:
	if SHAPES.LABELS.has(kind):
		var mesh := SHAPES.mesh_for(kind, Vector3.ONE, 6, 0.2, 360 if kind == "tube" else 90)
		var triangles := mesh.get_faces()
		var bounds := AABB(triangles[0], Vector3.ZERO)
		for vertex in triangles: bounds = bounds.expand(vertex)
		var mesh_center := bounds.get_center()
		var view := Vector3(1.5, 1.15, 1.8).normalized()
		var right := Vector3(view.z, 0, -view.x).normalized()
		var up := view.cross(right)
		for i in range(0, triangles.size(), 3):
			var a := triangles[i]
			var b := triangles[i + 1]
			var c := triangles[i + 2]
			var normal := (c - a).cross(b - a).normalized()
			if normal.dot(view) < -0.01: continue
			var points := PackedVector2Array()
			for v in [a, b, c]: points.append(Vector2((v - mesh_center).dot(right), -(v - mesh_center).dot(up)))
			_faces.append({"points": points, "depth": ((a + b + c) / 3).dot(view), "shade": 0.55 + 0.4 * maxf(normal.dot(Vector3(0.4, 1, 0.6).normalized()), 0)})
		_faces.sort_custom(func(a: Dictionary, b: Dictionary): return a.depth < b.depth)
func _draw() -> void:
	var center := size * 0.5
	var factor := minf(size.x * 0.72, size.y * 0.78)
	for face in _faces:
		var points := PackedVector2Array()
		for point in face.points: points.append(center + point * factor)
		draw_colored_polygon(points, Color("a1c7de") * float(face.shade))
