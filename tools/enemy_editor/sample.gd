extends Node3D
## Isolated authoring / debugging scene. No campaign writes.
var info: Label
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	add_child(layer)
	info = Label.new()
	info.position = Vector2(20, 20)
	info.add_theme_font_size_override("font_size", 20)
	layer.add_child(info)

func _process(_delta: float) -> void:
	var guard: GuardAI = $Guard
	info.text = "敌人蓝图独立样例\nWASD 移动目标 · N 制造噪音\n%s · 警觉 %.0f · %.1f s" % [guard.state_name(), guard.alert_level, guard.state_timer()]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_N:
			NoiseBus.emit_pulse($Target.global_position, 12.0, $Target)
