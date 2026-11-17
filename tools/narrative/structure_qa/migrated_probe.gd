extends Node
const ACCESS := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/state_access.gd")

func frames(count := 1) -> void:
	for i in count: await get_tree().physics_frame

func interact() -> void:
	var down := InputEventAction.new(); down.action = "interact"; down.pressed = true; Input.parse_input_event(down)
	await frames(3)
	var up := InputEventAction.new(); up.action = "interact"; up.pressed = false; Input.parse_input_event(up)
	await frames(3)

func move_player(player: Node3D, position: Vector3) -> void:
	player.global_position = position
	if player is CharacterBody3D: player.velocity = Vector3.ZERO
	await frames(5)
	var rig: Node = player.get("camera_rig")
	if rig != null and not rig.is_gameplay_input_enabled():
		var click := InputEventMouseButton.new(); click.position = get_viewport().get_visible_rect().get_center(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
		Input.parse_input_event(click); await frames(2)
		var release := click.duplicate() as InputEventMouseButton; release.pressed = false
		Input.parse_input_event(release); await frames(2)

func _ready() -> void:
	if not Engine.is_editor_hint(): _run.call_deferred()

func _run() -> void:
	var world := get_parent()
	var recorder: Node = world.get_node_or_null("SessionRecorder")
	if recorder != null: recorder.mode = "automated"
	var director: Node
	for attempt in 240:
		for candidate in get_tree().get_nodes_in_group("godot_level_editor_task_directors"):
			if candidate.world == world and candidate.valid: director = candidate; break
		if director != null: break
		await frames()
	var player := get_tree().get_first_node_in_group("godot_level_editor_player") as Node3D
	if director == null or player == null:
		write({"all_passed": false, "reason": "F6 player/task service missing"}); return
	await frames(8)
	await move_player(player, world.get_node("NPCs/Tester").global_position + Vector3(0, 0.1, 1))
	await interact()
	var button: Node3D = ACCESS.resolve(world, "$world/flow_button::button")
	var door: Node3D = ACCESS.resolve(world, "$world/flow_single_door::door")
	var last_press := -1000
	var last_dialog_press := -1000
	var attempts := []
	for step in 2600:
		if director.dialogue.is_active() and director.dialogue.current_mode() == "stationary" and step - last_dialog_press > 60:
			await interact(); last_dialog_press = step
		if director.task_states.get("1004002", "") == "active":
			if recorder.button_presses < 2 and step - last_press > 60:
				await move_player(player, button.global_position + Vector3(0, 0.1, 0.7))
				var rig: Node = player.get("camera_rig")
				attempts.append({"step": step, "player": str(player.global_position), "button": button.get_state(), "can_interact": button.can_interact(player), "input_enabled": rig == null or rig.is_gameplay_input_enabled(), "pressed_before": Input.is_action_pressed("interact"), "dialogue_active": director.dialogue.is_active()})
				await interact(); last_press = step
			elif recorder.button_presses >= 2 and door.get_state() == "open":
				await move_player(player, world.get_node("Rooms/FinishArea").global_position + Vector3(0, -0.8, 0))
		if director.event_states.get("1004", "") in ["completed", "failed"]: break
		await frames()
	await frames(12)
	var result: Dictionary = recorder.result() if recorder != null else {"all_passed": false}
	result["driver"] = "automated F input and movement; no task/event completion API called"
	result["task_states"] = director.task_states
	result["event_states"] = director.event_states
	result["attempts"] = attempts
	write(result)

func write(data: Dictionary) -> void:
	var file := FileAccess.open("user://narrative-migrated-runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
