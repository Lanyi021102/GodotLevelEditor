extends Node
const Template := preload("res://addons/godot_level_editor/modules/enemy_editor/runtime/guard_template.gd")
const Store := preload("res://addons/godot_level_editor/modules/enemy_editor/definition_store.gd")
const TEMP := "res://tools/enemy_editor/.roundtrip.tres"
var passed := 0
var failed := 0

func _ready() -> void:
	_test_definition_and_machine()
	_test_storage()
	await _test_guard()
	await _test_route()
	print("ENEMY EDITOR: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func _test_definition_and_machine() -> void:
	var d := Template.create()
	check(d.validate().is_empty(), "四状态模板合法")
	check(d.states.size() == 4 and d.transitions.size() == 15, "四状态与十五条实际转换")
	var a := EnemyMachine.new()
	var b := EnemyMachine.new()
	check(a.configure(d) and b.configure(d), "共用定义创建独立运行实例")
	a.evaluate("noise", {"has_last_known": true, "alert": 25.0, "seen": false})
	check(a.state_id == "suspicious" and b.state_id == "patrol", "噪音转换不影响其他实例")
	check(d.initial_state == "patrol" and not d.parameters.has("timer"), "定义不写入实例计时状态")
	var edge := a.evaluate("perception", {"has_last_known": true, "alert": 100.0, "seen": true})
	check(a.state_id == "alert" and edge.effect == "expose", "满警觉触发暴露效果标识")
	check(a.last_reason.contains("警觉(100") and a.last_reason.contains("感知更新"), "记录实际触发条件与转换原因")
	a.advance(8.0)
	a.evaluate("tick", {"alert": 0.0, "seen": false})
	check(a.state_id == "search" and is_equal_approx(a.timer, 6.0), "警戒计时结束进入搜索")
	a.advance(6.0)
	a.evaluate("tick", {"seen": true, "alert": 0.0})
	check(a.state_id == "suspicious", "搜索同时看到目标和超时，高优先级胜出")
	var snap := a.capture()
	a.evaluate("perception", {"alert": 100.0})
	check(a.restore(snap) and a.state_id == "suspicious" and a.timer == 6.0, "恢复状态与计时器")
	check(a.last_transition == snap.last_transition, "恢复最近转换原因")
	check(not a.restore({"state_id": "missing", "timer": 2.0}), "拒绝不存在的快照状态")
	d.state_by_id("suspicious").speed = 99.0
	check(float(a.current().speed) == 3.2, "运行定义已冻结，编辑源资源不影响回溯历史")
	var rerouted := Template.create()
	for t in rerouted.transitions:
		if t.id == "search_seen": t.priority = 0
	var rerouted_machine := EnemyMachine.new()
	rerouted_machine.configure(rerouted)
	rerouted_machine.restore({"state_id": "search", "timer": 0.0})
	rerouted_machine.evaluate("tick", {"seen": true})
	check(rerouted_machine.state_id == "patrol", "改优先级实际改变运行结果")
	for t in rerouted.transitions:
		if t.id == "patrol_noise": t.to = "search"
	rerouted_machine.configure(rerouted)
	rerouted_machine.evaluate("noise", {"has_last_known": true})
	check(rerouted_machine.state_id == "search", "改连线实际改变运行结果")
	rerouted.transitions = rerouted.transitions.filter(func(t: Dictionary): return t.id != "patrol_noise")
	rerouted_machine.configure(rerouted)
	rerouted_machine.evaluate("noise", {"has_last_known": true})
	check(rerouted_machine.state_id == "patrol", "删连线实际阻断转换")
	var bad := Template.create()
	bad.transitions[0].to = "dangling"
	check(not bad.validate().is_empty(), "校验悬空端点")
	bad = Template.create()
	bad.states.append(bad.states[0].duplicate())
	check(not bad.validate().is_empty(), "校验重复稳定 ID")
	bad = Template.create()
	bad.transitions[0].conditions[0].fact = "arbitrary_code"
	check(not bad.validate().is_empty(), "拒绝非白名单条件")
	bad = Template.create()
	bad.transitions[0].conditions = []
	check(not bad.validate().is_empty(), "拒绝无条件转换")
	bad = Template.create()
	bad.transitions[0].conditions[0] = {"fact": "seen", "op": "gt", "value": 1}
	check(not bad.validate().is_empty(), "校验条件类型不匹配")
	bad = Template.create()
	bad.schema_version = 2
	check(not bad.validate().is_empty(), "拒绝未支持版本")
	bad = Template.create()
	bad.transitions[0].from_port = "wrong_port"
	check(not bad.validate().is_empty(), "拒绝无效端口与连接类型")
	bad = Template.create()
	bad.states[0].duration = NAN
	check(not bad.validate().is_empty(), "拒绝非有限行为参数")
	bad = Template.create()
	bad.transitions = []
	check(not bad.warnings().is_empty(), "不可达状态警告")
	# All loops cross an explicit input event boundary; evaluate never recursively propagates.
	var loop := Template.create()
	loop.transitions.assign([Template._edge("self", "patrol", "patrol", "tick", 1, [Template._c("timer", "le", 0.0)])])
	var looper := EnemyMachine.new()
	looper.configure(loop)
	check(looper.evaluate("tick", {}).id == "self", "带事件推进规则的自环只执行一次")

func _test_storage() -> void:
	var d := Template.create()
	d.layout.scroll = Vector2(125, 225)
	d.layout.zoom = 0.8
	d.state_by_id("patrol").label = "巡逻重命名"
	check(Store.save_definition(d, TEMP) == OK, "保存定义")
	var uid := ResourceLoader.get_resource_uid(TEMP)
	check(ResourceUID.get_id_path(uid) == TEMP, "原子保存后资源标识指向最终文件")
	check(Store.save_definition(d, TEMP) == OK and ResourceLoader.get_resource_uid(TEMP) == uid, "重复保存保持已有资源标识")
	var loaded := Store.load_definition(TEMP)
	check(loaded != null and loaded.state_by_id("patrol").label == "巡逻重命名", "重载保持稳定 ID 和名称")
	check(loaded.layout == d.layout and loaded.transitions == d.transitions and loaded.parameters == d.parameters, "重载保持节点排版、视图、连线与参数")
	check(Store.save_definition(d, TEMP, "stale_hash") == ERR_BUSY, "文件冲突拒绝覆盖")
	d.initial_state = "missing"
	var before := FileAccess.get_sha256(TEMP)
	check(Store.save_definition(d, TEMP) == ERR_INVALID_DATA and FileAccess.get_sha256(TEMP) == before, "非法数据不会破坏已有文件")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))

