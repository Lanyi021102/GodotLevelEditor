extends "res://addons/godot_level_editor/scripts/core/game_session.gd"
var _initial_mechanisms: Dictionary = {}
func _ready() -> void:
	super._ready()
	get_window().title = "GodotLevelEditor · 3C Playground"
	$World/Door.add_power_source($World/Lever)
	for component in [$World/Lever, $World/Door]:
		_initial_mechanisms[component] = component.tl_capture().duplicate(true)
func _reset_room() -> void:
	super._reset_room()
	for component in _initial_mechanisms:
		component.tl_restore(_initial_mechanisms[component].duplicate(true))
