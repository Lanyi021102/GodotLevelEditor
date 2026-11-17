@tool
extends FontFile
## Resolve local Song/Songti fonts without bundling system font files.
const FAMILIES := ["Songti SC", "STSong", "SimSun", "NSimSun", "Noto Serif CJK SC", "Source Han Serif SC", "Songti TC"]
static var _sources: Dictionary = {}
static var _faces: Dictionary = {}
static var _fonts: Dictionary = {}

func _init() -> void:
	_configure(self, 400, false, 64)

func _validate_property(property: Dictionary) -> void:
	# System font bytes and fallback caches are computed locally, never saved.
	if property.name in ["data", "fallbacks"]: property.usage &= ~PROPERTY_USAGE_STORAGE

static func make(weight := 400, msdf := true, msdf_size := 64) -> FontFile:
	var key := "%d:%s:%d" % [weight, msdf, msdf_size]
	if not _fonts.has(key):
		var font := FontFile.new()
		_configure(font, weight, msdf, msdf_size)
		_fonts[key] = font
	return _fonts[key]

static func _source(weight: int) -> Dictionary:
	if _faces.has(weight): return _faces[weight]
	var best := {}; var best_score := -100000
	for family in FAMILIES:
		var path := OS.get_system_font_path(family, weight)
		if path.is_empty(): continue
		if not _sources.has(path): _sources[path] = FileAccess.get_file_as_bytes(path)
		var bytes: PackedByteArray = _sources[path]
		var probe := FontFile.new(); probe.data = bytes
		for index in probe.get_face_count():
			var candidate := FontFile.new()
			# Setting the face before supplying bytes avoids a cached first-face
			# glyph map (Songti's first face is Black with reduced CJK coverage).
			candidate.set_face_index(0, index)
			candidate.data = bytes
			var name := candidate.get_font_name()
			if not FAMILIES.has(name): continue
			var score := 10000 - absi(candidate.get_font_weight() - weight)
			if name == family: score += 1000
			if score > best_score:
				best_score = score; best = {"path": path, "face": index}
		if not best.is_empty(): break
	_faces[weight] = best
	return best

static func _configure(font: FontFile, weight: int, msdf: bool, msdf_size: int) -> void:
	font.multichannel_signed_distance_field = msdf
	font.msdf_size = msdf_size
	font.allow_system_fallback = true
	var source := _source(weight)
	if not source.is_empty():
		font.set_face_index(0, source.face)
		font.data = _sources[source.path]
	var symbols := SystemFont.new()
	symbols.font_names = PackedStringArray(["Apple Symbols", "Segoe UI Symbol", "Noto Sans Symbols 2", "DejaVu Sans"])
	symbols.multichannel_signed_distance_field = msdf; symbols.msdf_size = msdf_size
	var marks := SystemFont.new()
	marks.font_names = PackedStringArray(["Arial Unicode MS", "Segoe UI Symbol", "DejaVu Sans"])
	marks.multichannel_signed_distance_field = msdf; marks.msdf_size = msdf_size
	font.fallbacks = [symbols, marks]
	if source.is_empty():
		var system := SystemFont.new(); system.font_names = PackedStringArray(FAMILIES)
		system.font_weight = weight; system.multichannel_signed_distance_field = msdf; system.msdf_size = msdf_size
		font.fallbacks = [system, symbols, marks]
