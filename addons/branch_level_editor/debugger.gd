@tool
extends EditorDebuggerPlugin
signal state_received(key: String, data: Dictionary)
signal instance_removed(key: String)
signal session_cleared(id: int)
signal session_paused(id: int, paused: bool)
func _has_capture(capture: String) -> bool:
	return capture == "branch_level"
func _capture(message: String, data: Array, session: int) -> bool:
	if message == "branch_level:state" and data.size() == 1 and data[0] is Dictionary:
		state_received.emit("%d:%s" % [session, data[0].get("instance", "")], data[0])
		return true
	if message == "branch_level:remove" and data.size() == 1:
		instance_removed.emit("%d:%s" % [session, data[0]])
		return true
	return false
func _setup_session(id: int) -> void:
	var session := get_session(id)
	session.started.connect(func(): session_cleared.emit(id))
	session.stopped.connect(func(): session_cleared.emit(id))
	session.breaked.connect(func(_can_debug: bool): session_paused.emit(id, true))
	session.continued.connect(func(): session_paused.emit(id, false))
