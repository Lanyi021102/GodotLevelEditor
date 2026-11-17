extends Node
## Observes the new test level only. Does not trigger or advance gameplay.
const ACCESS = preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/state_access.gd")
const OUTPUT = "res://docs/qa/editor_flow_2026-11-17"
var director: Node
var history: Array[Dictionary] = []
var button_presses := 0
var restored := 0
var checkpoint_count := 0
var mode := "manual"

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--flow-automated"): mode = "automated"
	_bind.call_deferred()

func _bind() -> void:
	for i in 240:
		for candidate in get_tree().get_nodes_in_group("godot_level_editor_task_directors"):
			if candidate.world == get_parent() and candidate.valid: director = candidate; break
		if director != null: break
		await get_tree().process_frame
	if director == null: push_error("FLOW RECORDER: no valid director"); return
	director.task_started.connect(func(id: String): _note("task_started", id))
	director.task_completed.connect(func(id: String): _note("task_completed", id))
	director.task_failed.connect(func(id: String, reason: String): _note("task_failed", id + ":" + reason))
	director.checkpoint_saved.connect(func(): checkpoint_count += 1; _note("checkpoint_saved", ""))
	director.checkpoint_restored.connect(func(): restored += 1; _note("checkpoint_restored", ""))
	director.event_completed.connect(func(id: String):
		if id == "1004": _finish.call_deferred())
	var button = ACCESS.resolve(get_parent(), "$world/flow_button::button")
	if button != null: button.interacted.connect(_button)
	_note("session_ready", "9")

func _note(kind: String, value: String) -> void:
	history.append({"kind":kind, "value":value, "msec":Time.get_ticks_msec()})
	print("FLOW ", mode, " ", kind, " ", value)

func _button(_id: String, _action: String, _actor: Node3D) -> void:
	button_presses += 1
	_note("button", str(button_presses))

func result() -> Dictionary:
	var player = get_tree().get_first_node_in_group("godot_level_editor_player")
	var agent = player.get_node_or_null("LevelAgent") if player != null else null
	var door = ACCESS.resolve(get_parent(), "$world/flow_single_door::door")
	var checks := {
		"event_completed":director.event_states.get("1004") == "completed",
		"equipment_task_completed":director.task_states.get("1004001") == "completed",
		"mechanism_task_completed":director.task_states.get("1004002") == "completed",
		"parallel_task_completed":director.task_states.get("1004003") == "completed",
		"two_button_interactions":button_presses >= 2,
		"door_open":door != null and door.get_state() == "open",
		"room_active":get_parent().get_node("Rooms/FinishArea").is_active(),
		"numeric_variable":director.variables.get("flow_count") == 2.0,
		"inventory":agent != null and agent.level_inventory_count("flow_uniform") == 1,
		"equipment":agent != null and agent.level_has_equipped("body", "flow_uniform"),
		"child_actor_state":agent != null and agent.state_flags.get("flow_verified", false),
		"checkpoint_saved":checkpoint_count > 0,
	}
	return {"mode":mode, "checks":checks, "all_passed":not checks.values().has(false), "history":history, "progress":director.capture_progress(), "checkpoint_restores":restored}

func _finish() -> void:
	for i in 4: await get_tree().process_frame
	var data := result()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var file := FileAccess.open(OUTPUT + "/" + mode + "-session.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data, "\t"))
	print("FLOW_SESSION_RESULT ", JSON.stringify(data.checks), " all_passed=", data.all_passed)
	var layer := CanvasLayer.new(); add_child(layer)
	var label := Label.new(); label.text = "流程测试完成" if data.all_passed else "流程测试未通过，请查看验证记录"
	label.position = Vector2(32, 100); label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.2,0.85,0.55) if data.all_passed else Color(1,0.35,0.2))
	layer.add_child(label)
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUTPUT + "/" + mode + "-complete.png")
