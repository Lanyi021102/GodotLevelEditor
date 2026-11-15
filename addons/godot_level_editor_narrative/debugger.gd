@tool
extends "res://addons/godot_level_editor/debugger.gd"
func _has_capture(capture: String) -> bool: return capture == "godot_level_editor_narrative"
func _capture(message: String, data: Array, session: int) -> bool:
	if message == "godot_level_editor_narrative:state" and data.size() == 1 and data[0] is Dictionary:
		state_received.emit("%d:%s" % [session, data[0].get("instance", "")], data[0])
		return true
	if message == "godot_level_editor_narrative:remove" and data.size() == 1:
		instance_removed.emit("%d:%s" % [session, data[0]])
		return true
	return false