func _test_guard() -> void:
	var scene := load("res://addons/godot_level_editor/modules/enemy_editor/runtime/npc_actor.tscn") as PackedScene
	var a := scene.instantiate() as GuardAI
	var b := scene.instantiate() as GuardAI
	a.name = "TemplateGuard"
	b.name = "CustomGuard"
	a.patrol_speed = 1.6
	b.enemy_definition = Template.create()
	b.enemy_definition.state_by_id("suspicious").speed = 7.0
	b.enemy_definition.state_by_id("suspicious").duration = 2.0
	for t in b.enemy_definition.transitions:
		if t.id == "patrol_noise": t.to = "search"
	add_child(a)
	add_child(b)
	a.set_physics_process(false)
	b.set_physics_process(false)
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(100, 0, 0)
	check(is_equal_approx(a._machine.current().speed, 1.6), "旧场景导出速度兼容")
	a.heard_noise(Vector3(1, 0, 0), 8.0, null)
	check(a.state == GuardAI.State.SUSPICIOUS and a.state_timer() == 6.0, "旧枚举与听觉接口兼容")
	b.heard_noise(Vector3(101, 0, 0), 8.0, null)
	check(b._machine.state_id == "search", "守卫真实读取编辑后的转换")
	b._machine.restore({"state_id": "suspicious", "timer": 2.0})
	check(b._machine.current().speed == 7.0 and b.state_timer() == 2.0, "显式定义的行为参数生效")
	var original := a.tl_capture()
	a.alert_level = 100.0
	a._evaluate_enemy("perception")
	check(a.state == GuardAI.State.ALERT, "实际感知进入编辑的警戒状态")
	var exposed := a.tl_capture()
	a.tl_restore(original)
	check(a.state == GuardAI.State.SUSPICIOUS and a.alert_level == 25.0, "守卫快照恢复完整状态")
	a.tl_restore(exposed)
	check(a.state == GuardAI.State.ALERT, "恢复快照后警戒状态一致")
	original.erase("enemy_machine")
	a.tl_restore(original)
	check(a.state == GuardAI.State.SUSPICIOUS and a.state_timer() == 6.0, "旧版快照回退兼容")
	a.state = GuardAI.State.PATROL
	a.alert_level = 0.0
	a.has_last_known = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var baseline := a.tl_capture()
	a.heard_noise(Vector3.ZERO, 8.0, null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	a.tl_restore(baseline)
	check(a.state == GuardAI.State.PATROL and a.alert_level == 0.0, "编辑器快照恢复运行器状态")
	var packet := a.enemy_runtime_state()
	check(packet.definition.ends_with("legacy_guard.tres") and packet.state_id == "patrol", "调试包对应当前定义与回溯状态")
	a.queue_free()
	b.queue_free()
	await get_tree().physics_frame


func _test_route() -> void:
	var scene := load("res://tools/enemy_editor/fixtures/guard_blueprint_sample.tscn") as PackedScene
	var sample := scene.instantiate()
	add_child(sample)
	var guard := sample.get_node("Guard") as GuardAI
	guard.set_physics_process(false)
	sample.get_node("Target").set_physics_process(false)
	check(guard.patrol_points.size() == 4 and guard.patrol_points[0].is_equal_approx(guard.get_node("PatrolRoute/Point1").global_position), "三维 Marker3D 路线实际控制守卫巡逻目标")
	check(not guard.tl_capture().enemy_machine.has("definition") and not guard.tl_capture().enemy_machine.has("layout"), "回溯快照只存实例状态")
	sample.queue_free()
	await get_tree().physics_frame
