extends Node
const LIBRARY := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd")
const DIALOGUE := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_player.gd")
const XLSX := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/xlsx.gd")
var checks := 0
var failures := 0
var completions: Array[String] = []
var dialogue: CanvasLayer
var session: Node3D
var capture_dir := ""
class InteractionProbe extends Node3D:
	var calls := 0
	func can_interact(_actor: Node3D) -> bool: return true
	func interact(_actor: Node3D) -> bool:
		calls += 1
		return true
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)
func frames(count := 3) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame
func line(id: String, mode: String, text := "测试对白", duration := 0.0) -> Dictionary:
	return {"id": id, "speaker": "接待员", "dialogue_mode": mode, "text": text, "type": "对白", "duration": duration}
func library(lines: Array) -> Resource:
	var result := LIBRARY.new()
	result.speakers = {"接待员": Color("89b8df")}
	result.groups.assign([{"id": "group", "name": "播放检查", "comments": [{"id": "comment", "name": "当前段落", "lines": lines}, {"id": "next_comment", "name": "不应自动播放", "lines": [line("next_line", LIBRARY.MODE_FREE)]}]}])
	return result
func play(lines: Array) -> bool:
	completions.clear()
	dialogue.library = library(lines)
	return dialogue.show_dialog("comment")
func press(action := "interact") -> void:
	var event := InputEventAction.new(); event.action = action; event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = InputEventAction.new(); event.action = action; event.pressed = false
	Input.parse_input_event(event)
	await frames()
func capture(name_text: String) -> void:
	if capture_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(capture_dir + "/" + name_text + ".png") == OK, "real game render: " + name_text)
func _ready() -> void:
	get_tree().create_timer(60, true).timeout.connect(func(): get_tree().quit(2))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()
