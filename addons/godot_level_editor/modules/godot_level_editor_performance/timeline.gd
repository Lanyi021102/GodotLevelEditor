@tool
extends Control

signal seek_requested(time: float)
signal selected(clip_id: String)
signal clip_changed(clip_id: String, start: float, duration: float)

const DATA := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sequence.gd")
const HEADER := 142.0
const RULER := 27.0
const ROW := 32.0
const SCALE := 84.0
const SNAP := 0.1

var data: Resource
var names := {}
var time := 0.0
var selected_id := ""
var _tracks: Array[String] = []
var _drag := {}
var _scrubbing := false

func update_timeline(sequence: Resource, actors: Dictionary, active_id: String) -> void:
	data = sequence
	names = actors
	selected_id = active_id
	_tracks = [""]
	if data != null:
		for actor in data.actors:
			_tracks.append(actor + "/pose")
			_tracks.append(actor + "/action")
	_rescale()
	queue_redraw()

func _rescale() -> void:
	var end: float = data.duration() if data != null else 0.0
	if not _drag.is_empty(): end = maxf(end, _drag.start + _drag.duration)
	custom_minimum_size = Vector2(HEADER + SCALE * maxf(8.0, ceilf(end) + 1.0), RULER + _tracks.size() * ROW)

func set_time(value: float) -> void:
	time = value
	queue_redraw()

func _rect(clip: Dictionary) -> Rect2:
	var row := _tracks.find(DATA.track_of(clip))
	var start := float(clip.start)
	var duration := float(clip.duration)
	if _drag.get("id") == clip.id:
		start = _drag.start
		duration = _drag.duration
	return Rect2(HEADER + start * SCALE, RULER + row * ROW + 3, duration * SCALE, ROW - 6)

func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color("f8fafd"))
	for row in _tracks.size():
		var y := RULER + ROW * row
		draw_rect(Rect2(0, y, size.x, ROW), Color("f2f5fa") if row % 2 == 0 else Color("ffffff"))
		var track := _tracks[row]
		var actor := track.get_base_dir().trim_suffix("/")
		var caption := "镜头" if track.is_empty() else str(names.get(actor, "缺失 NPC")) + ("  动作" if track.ends_with("/action") else "  走位")
		draw_string(font, Vector2(8, y + 21), caption, HORIZONTAL_ALIGNMENT_LEFT, HEADER - 16, 13, Color("334155"))
		draw_line(Vector2(0, y + ROW), Vector2(size.x, y + ROW), Color("e2e8f0"))
	for tick in range(ceili((size.x - HEADER) / SCALE) + 1):
		var x := HEADER + tick * SCALE
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("dce3ee"))
		draw_string(font, Vector2(x + 4, 19), "%d 秒" % tick, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("4e6076"))
	if data != null:
		for clip in data.clips:
			if not DATA.track_of(clip) in _tracks: continue
			var rect := _rect(clip)
			var color: Color = {"camera": Color("2363bd"), "action": Color("6e51a3")}.get(clip.kind, Color("187a72"))
			draw_rect(rect, color)
			if rect.size.x >= 18:
				draw_string(font, rect.position + Vector2(5, 18), str(clip.label), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 9, 13, Color.WHITE)
			if selected_id == clip.id:
				draw_rect(rect, Color("0f172a"), false, 2)
				if clip.kind not in ["place", "turn"]: draw_line(rect.end - Vector2(4, 5), Vector2(rect.end.x - 4, rect.position.y + 5), Color.WHITE, 1)
	var x := HEADER + time * SCALE
	draw_line(Vector2(x, 0), Vector2(x, size.y), Color("c53936"), 2)

func _gui_input(event: InputEvent) -> void:
	if data == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.x >= HEADER:
			_press(event.position)
			accept_event()
		elif not event.pressed and (not _drag.is_empty() or _scrubbing):
			var result := _drag
			_drag = {}
			_scrubbing = false
			if not result.is_empty() and (result.start != result.original_start or result.duration != result.original_duration):
				clip_changed.emit(result.id, result.start, result.duration)
			_rescale()
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		if not _drag.is_empty():
			var delta: float = (event.position.x - float(_drag.x)) / SCALE
			if _drag.resize:
				_drag.duration = clampf(snappedf(_drag.original_duration + delta, SNAP), DATA.MIN_LENGTH, DATA.MAX_TIME - _drag.start)
			else:
				_drag.start = clampf(snappedf(_drag.original_start + delta, SNAP), 0.0, DATA.MAX_TIME - _drag.duration)
			_rescale()
			queue_redraw()
			accept_event()
		elif _scrubbing:
			_seek(event.position.x)
			accept_event()

func _press(position: Vector2) -> void:
	for clip in data.clips:
		if not DATA.track_of(clip) in _tracks: continue
		var rect := _rect(clip)
		if not rect.has_point(position): continue
		var resize: bool = clip.kind not in ["place", "turn"] and rect.end.x - position.x <= minf(8.0, rect.size.x * 0.3)
		_drag = {"id": clip.id, "x": position.x, "resize": resize, "start": float(clip.start), "duration": float(clip.duration), "original_start": float(clip.start), "original_duration": float(clip.duration)}
		selected.emit(clip.id)
		return
	_scrubbing = true
	_seek(position.x)

func _seek(x: float) -> void:
	seek_requested.emit(clampf(snappedf((x - HEADER) / SCALE, SNAP), 0.0, DATA.MAX_TIME))
