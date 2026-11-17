@tool
extends HBoxContainer
signal value_changed(value: float)
signal invalid_input(message: String)
var clock := LineEdit.new()
var slider := HSlider.new()
var _value := 12.0
var value: float:
	get: return _value
	set(next):
		if is_equal_approx(next, _value): return
		set_value_no_signal(next); value_changed.emit(_value)
var editable := true:
	set(next):
		editable = next
		clock.editable = next
		slider.editable = next
func _init() -> void:
	add_theme_constant_override("separation", 12)
	clock.custom_minimum_size = Vector2(118, 34)
	clock.alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.placeholder_text = "HH:MM"
	clock.max_length = 5
	clock.tooltip_text = "输入时:分，例如 07:30；也可拖动右侧滑块。"
	slider.min_value = 0; slider.max_value = 24; slider.step = 1.0 / 60.0
	slider.custom_minimum_size.x = 170; slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(clock); add_child(slider)
	preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/slider_style.gd").apply(slider)
	clock.text_submitted.connect(func(_text: String): commit_text())
	clock.focus_exited.connect(commit_text)
	slider.value_changed.connect(func(next: float): value = next)
	set_value_no_signal(_value)
func commit_text() -> void:
	var parts := clock.text.strip_edges().split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		_reject(); return
	var hours := int(parts[0]); var minutes := int(parts[1])
	if hours < 0 or hours > 24 or minutes < 0 or minutes >= 60 or (hours == 24 and minutes != 0):
		_reject(); return
	var next := hours + minutes / 60.0
	if is_equal_approx(next, _value): set_value_no_signal(_value); return
	value = next
func _reject() -> void:
	set_value_no_signal(_value)
	invalid_input.emit("时间格式应为 HH:MM，例如 07:30。")
func set_value_no_signal(next: float) -> void:
	_value = clampf(next, 0.0, 24.0)
	var minutes := roundi(_value * 60.0)
	clock.text = "%02d:%02d" % [minutes / 60, minutes % 60]
	slider.set_value_no_signal(_value)
func set_editable(next: bool) -> void:
	editable = next
