extends CanvasLayer
signal dialogue_completed(dialog_id: String)
signal opened
signal closed
var library: Resource
var active_group := ""
var index := 0
var completed: Dictionary = {}
var _lines: Array = []
var _was_paused := false
var _opened_frame := 0
var _remaining_seconds := 0.0
var panel: VBoxContainer
var subtitle: RichTextLabel

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("godot_level_editor_dialogue_player")
	panel = VBoxContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = -108
	panel.offset_bottom = -68
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle = RichTextLabel.new()
	subtitle.fit_content = true
	subtitle.scroll_active = false
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.add_theme_font_size_override("normal_font_size", 22)
	subtitle.add_theme_color_override("default_color", Color.WHITE)
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	subtitle.add_theme_constant_override("outline_size", 3)
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	panel.add_child(subtitle)
	panel.hide()

func is_active() -> bool: return not active_group.is_empty()

func show_dialog(id: String) -> bool:
	if is_active() or library == null or not library.validate().is_empty(): return false
	var comment: Dictionary = library.comment_by_id(id)
	if comment.is_empty() or comment.lines.is_empty(): return false
	_lines = comment.lines.duplicate(true)
	active_group = id
	index = 0
	_was_paused = get_tree().paused
	get_tree().paused = true
	_opened_frame = Engine.get_process_frames()
	panel.show()
	_render_line()
	opened.emit()
	return true

func _process(delta: float) -> void:
	if not is_active(): return
	_remaining_seconds -= delta
	if _remaining_seconds <= 0.0: advance()

func _input(event: InputEvent) -> void:
	if not is_active(): return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if not event.is_echo(): advance()
		get_viewport().set_input_as_handled()

func advance() -> void:
	if not is_active() or Engine.get_process_frames() <= _opened_frame: return
	var line_id := str(_lines[index].id)
	completed[line_id] = true
	dialogue_completed.emit(line_id)
	index += 1
	if index < _lines.size():
		_render_line()
		return
	var id := active_group
	completed[id] = true
	active_group = ""
	panel.hide()
	get_tree().paused = _was_paused
	dialogue_completed.emit(id)
	closed.emit()

func _render_line() -> void:
	var line: Dictionary = _lines[index]
	_remaining_seconds = library.playback_duration(line)
	subtitle.clear()
	subtitle.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.push_color(library.speakers.get(line.speaker, Color("bfc5ca")))
	subtitle.add_text(str(line.speaker) + "： ")
	subtitle.pop()
	subtitle.push_color(Color.WHITE)
	subtitle.add_text(str(line.text))
	subtitle.pop()
	subtitle.pop()

func _exit_tree() -> void:
	if is_active():
		get_tree().paused = _was_paused
