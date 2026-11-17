@tool
extends HBoxContainer
signal color_changed(color: Color)
signal invalid_input(message: String)
var picker := ColorPickerButton.new()
var code := LineEdit.new()
var _color := Color.WHITE
var color: Color:
	get: return _color
	set(next): set_color_no_signal(next)
func _init() -> void:
	add_theme_constant_override("separation", 10)
	picker.custom_minimum_size = Vector2(52, 34)
	picker.edit_alpha = false
	code.custom_minimum_size.x = 132
	code.max_length = 7
	code.placeholder_text = "#RRGGBB"
	code.tooltip_text = "可直接输入或粘贴六位色值，也可点击左侧色块选色。"
	add_child(picker); add_child(code)
	picker.color_changed.connect(func(next: Color): set_color_no_signal(next); color_changed.emit(_color))
	code.text_submitted.connect(func(_text: String): commit_text())
	code.focus_exited.connect(commit_text)
func commit_text() -> void:
	var text := code.text.strip_edges().trim_prefix("#")
	if text.length() != 6 or not Color.html_is_valid(text):
		code.text = "#" + _color.to_html(false).to_upper()
		invalid_input.emit("请输入六位色值，例如 #FFA366。")
		return
	var next := Color.from_string("#" + text, _color)
	next.a = _color.a
	if next.is_equal_approx(_color): return
	set_color_no_signal(next); color_changed.emit(_color)
func set_color_no_signal(next: Color) -> void:
	_color = next
	picker.color = next
	code.text = "#" + next.to_html(false).to_upper()
func set_editable(enabled: bool) -> void:
	picker.disabled = not enabled
	code.editable = enabled
