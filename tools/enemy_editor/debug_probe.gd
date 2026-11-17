extends Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sample: Node3D = (load("res://tools/enemy_editor/fixtures/guard_blueprint_sample.tscn") as PackedScene).instantiate()
	add_child(sample)
	var guard: GuardAI = sample.get_node("Guard")
	guard.set_physics_process(false)
	for _i in 6: await get_tree().physics_frame
	GLENoiseBus.emit_pulse(guard.global_position, 5.0, self)
	for _i in 6: await get_tree().physics_frame
	var baseline := guard.tl_capture()
	guard.alert_level = 100.0
	guard._evaluate_enemy("perception")
	for _i in 6: await get_tree().physics_frame
	guard.tl_restore(baseline)
	var hold := 90.0 if OS.get_cmdline_user_args().has("--hold-enemy-visual") else 0.3
	await get_tree().create_timer(hold, true).timeout
	get_tree().quit()
