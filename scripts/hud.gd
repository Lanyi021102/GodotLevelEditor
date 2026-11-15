extends CanvasLayer
@export var light_background := true
var _status := ""
func flash_message(text: String, _seconds := 3.0) -> void: _status = text
func status_text() -> String: return _status
func set_location(_text: String) -> void: pass
func set_objective(_text: String) -> void: pass
func set_rooms_info(_text: String) -> void: pass
func hide_banner() -> void: pass
func show_banner(_text: String) -> void: pass
