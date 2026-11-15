extends Node
const DATA := preload("res://addons/enemy_editor/appearance_data.gd")
const VISUAL := preload("res://addons/enemy_editor/npc_visual.gd")
const STORE := preload("res://addons/enemy_editor/definition_store.gd")
const TEMPLATE := preload("res://addons/enemy_editor/runtime/guard_template.gd")
const MODEL := "res://assets/characters/quaternius_base/adapted_human.scn"
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func _ready() -> void:
	var data := DATA.new()
	data.model = load(MODEL)
	var source := VISUAL.instantiate_model(data.model)
	data.skeleton_path = source.get_path_to(VISUAL.skeletons(source)[0])
	source.free()
	var visual := VISUAL.new(); visual.appearance = data; add_child(visual)
	check(visual.errors.is_empty() and visual.skeleton != null and visual.skeleton.get_bone_count() > 20, "导入真实模型并保留蒙皮骨骼")
	check(visual.pose_status == "T Pose" and not visual.anim.is_playing(), "未选动画时显示 T Pose，不自动播放自带动画")
	var horizontal := true
	for side in ["left", "right"]:
		var upper: int = visual._find_bone(side, "upper"); var hand: int = visual._find_bone(side, "hand")
		if upper < 0 or hand < 0: horizontal = false; continue
		var direction: Vector3 = visual.skeleton.get_bone_global_pose(hand).origin - visual.skeleton.get_bone_global_pose(upper).origin
		horizontal = horizontal and absf(direction.normalized().y) < 0.01
	check(horizontal, "T Pose 的双臂实际水平展开")
	check(not visual.play("Idle") and not visual.anim.is_playing(), "没有配置的待机动作不会退回旧默认动画")
	var catalog := VISUAL.animation_catalog(data.model)
	check(catalog.size() >= 3, "读取导入模型中的动画列表")
	for motion in catalog:
		if motion.clip == "Walking_A": data.motions.walk = motion
	var animated := VISUAL.new(); animated.appearance = data; add_child(animated)
	check(animated.errors.is_empty() and animated.play("Walking_A") and animated.anim.current_animation == "walk", "选中的走路动作可以实际播放")
	animated.anim.advance(0.2)
	check(not animated.play("Idle") and animated.pose_status == "T Pose" and not animated.anim.is_playing(), "未配置待机时从走路恢复 T Pose")
	var external := load("res://assets/characters/quaternius_base/UAL1_Standard.glb") as PackedScene
	for motion in VISUAL.animation_catalog(external):
		if motion.clip == "Walk": data.motions.walk = motion
	var retargeted := VISUAL.new(); retargeted.appearance = data; add_child(retargeted)
	check(retargeted.errors.is_empty() and retargeted.play("walk"), "可选用另一个文件中同名骨骼的动画")
	var donor := VISUAL.instantiate_model(data.model)
	data.skeleton_source = data.model; data.source_skeleton_path = donor.get_path_to(VISUAL.skeletons(donor)[0]); donor.free()
	var skeleton_copy := VISUAL.new(); skeleton_copy.appearance = data; add_child(skeleton_copy)
	check(skeleton_copy.errors.is_empty() and skeleton_copy.skeleton.get_bone_count() == visual.skeleton.get_bone_count(), "匹配的外部骨架能替换模型骨架并保留蒙皮")
	var incompatible := Skeleton3D.new(); incompatible.name = "Skeleton"; incompatible.add_bone("wrong")
	var packed := PackedScene.new(); packed.pack(incompatible); incompatible.free()
	data.skeleton_source = packed; data.source_skeleton_path = NodePath(".")
	var rejected := VISUAL.new(); rejected.appearance = data; add_child(rejected)
	check(not rejected.errors.is_empty(), "不匹配骨架明确拒绝，避免破坏模型")
	data.skeleton_source = null; data.source_skeleton_path = NodePath()
	var definition := TEMPLATE.create(); definition.appearance = data
	var path := "res://tools/enemy_editor/.npc_visual_roundtrip.tres"
	check(STORE.save_definition(definition, path) == OK, "NPC 定义保存模型、骨骼与可选动作")
	var loaded := STORE.load_definition(path)
	check(loaded != null and loaded.appearance.signature() == data.signature(), "关闭重读后外观配置完整保留")
	var dependencies := ResourceLoader.get_dependencies(path)
	check(str(dependencies).contains("adapted_human.scn") and str(dependencies).contains("UAL1_Standard.glb"), "模型和动画作为资源依赖保存，可随游戏导出")
	var guard := load("res://scenes/guard.tscn").instantiate() as GuardAI
	definition.appearance.motions = {}; guard.enemy_definition = definition; add_child(guard); guard.set_physics_process(false)
	check(guard._model.get_script() == VISUAL and guard._model.pose_status == "T Pose", "关卡运行使用 NPC 编辑器设置的模型与 T Pose")
	var old_guard := load("res://scenes/guard.tscn").instantiate() as GuardAI; add_child(old_guard); old_guard.set_physics_process(false)
	check(old_guard._model.get_script() == load("res://scripts/actors/character_model.gd"), "旧 NPC 未配置外观时保留原角色组件")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("NPC VISUAL: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
