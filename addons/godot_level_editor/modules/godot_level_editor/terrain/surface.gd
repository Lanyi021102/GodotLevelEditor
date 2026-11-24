@tool
extends RefCounted
const LAYOUT := preload("layout.gd")
const GRID_LIMIT := 160
const DRAFT_LIMIT := 64
const BASE_SIZE := 72.0

var state: Dictionary
var bounds := Rect2()
var peaks: Array[Dictionary] = []
var plateaus: Array[Dictionary] = []
var ridges: Array[Dictionary] = []
var rivers: Array[Dictionary] = []

func _init(layout: Dictionary) -> void:
	state = layout
	bounds = Rect2(-Vector2.ONE * BASE_SIZE * 0.5, Vector2.ONE * BASE_SIZE)
	for feature: Dictionary in state.features:
		match feature.kind:
			"peak":
				var radius: float = feature.radius
				var area := Rect2(feature.center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
				peaks.append({"id": feature.id, "area": area, "feature": feature})
				bounds = bounds.merge(area.grow(5.0))
			"plateau":
				var area := LAYOUT.points_bounds(feature.points).grow(feature.shoulder)
				plateaus.append({"area": area, "feature": feature})
				bounds = bounds.merge(area.grow(5.0))
	ridges = LAYOUT.ridges(state)
	for ridge in ridges:
		ridge.area = Rect2(ridge.a, ridge.b - ridge.a).abs().grow(ridge.width)
	for entry in peaks:
		var peak: Dictionary = entry.feature
		entry.crest = maxf(0.15, peak.radius * 0.2)
		for other in peaks:
			if entry.id != other.id:
				entry.crest = minf(entry.crest, peak.center.distance_to(other.feature.center) * 0.38)
	for feature: Dictionary in state.features:
		if feature.kind == "river":
			_add_river(feature)

func _peak_height(peak: Dictionary, delta: Vector2) -> float:
	var fraction: float = delta.length() / peak.radius
	if fraction >= 1.0:
		return 0.0
	var weight := 1.0 - smoothstep(0.0, 1.0, fraction)
	if peak.profile == 1:
		weight = pow(weight, 1.6)
	# Small, repeatable radial folds vanish at the crest and at the perimeter.
	var angle := delta.angle() + float(peak.id) * 0.73
	var amplitude := 0.075 if peak.profile == 1 else 0.055
	var folds := (sin(angle * 5.0 + fraction * 1.8) + sin(angle * 9.0 - fraction)) * amplitude
	return peak.height * minf(1.0, weight * (1.0 + folds * pow(sin(fraction * PI), 2)))

func _uplift(at: Vector2) -> float:
	var elevation := 0.0
	for entry in peaks:
		if entry.area.has_point(at):
			elevation = maxf(elevation, _peak_height(entry.feature, at - entry.feature.center))
	for ridge in ridges:
		if not ridge.area.has_point(at):
			continue
		var a: Vector2 = ridge.a
		var b: Vector2 = ridge.b
		var along := clampf((at - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
		var across := at.distance_to(a.lerp(b, along))
		var side := 1.0 - smoothstep(0.0, ridge.width, across)
		var target: float = lerpf(ridge.first if along < 0.5 else ridge.last, ridge.height, smoothstep(0.0, 1.0, 1.0 - absf(along * 2.0 - 1.0)))
		if ridge.edited and target < elevation:
			var middle := smoothstep(0.06, 0.37, minf(along, 1.0 - along))
			elevation = lerpf(elevation, target, middle * side)
		else:
			elevation = maxf(elevation, target * side)
	for entry in plateaus:
		if not entry.area.has_point(at):
			continue
		var plateau: Dictionary = entry.feature
		var polygon: PackedVector2Array = plateau.points
		if Geometry2D.is_point_in_polygon(at, polygon):
			elevation = maxf(elevation, plateau.height)
			continue
		var distance := INF
		for i in polygon.size():
			distance = minf(distance, at.distance_to(Geometry2D.get_closest_point_to_segment(at, polygon[i], polygon[(i + 1) % polygon.size()])))
		elevation = maxf(elevation, plateau.height * (1.0 - smoothstep(0.0, plateau.shoulder, distance)))
	for entry in peaks:
		if not entry.area.has_point(at):
			continue
		var peak: Dictionary = entry.feature
		var offset: Vector2 = at - peak.center
		var distance := offset.length()
		if distance < entry.crest:
			var own_height := _peak_height(peak, offset)
			if elevation > own_height:
				elevation = lerpf(own_height, elevation, smoothstep(entry.crest * 0.42, entry.crest, distance))
	return elevation

func _add_river(feature: Dictionary) -> void:
	var points: PackedVector2Array = feature.points
	if points.size() < 2:
		return
	var curve := Curve2D.new()
	curve.bake_interval = maxf(0.9, feature.width * 0.17)
	for i in points.size():
		var point := points[i]
		var previous: Vector2 = points[maxi(0, i - 1)]
		var next: Vector2 = points[mini(i + 1, points.size() - 1)]
		var tangent := (next - previous).normalized() * minf(point.distance_to(previous), point.distance_to(next)) * 0.28
		curve.add_point(point, -tangent, tangent)
	var samples := curve.get_baked_points()
	if samples.size() < 2:
		return
	var radius: float = feature.width * 0.5
	var bank := maxf(radius * 1.7, radius + 2.0)
	var reach := LAYOUT.points_bounds(samples).grow(bank)
	bounds = bounds.merge(reach.grow(5.0))
	var beds := PackedFloat32Array()
	var cuts := PackedByteArray()
	for i in samples.size():
		var ground := _uplift(samples[i])
		var bed: float = ground - feature.depth
		if i > 0:
			bed = minf(bed, beds[i - 1] - samples[i - 1].distance_to(samples[i]) * 0.014)
		beds.append(bed)
		cuts.append(1 if ground - bed > feature.depth + 2.5 else 0)
	var cells := {}
	var tile_size := maxf(bank, 6.0)
	for i in range(samples.size() - 1):
		var segment := Rect2(samples[i], samples[i + 1] - samples[i]).abs().grow(bank)
		var first := Vector2i((segment.position / tile_size).floor())
		var last := Vector2i((segment.end / tile_size).floor())
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				var tile := Vector2i(x, y)
				if not cells.has(tile):
					cells[tile] = []
				cells[tile].append(i)
	rivers.append({"id": feature.id, "points": samples, "beds": beds, "cuts": cuts,
		"area": reach, "radius": radius, "bank": bank, "tiles": cells, "tile_size": tile_size})

func height_at(at: Vector2) -> float:
	var elevation := _uplift(at)
	for river in rivers:
		if not river.area.has_point(at):
			continue
		var tile := Vector2i((at / float(river.tile_size)).floor())
		var candidates: Array = river.tiles.get(tile, [])
		var points: PackedVector2Array = river.points
		var beds: PackedFloat32Array = river.beds
		var shallower := elevation
		for i: int in candidates:
			var a := points[i]
			var ab := points[i + 1] - a
			var t := clampf((at - a).dot(ab) / maxf(ab.length_squared(), 0.00001), 0.0, 1.0)
			var distance := (at - a - ab * t).length()
			if distance < river.bank:
				var bed := lerpf(beds[i], beds[i + 1], t)
				var bank_factor := smoothstep(river.radius * 0.70, river.bank, distance)
				shallower = minf(shallower, lerpf(bed, elevation, bank_factor))
		elevation = shallower
	return elevation

func _axis(start: float, finish: float, count: int, axis: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for i in range(count + 1):
		values.append(lerpf(start, finish, float(i) / count))
	for entry in peaks:
		var center: Vector2 = entry.feature.center
		values.append(center[axis])
	values.sort()
	var unique := PackedFloat32Array()
	for value in values:
		if unique.is_empty() or not is_equal_approx(unique[-1], value):
			unique.append(value)
	return unique

func mesh(draft := false) -> ArrayMesh:
	var limit := DRAFT_LIMIT if draft else GRID_LIMIT
	var spacing := maxf(1.5 if draft else 0.85, maxf(bounds.size.x, bounds.size.y) / limit)
	var xs := _axis(bounds.position.x, bounds.end.x, maxi(2, ceili(bounds.size.x / spacing)), 0)
	var ys := _axis(bounds.position.y, bounds.end.y, maxi(2, ceili(bounds.size.y / spacing)), 1)
	var stride := xs.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(stride * ys.size())
	normals.resize(vertices.size())
	for y in ys.size():
		for x in stride:
			vertices[y * stride + x] = Vector3(xs[x], height_at(Vector2(xs[x], ys[y])), ys[y])
	for y in ys.size():
		for x in stride:
			var i := y * stride + x
			var dx := vertices[y * stride + mini(x + 1, stride - 1)] - vertices[y * stride + maxi(x - 1, 0)]
			var dz := vertices[mini(y + 1, ys.size() - 1) * stride + x] - vertices[maxi(y - 1, 0) * stride + x]
			normals[i] = dz.cross(dx).normalized()
			if x < stride - 1 and y < ys.size() - 1:
				indices.append_array(PackedInt32Array([i, i + 1, i + stride, i + 1, i + stride + 1, i + stride]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
