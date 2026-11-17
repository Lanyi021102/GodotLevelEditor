@tool
extends EditorDebuggerPlugin
signal state_received(key: String, packet: Dictionary)
signal instance_removed(key: String)
signal session_cleared(session_id: int)
func _has_capture(capture: String) -> bool:
	return capture == "godot_level_editor_mechanism"
func _capture(message: String, data: Array, session_id: int) -> bool:
	if message == "godot_level_editor_mechanism:state" and data.size() == 1 and data[0] is Dictionary:
		var packet: Dictionary = data[0].duplicate(true)
		packet["session"] = session_id
		state_received.emit("%d:%s" % [session_id, packet.get("instance", "")], packet)
		return true
	if message == "godot_level_editor_mechanism:remove" and data.size() == 1:
		instance_removed.emit("%d:%s" % [session_id, data[0]])
		return true
	return false
func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.started.connect(func(): session_cleared.emit(session_id))
	session.stopped.connect(func(): session_cleared.emit(session_id))