func _run() -> void:
	check(LIBRARY.estimate_reading_seconds("你好") >= 2.5, "short dialogue has a readable minimum time")
	check(LIBRARY.estimate_reading_seconds("中文对白".repeat(35)) > 18.0, "long dialogue is not truncated to the former 18-second ceiling")
	check(LIBRARY.estimate_reading_seconds("这是一段比较长的对白，里面有停顿。") > LIBRARY.estimate_reading_seconds("这是一段比较长的对白里面有停顿"), "punctuation adds reading pauses")
	check(LIBRARY.estimate_reading_seconds("a very long conversation with several separate words") > LIBRARY.estimate_reading_seconds("a"), "Latin text is estimated by word groups")
	var mixed := library([line("00001", LIBRARY.MODE_FREE), line("00002", LIBRARY.MODE_STATIONARY)])
	check(mixed.playback_duration(line("fixed", LIBRARY.MODE_FREE, "很长的对白".repeat(10), 4.0)) == 4.0, "existing explicit duration remains a Free Dialogue override")
	var path := "user://dialogue_modes.xlsx"
	check(mixed.write_xlsx(path).is_empty(), "new dialogue modes save to XLSX")
	var read := LIBRARY.read_xlsx(path)
	check(read.library != null and read.library.comment_by_id("comment").lines[1].dialogue_mode == LIBRARY.MODE_STATIONARY and read.library.comment_by_id("comment").lines[0].id == "00001", "XLSX preserves both modes and leading-zero IDs")
	var sheets: Dictionary = mixed.workbook_sheets()
	check(sheets["对白"][0].find("dialogue_mode") + 1 == sheets["对白"][0].find("text"), "XLSX dialogue_mode column is left of text")
	for row in sheets["对白"]: row.remove_at(4)
	XLSX.write_book(path, sheets)
	read = LIBRARY.read_xlsx(path)
	check(read.library != null and read.library.comment_by_id("comment").lines[1].dialogue_mode == LIBRARY.MODE_FREE, "old XLSX without the new column defaults to Free Dialogue")
	mixed.groups[0].comments[0].lines[0].dialogue_mode = "unknown"
	check(not mixed.validate().is_empty(), "unknown dialogue modes are rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	session = load("res://tools/runtime/session_fixture.tscn").instantiate()
	if not capture_dir.is_empty():
		var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-50, -25, 0); light.light_energy = 1.5; session.add_child(light)
		var environment: Environment = session.get_node("WorldEnvironment").environment.duplicate()
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color.WHITE
		session.get_node("WorldEnvironment").environment = environment
	add_child(session)
	dialogue = DIALOGUE.new(); add_child(dialogue)
	dialogue.dialogue_completed.connect(func(id: String): completions.append(id))
	await frames(12)
	var camera: Node3D = session.camera_rig
	var player: CharacterBody3D = session.player
	if DisplayServer.get_name() != "headless":
		# Native foreground changes must not interrupt scripted input replay.
		# Focus loss/restoration is exercised explicitly below, independently.
		get_window().focus_exited.disconnect(camera._on_window_focus_exited)
	camera.capture_mouse()
	check(play([line("free_1", LIBRARY.MODE_FREE, "自由对话时可以走动。", 100.0), line("free_2", LIBRARY.MODE_FREE, "这一句播放后结束。", 100.0)]), "Free Dialogue starts")
	check(not get_tree().paused and camera.is_gameplay_input_enabled(), "Free Dialogue leaves the world and player controls running")
	var start := player.global_position
	Input.action_press("move_right"); await frames(25); Input.action_release("move_right")
	check(player.global_position.distance_to(start) > 0.5, "the real player can walk during Free Dialogue")
	await press()
	check(dialogue.index == 0 and dialogue.is_active(), "Free Dialogue ignores manual next-line keys")
	await capture("free_dialogue")
	dialogue._remaining_seconds = 0.001
	await frames()
	check(dialogue.index == 1 and completions == ["free_1"], "Free Dialogue automatically advances one line after its reading time")
	dialogue._remaining_seconds = 0.001
	await frames()
	check(not dialogue.is_active() and completions == ["free_1", "free_2", "comment"] and not dialogue.completed.has("next_comment"), "automatic playback ends at this comment boundary with exactly-once completion")
	check(play([line("stand_1", LIBRARY.MODE_STATIONARY, "请按交互键或点击画面继续。", 0.001), line("stand_2", LIBRARY.MODE_STATIONARY, "这一句也需要手动结束。", 0.001)]), "Stationary Dialogue starts")
	var opening_click := InputEventMouseButton.new(); opening_click.button_index = MOUSE_BUTTON_LEFT; opening_click.pressed = true
	dialogue._input(opening_click)
	check(dialogue.index == 0, "the input that opens a stationary line cannot skip it in the same frame")
	check(not get_tree().paused and not camera.is_gameplay_input_enabled(), "Stationary Dialogue blocks player controls without pausing the world")
	start = player.global_position
	Input.action_press("move_right"); await frames(25); Input.action_release("move_right")
	check(player.global_position.distance_to(start) < 0.05 and dialogue.index == 0, "Stationary Dialogue neither moves the player nor advances when its duration elapses")
	await capture("stationary_dialogue")
	var echo := InputEventKey.new(); echo.physical_keycode = KEY_F; echo.pressed = true; echo.echo = true
	dialogue._input(echo)
	check(dialogue.index == 0, "held-key repeat cannot skip stationary lines")
	await press()
	check(dialogue.index == 1 and completions == ["stand_1"], "F advances Stationary Dialogue exactly one line")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	Input.parse_input_event(click)
	await frames(4)
	check(not dialogue.is_active() and completions == ["stand_1", "stand_2", "comment"] and camera.is_gameplay_input_enabled(), "left click ends the final stationary line and restores controls")
	check(play([line("mixed_free", LIBRARY.MODE_FREE, "自动结束这一句。", 100.0), line("mixed_stand", LIBRARY.MODE_STATIONARY)]), "mixed-mode comment starts")
	await frames()
	dialogue._remaining_seconds = 0.001
	await frames()
	check(dialogue.current_mode() == LIBRARY.MODE_STATIONARY and not camera.is_gameplay_input_enabled(), "a free-to-stationary transition locks controls at the new line")
	await press("ui_accept")
	check(not dialogue.is_active() and camera.is_gameplay_input_enabled(), "Enter can finish Stationary Dialogue")
	check(play([line("stand_first", LIBRARY.MODE_STATIONARY), line("free_last", LIBRARY.MODE_FREE, "恢复行走。", 100.0)]), "stationary-to-free comment starts")
	await frames()
	await press()
	check(dialogue.current_mode() == LIBRARY.MODE_FREE and camera.is_gameplay_input_enabled(), "a stationary-to-free transition restores movement while the comment remains open")
	dialogue._remaining_seconds = 0.001; await frames()
	camera.release_mouse()
	play([line("released", LIBRARY.MODE_STATIONARY)])
	await frames(); await press()
	check(not camera.is_gameplay_input_enabled(), "closing dialogue does not capture a mouse that was already released")
	camera.capture_mouse()
	play([line("focus", LIBRARY.MODE_STATIONARY)])
	await frames(); camera._on_window_focus_exited(); await press()
	check(not camera.is_gameplay_input_enabled(), "switching to the editor during stationary dialogue does not recapture on close")
	camera.capture_mouse()
	var probe := InteractionProbe.new(); add_child(probe); probe.position = player.global_position
	probe.add_to_group("godot_level_editor_interactable")
	play([line("no_fallthrough", LIBRARY.MODE_STATIONARY)])
	await frames(); await press()
	check(probe.calls == 0, "the F press closing dialogue cannot also interact with a nearby object")
	await press()
	check(probe.calls == 1, "the next deliberate F press can interact normally")
	probe.queue_free()
	get_tree().paused = true
	play([line("paused", LIBRARY.MODE_FREE, "保持外部暂停。", 0.001)])
	await get_tree().process_frame
	check(get_tree().paused and dialogue.is_active(), "dialogue does not clear an existing external pause")
	dialogue.queue_free(); await get_tree().process_frame
	check(get_tree().paused, "removing a dialogue player preserves external pause state")
	get_tree().paused = false
	session.queue_free(); await frames()
	print("DIALOGUE MODES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
