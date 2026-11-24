@tool
extends RefCounted
## The authored points, outlines and overrides are the source of truth.

static func empty() -> Dictionary:
	return {"version": 1, "features": [], "ridges": {}, "next_id": 1}

static func add(state: Dictionary, feature: Dictionary) -> int:
	var id: int = state.next_id
	state.next_id += 1
	feature.id = id
	state.features.append(feature)
	return id

static func peak(center: Vector2, height := 12.0, radius := 25.0, profile := 0) -> Dictionary:
	return {"kind": "peak", "center": center, "height": height, "radius": radius, "profile": profile}

static func river(points: PackedVector2Array, width := 5.0, depth := 1.4) -> Dictionary:
	return {"kind": "river", "points": points, "width": width, "depth": depth}

static func plateau(first: Vector2, last: Vector2, height := 9.0, shoulder := 14.0) -> Dictionary:
	var rect := Rect2(first, last - first).abs()
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	return {"kind": "plateau", "points": points, "height": height, "shoulder": shoulder}

static func find(state: Dictionary, id: int) -> Dictionary:
	for feature: Dictionary in state.features:
		if feature.id == id:
			return feature
	return {}

static func remove(state: Dictionary, id: int) -> void:
	state.features = state.features.filter(func(feature: Dictionary) -> bool: return feature.id != id)
	for key: String in state.ridges.keys():
		if str(id) in key.split(":"):
			state.ridges.erase(key)

static func ridge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

static func _can_join(a: Dictionary, b: Dictionary) -> bool:
	var distance: float = a.center.distance_to(b.center)
	return distance > 0.3 and distance < (float(a.radius) + float(b.radius)) * 0.90

static func ridges(state: Dictionary) -> Array[Dictionary]:
	var peaks: Array = state.features.filter(func(feature: Dictionary) -> bool: return feature.kind == "peak")
	var result: Array[Dictionary] = []
	for i in peaks.size():
		for j in range(i + 1, peaks.size()):
			var a: Dictionary = peaks[i]
			var b: Dictionary = peaks[j]
			if not _can_join(a, b):
				continue
			var key := ridge_key(a.id, b.id)
			var settings: Dictionary = state.ridges.get(key, {})
			if settings.get("disabled", false):
				continue
			# Keep nearby chains readable by skipping a connection that has a closer intermediate peak.
			var distance: float = a.center.distance_squared_to(b.center)
			var shortcut := peaks.any(func(other: Dictionary) -> bool:
				return other != a and other != b and _can_join(a, other) and _can_join(b, other) \
					and a.center.distance_squared_to(other.center) < distance and b.center.distance_squared_to(other.center) < distance)
			if shortcut:
				continue
			var low: float = minf(a.height, b.height)
			result.append({
				"key": key, "a": a.center, "b": b.center, "first": a.height, "last": b.height,
				"height": clampf(settings.get("height", low * 0.55), 0.0, low),
				"width": minf(a.radius, b.radius) * 0.48, "edited": settings.has("height"),
			})
	return result

static func preset(index: int, center: Vector2) -> Dictionary:
	var state := empty()
	if index == 0:
		add(state, peak(center + Vector2(-17, -12), 15.0, 27.0))
		add(state, peak(center + Vector2(17, -12), 12.0, 25.0))
	else:
		add(state, plateau(center + Vector2(-26, -26), center + Vector2(2, -3), 10.0))
		add(state, river(PackedVector2Array([
			center + Vector2(-9, -9), center + Vector2(10, -3),
			center + Vector2(14, 12), center + Vector2(33, 21),
		]), 5.0))
	return state

static func center_of(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / maxi(1, points.size())

static func points_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

static func polygon_is_valid(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	var double_area := 0.0
	for i in points.size():
		var next := (i + 1) % points.size()
		double_area += points[i].cross(points[next])
		if points[i].distance_squared_to(points[next]) < 0.04:
			return false
		for j in range(i + 2, points.size()):
			var end := (j + 1) % points.size()
			if end != i and Geometry2D.segment_intersects_segment(points[i], points[next], points[j], points[end]) != null:
				return false
	return absf(double_area) >= 0.5
