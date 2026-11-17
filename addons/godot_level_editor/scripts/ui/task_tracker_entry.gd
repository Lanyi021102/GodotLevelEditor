extends VBoxContainer
signal retired
const LINE := preload("res://addons/godot_level_editor/scenes/ui/task_tracker_line.tscn")
var title_line: Control
var task_line: Control
var desired: Dictionary = {}
var completions: Array[Dictionary] = []
var seen: Dictionary = {}
var busy := false
var displayed_task := ""
var motion: Tween
var timings := Vector4(0.25, 0.25, 0.18, 0.25)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	title_line = LINE.instantiate()
	title_line.heading = true
	add_child(title_line)
	var indent := MarginContainer.new()
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indent.add_theme_constant_override("margin_left", 26)
	add_child(indent)
	task_line = LINE.instantiate()
	indent.add_child(task_line)

func sync(entry: Dictionary) -> void:
	desired = entry.duplicate(true)
	if busy: return
	if desired.is_empty(): retired.emit(); return
	title_line.set_text(str(desired.event))
	if displayed_task != str(desired.task_id):
		_show_task(desired)
		if motion != null: motion.kill()
		task_line.modulate.a = 0
		motion = create_tween()
		motion.tween_property(task_line, "modulate:a", 1.0, timings.w)

func _show_task(entry: Dictionary) -> void:
	displayed_task = str(entry.task_id)
	title_line.set_text(str(entry.event))
	task_line.set_text(str(entry.task))
	task_line.strike = 0
	task_line.modulate.a = 1
	task_line.visible = not str(entry.task).is_empty()

func complete(entry: Dictionary) -> void:
	if seen.has(entry.task_id): return
	seen[entry.task_id] = true
	completions.append(entry.duplicate(true))
	if not busy: _animate_completions()

func _animate_completions() -> void:
	busy = true
	if motion != null: motion.kill()
	while not completions.is_empty():
		var entry: Dictionary = completions.pop_front()
		var changed := displayed_task != str(entry.task_id)
		_show_task(entry)
		motion = create_tween()
		if changed:
			task_line.modulate.a = 0
			motion.tween_property(task_line, "modulate:a", 1.0, timings.w)
		motion.tween_property(task_line, "strike", 1.0, timings.x)
		motion.tween_interval(timings.y)
		motion.tween_property(task_line, "modulate:a", 0.0, timings.z)
		await motion.finished
	busy = false
	if desired.is_empty(): retired.emit(); return
	_show_task(desired)
	if seen.has(desired.task_id):
		task_line.strike = 1
		return
	task_line.modulate.a = 0
	motion = create_tween()
	motion.tween_property(task_line, "modulate:a", 1.0, timings.w)

func _exit_tree() -> void:
	if motion != null: motion.kill()
