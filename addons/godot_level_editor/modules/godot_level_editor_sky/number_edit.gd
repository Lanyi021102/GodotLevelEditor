@tool
extends HBoxContainer
signal value_changed(value: float)
var spin := SpinBox.new()
var slider := HSlider.new()
var _value := 0.0
var _factor := 1.0
var value: float:
	get: return _value
	set(next):
		if is_equal_approx(next, _value): return
		set_value_no_signal(next)
		value_changed.emit(_value)
var editable := true:
	set(next):
		editable = next
		spin.editable = next
		slider.editable = next
func _init() -> void:
	add_theme_constant_override("separation", 12)
	spin.custom_minimum_size = Vector2(118, 34)
	slider.custom_minimum_size.x = 170
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(spin); add_child(slider)
	preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/slider_style.gd").apply(slider)
	spin.value_changed.connect(func(next: float): value = next / _factor)
	slider.value_changed.connect(func(next: float): value = next / _factor)
func configure(initial: float, minimum: float, maximum: float, step: float, unit := "", show_slider := true, factor := 1.0) -> void:
	_factor = factor
	for control in [spin, slider]:
		control.min_value = minimum * factor
		control.max_value = maximum * factor
		control.step = step * factor
	# Keep stored values readable even when the arrow increment is coarse.
	spin.step = 0.01
	spin.custom_arrow_step = step * factor
	spin.allow_greater = true
	spin.suffix = unit
	slider.visible = show_slider
	set_value_no_signal(initial)
func set_value_no_signal(next: float) -> void:
	_value = next
	spin.set_value_no_signal(next * _factor)
	slider.set_value_no_signal(next * _factor)
func set_editable(next: bool) -> void:
	editable = next
