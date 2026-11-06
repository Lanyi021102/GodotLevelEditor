@tool
extends Control
signal chosen(kind: String)
const SHAPES := preload("res://addons/branch_level_editor/runtime/whitebox_shapes.gd")
var kind := "box"
var title := "方块"
var selected := false:
	set(value): selected = value; queue_redraw()
var _faces: Array = []
func _ready() -> void:
	custom_minimum_size = custom_minimum_size.max(Vector2(112, 104))
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	tooltip_text = title + " · 拖入三维视口；默认 1×1×1；拉伸步长 0.1"
	if SHAPES.LABELS.has(kind):
		var mesh := SHAPES.mesh_for(kind, Vector3.ONE, 6, 0.2, 360 if kind == "tube" else 90)
		var triangles := mesh.get_faces()
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
			for v in [a, b, c]: points.append(Vector2(v.dot(right), -v.dot(up)))
			_faces.append({"points": points, "depth": ((a + b + c) / 3).dot(view), "shade": 0.55 + 0.4 * maxf(normal.dot(Vector3(0.4, 1, 0.6).normalized()), 0)})
		_faces.sort_custom(func(a: Dictionary, b: Dictionary): return a.depth < b.depth)
func _draw() -> void:
	draw_style_box(_style(), Rect2(Vector2.ZERO, size))
	var center := Vector2(size.x * 0.5, (size.y - 25) * 0.52)
	var factor := minf(size.x * 0.58, (size.y - 25) * 0.78)
	for face in _faces:
		var points := PackedVector2Array()
		for p in face.points: points.append(center + p * factor)
		draw_colored_polygon(points, Color("a1c7de") * float(face.shade))
	if _faces.is_empty():
		draw_rect(Rect2(Vector2(25, 12), Vector2(size.x - 50, size.y - 45)), Color("66b5b0"), false, 2)
		if kind == "room": draw_line(Vector2(25, 28), Vector2(size.x - 25, 28), Color("66b5b0"), 2)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(maxf(4, (size.x - width) * 0.5), size.y - 9), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e4edf3"))
func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("344c62") if selected else Color("253241")
	style.set_corner_radius_all(6)
	style.set_border_width_all(2 if selected else 1)
	style.border_color = Color("69d2df") if selected else Color("45596a")
	return style
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: chosen.emit(kind)
func drag_payload() -> Dictionary:
	return {"type": "files", "files": PackedStringArray(["res://addons/branch_level_editor/palette_assets/" + kind + ".tscn"])}
func _get_drag_data(_at: Vector2) -> Variant:
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(112, 104)
	var card: Control = get_script().new()
	card.kind = kind
	card.title = title
	card.size = Vector2(112, 104)
	preview.add_child(card)
	set_drag_preview(preview)
	chosen.emit(kind)
	return drag_payload()
