@tool
extends Control
signal curve_edited(value: Curve)
var curve: Curve
var progress := -1.0
var editable := true
var _drag := -1
const INK := Color("244568")

func _init() -> void:
	custom_minimum_size = Vector2(250, 125)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "横轴：动画时间；纵轴：0° 到 90°。左键添加/拖动曲线点，右键删除中间点；起终点固定。"

func plot() -> Rect2: return Rect2(Vector2(30, 12), size - Vector2(43, 38))
func point_position(value: Vector2) -> Vector2:
	var rect := plot()
	return rect.position + Vector2(value.x, 1 - value.y) * rect.size
func nearest(at: Vector2) -> int:
	if curve == null: return -1
	var index := -1; var distance := 10.0
	for i in curve.point_count:
		var candidate := at.distance_to(point_position(curve.get_point_position(i)))
		if candidate < distance: index = i; distance = candidate
	return index

func _gui_input(event: InputEvent) -> void:
	if not editable or curve == null: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag = nearest(event.position)
				if _drag == 0 or _drag == curve.point_count - 1:
					_drag = -1; accept_event(); return
				if _drag < 0 and plot().has_point(event.position):
					curve = curve.duplicate(true); _drag = curve.add_point(_normalized(event.position)); queue_redraw()
				elif _drag >= 0: curve = curve.duplicate(true)
			else:
				if _drag >= 0: curve_edited.emit(curve.duplicate(true))
				_drag = -1
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var index := nearest(event.position)
			if index > 0 and index < curve.point_count - 1:
				curve = curve.duplicate(true); curve.remove_point(index); curve_edited.emit(curve.duplicate(true)); queue_redraw()
			accept_event()
	if event is InputEventMouseMotion and _drag > 0 and _drag < curve.point_count - 1:
		var value := _normalized(event.position)
		value.x = clampf(value.x, curve.get_point_position(_drag - 1).x + 0.01, curve.get_point_position(_drag + 1).x - 0.01)
		_drag = curve.set_point_offset(_drag, value.x); curve.set_point_value(_drag, value.y)
		queue_redraw(); accept_event()

func _normalized(at: Vector2) -> Vector2:
	var rect := plot(); var value := (at - rect.position) / rect.size
	return Vector2(clampf(value.x, 0.01, 0.99), clampf(1 - value.y, 0, 1))

func _draw() -> void:
	var rect := plot(); var font := get_theme_default_font()
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for i in 5:
		var x := rect.position.x + rect.size.x * i / 4.0; var y := rect.position.y + rect.size.y * i / 4.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color("dce5ee"))
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color("dce5ee"))
	draw_string(font, Vector2(1, rect.position.y + 8), "90°", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	draw_string(font, Vector2(5, rect.end.y), "0°", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	draw_string(font, Vector2(rect.position.x, rect.end.y + 18), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	draw_string(font, Vector2(rect.end.x - 45, rect.end.y + 18), "时间 100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	if curve != null:
		var points := PackedVector2Array()
		for i in 81:
			var t := i / 80.0; points.append(point_position(Vector2(t, clampf(curve.sample(t), 0, 1))))
		draw_polyline(points, Color("2563eb"), 2.5, true)
		for i in curve.point_count: draw_circle(point_position(curve.get_point_position(i)), 4, Color("2563eb"))
		if progress >= 0:
			var at := point_position(Vector2(progress, clampf(curve.sample(progress), 0, 1)))
			draw_line(Vector2(at.x, rect.position.y), Vector2(at.x, rect.end.y), Color("40a47d"), 1.5)
			draw_circle(at, 5, Color("40a47d"))

func _background() -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color = Color("f5f8fc"); box.set_corner_radius_all(5)
	return box
