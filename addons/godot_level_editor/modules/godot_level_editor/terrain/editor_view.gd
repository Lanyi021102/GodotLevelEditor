@tool
extends RefCounted
const LAYOUT := preload("layout.gd")
const INK := Color("182b41")
const PEAK := Color("ffe2ac")
const RIDGE := Color("fbba64")
const RIVER := Color("74cbff")
const PLATEAU := Color("a6e5ca")
const SELECTED := Color("fcffff")
const DEEP_CUT := Color("ffaf58")
const TOP_ITEM := 0
const PERSPECTIVE_ITEM := 10
const ORTHOGONAL_ITEM := 12

static func _viewport_owner(camera: Camera3D) -> Node:
	var owner: Node = camera.get_viewport()
	while owner != null and owner.get_class() != "Node3DEditorViewport":
		owner = owner.get_parent()
	return owner

static func belongs_to(camera: Camera3D, overlay: Control) -> bool:
	var owner := _viewport_owner(camera)
	return owner != null and owner.is_ancestor_of(overlay)

static func is_top(camera: Camera3D) -> bool:
	return camera.global_basis.z.y > 0.998

static func snapshot(camera: Camera3D) -> Dictionary:
	return {"pose": camera.global_transform, "projection": camera.projection, "size": camera.size}

static func _native_menu(camera: Camera3D) -> PopupMenu:
	var owner := _viewport_owner(camera)
	if owner == null:
		return null
	# Match the native viewport menu by its IDs and the top-view shortcut. The names are localized.
	for button in owner.find_children("*", "MenuButton", true, false):
		var popup: PopupMenu = button.get_popup()
		var top := popup.get_item_index(TOP_ITEM)
		if top >= 0 and popup.get_item_index(PERSPECTIVE_ITEM) >= 0 and popup.get_item_index(ORTHOGONAL_ITEM) >= 0 and popup.get_item_shortcut(top) != null:
			return popup
	return null

static func change(camera: Camera3D, top: bool) -> void:
	var popup := _native_menu(camera)
	if popup != null:
		popup.id_pressed.emit(TOP_ITEM if top else PERSPECTIVE_ITEM)

static func restore(camera: Camera3D, state: Dictionary) -> bool:
	var popup := _native_menu(camera)
	if state.is_empty() or popup == null:
		return false
	popup.id_pressed.emit(PERSPECTIVE_ITEM if state.projection == Camera3D.PROJECTION_PERSPECTIVE else ORTHOGONAL_ITEM)
	camera.set_deferred("global_transform", state.pose)
	camera.set_deferred("size", state.size)
	return true

static func meters_per_pixel(camera: Camera3D, point: Vector3) -> float:
	var position := camera.unproject_position(point)
	var plane := Plane(camera.global_basis.z, point)
	var other: Variant = plane.intersects_ray(camera.project_ray_origin(position + Vector2.DOWN), camera.project_ray_normal(position + Vector2.DOWN))
	return clampf(point.distance_to(other), 0.02, 7.0) if other != null else 0.15

static func _project(camera: Camera3D, basis: Transform3D, at: Vector2, height: float) -> Variant:
	var world := basis * Vector3(at.x, height, at.y)
	return null if camera.is_position_behind(world) else camera.unproject_position(world)

static func _push_handle(target: Array[Dictionary], camera: Camera3D, basis: Transform3D, info: Dictionary) -> void:
	var screen: Variant = _project(camera, basis, info.at, info.y)
	if screen == null:
		return
	info.screen = screen
	if info.kind == "height":
		info.origin = screen
		info.screen += Vector2(0, -26) * EditorInterface.get_editor_scale()
	target.append(info)

