extends Node
const SCENE = "res://content/scenes/levels/dusk_mountain_house.tscn"
const ACCESS = preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/state_access.gd")
var checks := 0
var failures := 0
var world: Node3D
var player: CharacterBody3D
var director: Node
var manifest: Dictionary

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", message)

func frames(n := 8) -> void:
	for i in n: await get_tree().physics_frame

func task(i: int) -> String: return manifest.tasks[i].task_id
func obj(id: String) -> Node3D: return world.object_by_id("$world/" + id)
func component(id: String) -> Node: return ACCESS.resolve_anchor(obj(id))

func teleport(pos: Vector3) -> void:
	player.global_position = pos; player.velocity = Vector3.ZERO
	await frames(8)

func interact(id: String) -> void:
	var target := obj(id)
	await teleport(target.global_position + Vector3(0, 0.05, 0.8))
	check(target.interact(player), "实际玩家交互：" + id)
	await frames()

func close_dialog() -> void:
	var count := 0
	while director.dialogue.is_active() and count < 20:
		director.dialogue.advance(); count += 1; await get_tree().process_frame
	await frames(10)

func walk_forward(count: int, action := "move_forward") -> void:
	player.camera_rig.yaw_degrees = 0.0
	player.camera_rig.capture_mouse()
	Input.action_press(action)
	await frames(count)
	Input.action_release(action)
	await frames(10)
	print("WALK_POSITION ", player.global_position, " input=", player.camera_rig.is_gameplay_input_enabled())

func _ready() -> void:
	get_tree().create_timer(90, true).timeout.connect(func(): get_tree().paused = false; get_tree().quit(2))
	run.call_deferred()

func run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://content/resources/levels/dusk_mountain/manifest.json"))
	world = load(SCENE).instantiate(); get_tree().root.add_child(world); get_tree().current_scene = world
	await frames(30)
	player = get_tree().get_first_node_in_group("godot_level_editor_player")
	director = world.logic_director
	check(world.validate().is_empty() and world.runtime_valid, "关卡及常驻图完整校验")
	check(director != null and director.valid, "F6 自动创建唯一任务服务")
	check(player != null and player.global_position.distance_to(Vector3(0, 0, 48)) < 1, "正式角色在远端出生点生成")
	check(world.sky_preset.hour == 17.0, "关卡绑定 17:00 黄昏天空")
	for row in manifest.tasks:
		var graph: Resource = load(row.graph_path)
		check(graph.validate().is_empty(), "任务图校验：" + row.display_name)
	check(not obj("key_chest").can_interact(player) and director.active.is_empty(), "接任务前不可提前拿钥匙")
	check(not component("front_door").interact(player), "正门初始锁定")
	check(not component("rear_lift").interaction_enabled, "发现院门前升降机未激活")
	await teleport(Vector3(0, 0.1, -25.8)); await walk_forward(350)
	check(player.global_position.y > 3.0 and player.global_position.z < -32, "正式玩家无需跳跃即可走上院门石阶")
	await interact("mountain_guide")
	check(director.dialogue.is_active(), "NPC 真实交互播放委托对白")
	await close_dialog()
	check(director.task_states.get(task(0)) == "active", "对白结束自动接取首项任务")
	await teleport(obj("road_b1").global_position)
	check(not obj("road_b1").interact(player), "不能提前击败后续阶段敌人")
	await interact("road_a1")
	check(not obj("road_a1").visible and director.task_states.get(task(0)) == "active", "第一名敌人消失但不会提前推进")
	check(not obj("road_a1").interact(player), "击败后不能重复计数")
	await interact("road_a2")
	check(director.task_states.get(task(1)) == "active", "第一组清空后激活第二组")
	await interact("road_b2"); await interact("road_b1")
	check(director.task_states.get(task(2)) == "active", "第二组支持任意击败顺序")
	await teleport(Vector3(0, 4.1, -32.8))
	check(director.dialogue.is_active(), "真实 Area3D 接近院门触发堵塞发现对白")
	await close_dialog()
	check(director.task_states.get(task(3)) == "active", "转为后院升降机目标")
	# Use the real player and platform physics, without injecting completion events.
	await teleport(Vector3(13.1, 0.25, -53))
	check(component("rear_lift").interact(player), "玩家站在升降台上发出移动指令")
	await frames(245)
	check(component("rear_lift").get_state() == "at_end", "升降机确实移动到 3.78 m 终点")
	check(player.global_position.y > 3.8, "真实升降机碰撞载着正式玩家上升")
	check(director.task_states.get(task(3)) == "active", "升降机到位仍需玩家实际进入房屋")
	await walk_forward(280, "move_left")
	check(director.task_states.get(task(4)) == "active", "实际穿过后门感应区域完成入屋")
	await teleport(Vector3(4.2, 4.05, -52.7))
	check(component("foyer_button").interact(player), "实际按下玄关按钮")
	await frames(15)
	check(director.task_states.get(task(4)) == "active" and component("inner_door").get_state() != "open", "内门运动中不提前完成")
	await frames(90)
	check(component("inner_door").get_state() == "open" and director.task_states.get(task(5)) == "active", "内门完全打开后激活一层战斗")
	await interact("house_e2"); await interact("house_e1")
	check(director.task_states.get(task(6)) == "active", "清空一层后激活二层宝箱")
	await teleport(Vector3(-3.6, 4.05, -43.8)); await walk_forward(450)
	check(player.global_position.y > 7.8 and player.global_position.z < -52, "正式玩家无需跳跃即可沿楼梯到二层平台")
	await interact("key_chest"); await close_dialog()
	check(player.get_node("LevelAgent").level_inventory_count("dusk_front_door_key") == 1, "宝箱真实授予一把钥匙")
	check(director.task_states.get(task(7)) == "active", "拿钥匙后转入返回正门目标")
	var inventory: Node = player.get_node("LevelAgent")
	check(inventory.level_change_item("dusk_front_door_key", -1), "暂时移除钥匙以验证锁门分支")
	await interact("front_lock")
	check(component("front_door").get_state() == "closed" and component("front_door").locked and director.task_states.get(task(7)) == "active", "没有钥匙不能解锁或完成任务")
	check(inventory.level_change_item("dusk_front_door_key", 1), "恢复测试钥匙")
	await interact("front_lock")
	check(director.event_states.get(manifest.event_id) == "active", "正门动作未完成时事件不结束")
	await frames(95); await close_dialog()
	check(component("front_door").get_state() == "open", "带钥匙真实解锁并打开正门")
	check(director.event_states.get(manifest.event_id) == "completed", "全部八阶段完成后结束事件")
	check(director.objective_label.text.contains("任务完成"), "事件结束后 HUD 保留清晰的任务完成提示")
	for row in manifest.tasks: check(director.task_states.get(row.task_id) == "completed", "任务已完成：" + row.display_name)
	check(player.get_node("LevelAgent").level_inventory_count("dusk_front_door_key") == 1 and not obj("key_chest").interact(player), "宝箱不可重复领取钥匙")
	print("DUSK_TEST checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
