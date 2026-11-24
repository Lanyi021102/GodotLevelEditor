extends RefCounted
## Session checkpoint, scoped to the current world. Uses existing component save/reset contracts.
const PERFORMANCE := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/player.gd")
var saved: Dictionary = {}

func capture(director: Node) -> bool:
	if director.dialogue.is_active() or PERFORMANCE.is_playing_in(director.world): return false
	for state in director.active.values():
		if state.has("failure"): return false
	var nodes: Array[Node] = [director.world]
	nodes.append_array(director.world.find_children("*", "Node", true, false))
	var player: Node = director.world.get_tree().get_first_node_in_group("godot_level_editor_player")
	if player != null:
		nodes.append(player)
		nodes.append_array(player.find_children("*", "Node", true, false))
	var states := {}
	for node in nodes:
		if not node.has_method("tl_capture") and node != player and not director.world.objects().values().has(node): continue
		var state := {}
		if node is Node3D:
			state["transform"] = node.global_transform
			state["visible"] = node.visible
		if node is CharacterBody3D: state["velocity"] = node.velocity
		if node.has_method("tl_capture") and node.has_method("tl_restore"): state["component"] = node.tl_capture().duplicate(true)
		states[str(node.get_path())] = state
	saved = {"world": director.world.get_instance_id(), "level": director.current_level_id, "progress": director.capture_progress().duplicate(true), "world_progress": director.world.capture_progress().duplicate(true), "nodes": states}
	return true

func restore(director: Node) -> bool:
	if saved.is_empty() or director.dialogue.is_active() or saved.world != director.world.get_instance_id() or saved.level != director.current_level_id: return false
	for path in saved.nodes:
		if director.get_node_or_null(NodePath(path)) == null: return false
	PERFORMANCE.cancel_in(director.world)
	for path in saved.nodes:
		var node: Node = director.get_node(NodePath(path))
		var state: Dictionary = saved.nodes[path]
		if state.has("transform"): node.global_transform = state.transform; node.visible = state.visible
		if state.has("velocity"): node.velocity = state.velocity
		if state.has("component"): node.tl_restore(state.component.duplicate(true))
	if director.world.runtime_valid: director.world.restore_progress(saved.world_progress.duplicate(true))
	if not director.restore_progress(saved.progress.duplicate(true)): return false
	var main: Node = director.get_tree().get_first_node_in_group("main")
	if main != null and main.get("camera_rig") != null: main.camera_rig.snap_to_target()
	return true