static func handles(camera: Camera3D, basis: Transform3D, surface: RefCounted, state: Dictionary, selected: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for feature: Dictionary in state.features:
		var focus: bool = feature.id == selected
		match feature.kind:
			"peak":
				_push_handle(result, camera, basis, {"id": feature.id, "kind": "center", "at": feature.center, "y": feature.height, "color": PEAK})
				if focus:
					_push_handle(result, camera, basis, {"id": feature.id, "kind": "height", "at": feature.center, "y": feature.height, "color": PEAK})
					var edge: Vector2 = feature.center + Vector2.RIGHT * feature.radius
					_push_handle(result, camera, basis, {"id": feature.id, "kind": "radius", "at": edge, "y": surface.height_at(edge), "color": PEAK})
			"river", "plateau":
				var is_river: bool = feature.kind == "river"
				var color := RIVER if is_river else PLATEAU
				var points: PackedVector2Array = feature.points
				if is_river or focus:
					for i in points.size():
						_push_handle(result, camera, basis, {"id": feature.id, "kind": "vertex", "index": i, "at": points[i], "y": surface.height_at(points[i]), "color": color})
				if is_river and focus:
					var i := floori((points.size() - 1) * 0.5)
					var middle := (points[i] + points[i + 1]) * 0.5
					var normal := (points[i + 1] - points[i]).orthogonal().normalized()
					var edge: Vector2 = middle + normal * feature.width * 0.5
					_push_handle(result, camera, basis, {"id": feature.id, "kind": "width", "at": edge, "y": surface.height_at(edge), "color": color, "middle": middle, "normal": normal})
				elif not is_river:
					var center := LAYOUT.center_of(points)
					_push_handle(result, camera, basis, {"id": feature.id, "kind": "move", "at": center, "y": feature.height, "color": color})
					if focus:
						_push_handle(result, camera, basis, {"id": feature.id, "kind": "height", "at": center, "y": feature.height, "color": color})
	for ridge: Dictionary in surface.ridges:
		var center: Vector2 = (ridge.a + ridge.b) * 0.5
		_push_handle(result, camera, basis, {"id": 0, "kind": "ridge", "ridge": ridge.key, "at": center,
			"y": surface.height_at(center), "height": ridge.height, "limit": minf(ridge.first, ridge.last), "color": RIDGE})
	return result

static func edge_at(camera: Camera3D, basis: Transform3D, surface: RefCounted, points: PackedVector2Array, cursor: Vector2) -> int:
	var closest := -1
	var distance := 12.0 * EditorInterface.get_editor_scale()
	for i in points.size():
		var a: Variant = _project(camera, basis, points[i], surface.height_at(points[i]))
		var point := points[(i + 1) % points.size()]
		var b: Variant = _project(camera, basis, point, surface.height_at(point))
		if a == null or b == null:
			continue
		var current := cursor.distance_to(Geometry2D.get_closest_point_to_segment(cursor, a, b))
		if current < distance:
			distance = current
			closest = i
	return closest

static func ridge_handle_at(camera: Camera3D, basis: Transform3D, surface: RefCounted, markers: Array[Dictionary], cursor: Vector2) -> Dictionary:
	for ridge: Dictionary in surface.ridges:
		var distance := 9.0 * EditorInterface.get_editor_scale()
		var previous: Variant = null
		for i in 17:
			var point: Vector2 = ridge.a.lerp(ridge.b, float(i) / 16.0)
			var at: Variant = _project(camera, basis, point, surface.height_at(point))
			if previous != null and at != null and cursor.distance_to(Geometry2D.get_closest_point_to_segment(cursor, previous, at)) < distance:
				for marker in markers:
					if marker.get("ridge") == ridge.key:
						return marker
			previous = at
	return {}

static func _surface_outline(control: Control, camera: Camera3D, basis: Transform3D, surface: RefCounted, points: PackedVector2Array, color: Color) -> void:
	var previous: Variant = null
	for point in points:
		var at: Variant = _project(camera, basis, point, surface.height_at(point))
		if previous != null and at != null:
			control.draw_line(previous, at, color, 1.6, true)
		previous = at

static func draw(control: Control, camera: Camera3D, basis: Transform3D, surface: RefCounted, state: Dictionary, selected: int, selected_ridge: String, show_handles: bool) -> void:
	var scale := EditorInterface.get_editor_scale()
	for feature: Dictionary in state.features:
		if feature.kind == "plateau":
			var points: PackedVector2Array = feature.points.duplicate()
			points.append(points[0])
			_surface_outline(control, camera, basis, surface, points, PLATEAU)
		elif feature.kind == "peak" and (not show_handles or feature.id == selected):
			var footprint := PackedVector2Array()
			for i in 49:
				footprint.append(feature.center + Vector2.from_angle(float(i) * TAU / 48.0) * feature.radius)
			_surface_outline(control, camera, basis, surface, footprint, Color(PEAK, 0.68))
	for ridge: Dictionary in surface.ridges:
		var points := PackedVector2Array()
		for i in 17:
			points.append(ridge.a.lerp(ridge.b, float(i) / 16.0))
		_surface_outline(control, camera, basis, surface, points, SELECTED if selected_ridge == ridge.key else RIDGE)
	for river: Dictionary in surface.rivers:
		var points: PackedVector2Array = river.points
		var previous: Variant = null
		for i in points.size():
			var at: Variant = _project(camera, basis, points[i], surface.height_at(points[i]))
			if previous != null and at != null:
				var color := DEEP_CUT if river.cuts[i] else RIVER
				control.draw_line(previous, at, color, 2.6 * scale, true)
			previous = at
	if not show_handles:
		return
	for handle: Dictionary in handles(camera, basis, surface, state, selected):
		var color: Color = SELECTED if (handle.id > 0 and handle.id == selected) or (handle.has("ridge") and handle.ridge == selected_ridge) else handle.color
		var position: Vector2 = handle.screen
		var radius := 6.0 * scale
		if handle.has("origin"):
			control.draw_line(handle.origin, position, color, 1.4 * scale, true)
		if handle.kind in ["ridge", "height", "radius", "width"]:
			control.draw_rect(Rect2(position - Vector2.ONE * radius, Vector2.ONE * radius * 2), INK)
			control.draw_rect(Rect2(position - Vector2.ONE * (radius - 2), Vector2.ONE * (radius - 2) * 2), color)
		else:
			control.draw_circle(position, radius + scale, INK, true, -1.0, true)
			control.draw_circle(position, radius - scale, color, true, -1.0, true)
