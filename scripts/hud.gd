extends CanvasLayer
signal pause_requested
@export var light_background := true
var _status := ""
func _ready() -> void:
	%PauseButton.pressed.connect(func(): pause_requested.emit())
func _process(_delta: float) -> void:
	%PauseButton.text = "▶" if get_tree().paused else "Ⅱ"
	%PauseButton.tooltip_text = "继续（T）" if get_tree().paused else "暂停"
func flash_message(text: String, _seconds := 3.0) -> void: _status = text
func status_text() -> String: return _status
func set_location(_text: String) -> void: pass
func set_objective(_text: String) -> void: pass
func set_rooms_info(_text: String) -> void: pass
func set_stealth_info(_text: String) -> void: pass
func set_abilities_info(_text: String) -> void: pass
func set_clone_count(_count: int, _limit: int) -> void: pass
func hide_banner() -> void: pass
func show_banner(_text: String) -> void: pass
