@tool
extends Node
var checks: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	checks.append({"ok": ok, "check": label})
	print("[PASS] " if ok else "[FAIL] ", label)
func _ready() -> void:
	if not Engine.is_editor_hint(): run.call_deferred()
func run() -> void:
	if not FileAccess.file_exists("res://.npc_structure_qa"): get_tree().quit(2); return
	for i in 50: await get_tree().physics_frame
	var level := get_parent()
	var session := get_tree().get_first_node_in_group("main")
	check(session != null and session.player != null and level.runtime_valid, "原生关卡 F6 建立玩家与试玩会话")
	if session == null: _finish(); return
	var npc: Node3D = level.find_child("WalkingNPC", true, false)
	check(npc != null and npc.get("_model") != null, "F6 加载个人 NPC 与模型")
	if npc != null:
		var origin := npc.global_position
		for i in 45: await get_tree().physics_frame
		check(npc.global_position.distance_to(origin) > 0.15, "巡逻路点实际驱动 NPC 位移")
		var visual: CharacterModel = npc.get("_model")
		check(visual.current_clip() == "walk" and visual.anim.is_playing(), "移动实际触发行走动画")
		var rig: Skeleton3D = visual.get("skeleton")
		var before := []
		for i in rig.get_bone_count(): before.append(rig.get_bone_pose(i))
		for i in 12: await get_tree().physics_frame
		var changed := false
		for i in rig.get_bone_count(): changed = changed or rig.get_bone_pose(i) != before[i]
		check(changed, "行走动画实际改变骨骼姿态")
		check(npc.global_position.y > -0.1 and session.player.global_position.y > -0.1, "NPC 与玩家留在地面碰撞上")
		check(not npc.has_method("interact"), "边界记录：模型型 NPC 不自带台本交互组件")
	var receiver: Node3D = level.find_child("DialogueNPC", true, false)
	check(receiver != null and receiver.has_method("interact"), "原有对话 NPC 组件仍可加载")
	if receiver != null:
		session.player.global_position = receiver.global_position + Vector3(0, 0.1, 1)
		check(receiver.interaction_allowed and receiver.can_interact(session.player), "常驻逻辑的 NPC 交互节点启用对话入口")
		var signal_count := [0]
		receiver.interacted.connect(func(_id: String, _actor: Node3D): signal_count[0] += 1)
		if DisplayServer.get_name() != "headless": get_tree().root.grab_focus()
		session.camera_rig.capture_mouse()
		Input.action_press("interact")
		for i in 2: await get_tree().physics_frame
		Input.action_release("interact")
		check(signal_count[0] > 0, "F 输入经过玩家触发原有 NPC 对话信号")
	var before: Vector3 = session.player.global_position
	Input.action_press("move_forward")
	for i in 20: await get_tree().physics_frame
	Input.action_release("move_forward")
	check(session.player.global_position.distance_to(before) > 0.1, "F6 中玩家移动输入可用")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://npc-structure-play.png")
	_finish()
func _finish() -> void:
	var failed := checks.filter(func(row: Dictionary): return not row.ok).size()
	var output := FileAccess.open("res://npc-structure-play.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failed": failed}, "  ")); output.close()
	print("NPC STRUCTURE PLAY: %d checks / %d failed" % [checks.size(), failed])
	get_tree().quit(1 if failed else 0)
