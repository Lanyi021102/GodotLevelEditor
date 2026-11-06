extends "res://scripts/core/game_session.gd"
const ADAPTER := preload("res://scripts/actors/player_rewindable.gd")
var _initial_mechanisms: Dictionary = {}
func _ready() -> void:
	super._ready()
	get_window().title = "Branch · 3C Playground"
	$World/Door.add_power_source($World/Lever)
	for component in [$World/Lever, $World/Door]:
		var adapter := ADAPTER.new()
		adapter.name = "Rewindable"
		adapter.trail_enabled = false
		component.add_child(adapter)
		_initial_mechanisms[component] = component.tl_capture().duplicate(true)
func _reset_room() -> void:
	super._reset_room()
	for component in _initial_mechanisms:
		component.tl_restore(_initial_mechanisms[component].duplicate(true))
