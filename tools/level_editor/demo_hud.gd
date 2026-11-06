extends CanvasLayer
var _label: Label
func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.size = Vector2(1150, 120)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 22)
	add_child(_label)
	get_parent().objective_changed.connect(func(text: String): _label.text = "关卡节点示例 · WASD 移动，R 重新开始\n" + text)
