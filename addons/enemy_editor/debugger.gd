@tool
extends EditorDebuggerPlugin
signal state_received(key: String, data: Dictionary)
signal instance_removed(key: String)
signal session_cleared(session_id: int)
signal session_pause_changed(session_id: int, paused: bool)

func _has_capture(capture: String) -> bool:
	return capture == "branch_enemy"

func _capture(message: String, data: Array, session_id: int) -> bool:
	if message == "branch_enemy:state" and data.size() == 1 and data[0] is Dictionary:
		var packet: Dictionary = data[0].duplicate(true)
		packet["session"] = session_id
		state_received.emit("%d:%s" % [session_id, packet.get("instance", "")], packet)
		return true
	if message == "branch_enemy:remove" and data.size() == 1:
		instance_removed.emit("%d:%s" % [session_id, data[0]])
		return true
	return false

func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.breaked.connect(func(_can_debug: bool): session_pause_changed.emit(session_id, true))
	session.continued.connect(func(): session_pause_changed.emit(session_id, false))
	session.started.connect(func(): session_cleared.emit(session_id))
	session.stopped.connect(func(): session_cleared.emit(session_id))
