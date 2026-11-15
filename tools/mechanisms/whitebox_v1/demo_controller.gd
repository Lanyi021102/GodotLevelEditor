extends Node
## F6 showcase uses the same task schema/evaluator as the editor without modifying the user's workbook.
const RUNNER := preload("res://addons/godot_level_editor_narrative/runtime/task_runner.gd")
const ACTIONS := preload("res://addons/godot_level_editor_narrative/runtime/task_actions.gd")
var runners: Dictionary = {}
var completed: Dictionary = {}
var _actions: RefCounted
var _labels: Dictionary = {}

func _ready() -> void:
	process_physics_priority = 530
	var world := get_parent()
	_actions = ACTIONS.new(); _actions.world = world
	_actions.legacy = preload("res://addons/godot_level_editor/runtime/level_actions.gd").new(); _actions.legacy.world = world
	var bridge := preload("res://addons/godot_level_editor_mechanisms/task_bridge.gd").new(); add_child(bridge); bridge.bind_world(world, _broadcast)
	var layer := CanvasLayer.new(); add_child(layer)
	var panel := PanelContainer.new(); panel.position = Vector2(20, 110); panel.custom_minimum_size.x = 430; layer.add_child(panel)
	var style := StyleBoxFlat.new(); style.bg_color = Color(0.08, 0.13, 0.20, 0.9); style.set_content_margin_all(14); panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new(); panel.add_child(box)
	var header := Label.new(); header.text = "机关素材演示"; header.add_theme_font_size_override("font_size", 22); box.add_child(header)
	for id in ["button_door", "dual_plate_door", "terminal_lift"]:
		var runner := RUNNER.new(); var graph: Resource = load("res://resources/mechanisms/whitebox_v1/" + id + ".task.tres")
		if not runner.configure(graph, world.object_by_id, _action.bind(id), _actions.condition): push_error("机关示例任务配置失败：" + id); continue
		runners[id] = runner
		var label := Label.new(); label.text = "○ " + {"button_door": "左：按下按钮，等待滑门完全打开", "dual_plate_door": "中：配重箱 + 玩家同时压住两个压力板", "terminal_lift": "右：激活终端，等待升降台到达终点"}[id]; box.add_child(label); _labels[id] = label
	var hint := Label.new(); hint.text = "WASD 移动 · 鼠标观察 · F 交互\n配重箱可拿起，走到压力板上再放下。"; box.add_child(hint)
	if OS.get_cmdline_user_args().has("--whitebox-demo-capture"): _capture_demo.call_deferred()

func _broadcast(kind: String, context: Dictionary) -> void:
	for id in runners:
		if not completed.has(id): runners[id].queue_trigger(kind, context)

func _action(node: Dictionary, context: Dictionary, id: String) -> Dictionary:
	if node.kind == "task_complete":
		if not completed.has(id): completed[id] = true; _labels[id].text = str(_labels[id].text).replace("○", "✓")
		return {"ok": true, "reason": "机关已实际到位，示例目标完成"}
	return _actions.perform(node, context)

func _physics_process(delta: float) -> void:
	for id in runners:
		if not completed.has(id): runners[id].tick(delta)

func _capture_demo() -> void:
	for frame in 40: await get_tree().process_frame
	var main: Node = get_tree().get_first_node_in_group("main")
	if main != null and main.get("camera_rig") != null: main.camera_rig.release_mouse()
	var camera := Camera3D.new(); get_parent().add_child(camera)
	camera.attributes = CameraAttributesPractical.new(); camera.position = Vector3(25, 21, 30); camera.fov = 47; camera.look_at(Vector3(0, 0, 1)); camera.current = true
	for frame in 10: await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("res://docs/mechanism_editor/whitebox_v1")
	RenderingServer.force_draw(false); get_viewport().get_texture().get_image().save_png("res://docs/mechanism_editor/whitebox_v1/试玩初始.png")
	var player: Node3D = get_tree().get_first_node_in_group("godot_level_editor_player")
	var world := get_parent()
	var first: Node = world.get_node("ButtonDoor")
	player.global_position = first.bindings.button.global_position + Vector3.BACK
	first.bindings.button.interact(player)
	var third: Node = world.get_node("TerminalLift")
	player.global_position = third.bindings.terminal.global_position + Vector3.BACK
	third.bindings.terminal.interact(player)
	var second: Node = world.get_node("DualPlateDoor")
	world.get_node("Weight").global_position = second.bindings.plate_a.global_position + Vector3.UP * 0.45
	player.global_position = second.bindings.plate_b.global_position + Vector3.UP * 0.12
	for frame in 150: await get_tree().physics_frame
	RenderingServer.force_draw(false); get_viewport().get_texture().get_image().save_png("res://docs/mechanism_editor/whitebox_v1/试玩目标完成.png")
	print("DEMO OBJECTIVES COMPLETED: ", completed.size(), "/3")
	get_tree().quit(0 if completed.size() == 3 else 1)
