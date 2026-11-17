extends VBoxContainer
const ENTRY := preload("res://addons/godot_level_editor/scripts/ui/task_tracker_entry.gd")
@export_range(0.01, 2.0) var strike_seconds := 0.25
@export_range(0.0, 2.0) var completed_hold_seconds := 0.25
@export_range(0.01, 2.0) var fade_out_seconds := 0.18
@export_range(0.01, 2.0) var fade_in_seconds := 0.25
var rows: Dictionary = {}
# Compatibility text for status listeners; only the two-level task rows are drawn.
var text := ""
var failure: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 14)
	failure = Label.new()
	failure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	failure.add_theme_color_override("font_color", Color("f0c7bc"))
	failure.add_theme_color_override("font_outline_color", Color("202a30"))
	failure.add_theme_constant_override("outline_size", 4)
	add_child(failure)
	failure.hide()
	hide()

func _row(id: String) -> VBoxContainer:
	if not rows.has(id):
		var row := ENTRY.new()
		row.timings = Vector4(strike_seconds, completed_hold_seconds, fade_out_seconds, fade_in_seconds)
		add_child(row)
		move_child(failure, get_child_count() - 1)
		rows[id] = row
		row.retired.connect(func():
			rows.erase(id)
			row.queue_free()
			visible = not rows.is_empty() or failure.visible)
	return rows[id]

func sync(entries: Array[Dictionary], error_text: String = "", notice: String = "") -> void:
	var keep := {}
	for entry in entries:
		var id := str(entry.event_id)
		keep[id] = true
		_row(id).sync(entry)
	for id in rows.keys():
		if not keep.has(id): rows[id].sync({})
	failure.text = "任务失败：" + error_text if not error_text.is_empty() else notice
	failure.visible = not failure.text.is_empty()
	visible = not rows.is_empty() or failure.visible

func complete(entry: Dictionary) -> void:
	_row(str(entry.event_id)).complete(entry)
	show()

func reset() -> void:
	for row in rows.values():
		remove_child(row)
		row.queue_free()
	rows.clear()
