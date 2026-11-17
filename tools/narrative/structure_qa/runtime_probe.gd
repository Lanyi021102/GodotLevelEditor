extends Node
var checks := []
var failures := 0

func check(ok: bool, name_text: String) -> void:
	checks.append({"ok": ok, "step": name_text})
	if not ok: failures += 1

func frames(count := 4) -> void:
	for i in count: await get_tree().physics_frame

func press_interact() -> void:
	var event := InputEventAction.new(); event.action = "interact"; event.pressed = true
	Input.parse_input_event(event)
	await frames(3)
	var release := InputEventAction.new(); release.action = "interact"; release.pressed = false
	Input.parse_input_event(release)
	await frames(3)

func _ready() -> void:
	if Engine.is_editor_hint(): return
	_run.call_deferred()

func _run() -> void:
	var director: Node
	for attempt in 180:
		director = get_tree().get_first_node_in_group("godot_level_editor_task_directors")
		if director != null and director.valid: break
		await frames(1)
	var task := str(get_meta("task_id")); var event := str(get_meta("event_id"))
	check(director != null and director.valid and director.current_level_id == str(get_meta("level_id")), "standalone F6 installs a valid service for the saved native level ID")
	var player := get_tree().get_first_node_in_group("godot_level_editor_player") as Node3D
	check(player != null, "F6 supplies the normal controllable player")
	if director != null and player != null:
		var npc: Node3D = get_parent().get_node("QAContact")
		player.global_position = npc.global_position + Vector3(0, 0, 1.0)
		await frames(5)
		# A rendered F6 window can be focused after its first physics frames.
		# Follow the normal click-to-recapture path before pressing F.
		if DisplayServer.get_name() != "headless":
			for attempt in 180:
				if get_window().has_focus(): break
				await frames(1)
			var rig: Node = player.get("camera_rig")
			if rig != null and not rig.is_gameplay_input_enabled():
				var click := InputEventMouseButton.new(); click.position = get_viewport().get_visible_rect().get_center(); click.global_position = click.position; click.button_index = MOUSE_BUTTON_LEFT; click.button_mask = MOUSE_BUTTON_MASK_LEFT; click.pressed = true
				Input.parse_input_event(click); await frames(2)
				var release := click.duplicate() as InputEventMouseButton; release.pressed = false; release.button_mask = 0
				Input.parse_input_event(release); await frames(4)
		check(director.task_states.get(task, "") != "active" and npc.can_interact(player), "unaccepted task stays inactive while its permanent NPC can interact")
		await press_interact()
		for attempt in 100:
			if director.dialogue.is_active() and director.dialogue.current_mode() == "stationary": break
			await frames(1)
		check(director.task_states.get(task, "") == "active", "F interaction accepts the new task through permanent level logic")
		check(director.dialogue.is_active() and director.dialogue.current_mode() == "stationary" and director.dialogue.blocks_player_input(), "saved free dialogue advances to the authored stationary line")
		await press_interact()
		await frames(12)
		check(director.task_states.get(task, "") == "completed" and director.event_states.get(event, "") == "completed", "second F finishes the dialogue and completes the actual task/event")
		check(not director.dialogue.is_active() and not director.dialogue.blocks_player_input(), "dialogue completion restores normal player input")
	var file := FileAccess.open("user://narrative-structure-runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "checks": checks}, "  "))
