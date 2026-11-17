extends Node
const VISUAL := preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd")
const STORE := preload("res://addons/godot_level_editor/modules/enemy_editor/definition_store.gd")
const ASSETS := preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_catalog.gd")
const BUILD := preload("res://tools/enemy_editor/npc_samples_v1/build_samples.gd")
const CATALOG := "res://addons/godot_level_editor/resources/enemies/samples_v1/catalog.json"
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func _ready() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	check(catalog.samples.size() == 13, "首批13个样例：6人形、4动物、3怪物")
	var assets := ASSETS.assets("常驻 NPC")
	check(assets.size() == 13, "NPC 素材目录仅保留13个新示例")
	check(ASSETS.template("常驻 NPC", "level").path == "res://addons/godot_level_editor/scenes/npcs/v1_human_medium_male.tscn", "新建 NPC 默认使用导入人物模型")
	var receptionist := load("res://addons/godot_level_editor/scenes/narrative/npc.tscn").instantiate() as Node3D
	add_child(receptionist)
	check(receptionist.get_node("ModelRoot").get_script() == VISUAL and receptionist.get_node("ModelRoot").model != null, "旧对话 NPC 使用带骨骼模型替代胶囊")
	var has_capsule := false
	for mesh in receptionist.find_children("*", "MeshInstance3D", true, false): has_capsule = has_capsule or mesh.mesh is CapsuleMesh
	check(not has_capsule, "旧对话 NPC 不再生成胶囊网格")
	var player := Node3D.new(); add_child(player); player.add_to_group("godot_level_editor_player")
	receptionist.interaction_allowed = true
	check(receptionist.interact(player), "更换外观后原有 F 对话交互仍可触发")
	receptionist.queue_free(); player.queue_free()
	var actual_variants: Dictionary = {}
	for row in catalog.samples:
		var definition := STORE.load_definition(row.definition)
		check(definition != null and definition.validate().is_empty() and definition.transitions.is_empty(), row.id + "：定义有效，默认无敌对转换")
		check(assets.any(func(asset: Dictionary): return asset.path == row.scene), row.id + "：轮盘已有素材可发现")
		var actor := load(row.scene).instantiate() as GuardAI
		add_child(actor); actor.set_physics_process(false)
		var visual: CharacterModel = actor._model
		check(visual.get_script() == VISUAL and visual.errors.is_empty() and visual.skeleton.get_bone_count() == int(row.bone_count), row.id + "：实际NPC加载网格、骨架及绑定动画")
		var bounds := BUILD.mesh_bounds(visual.model)
		check(absf(bounds.size.y - float(row.height)) < 0.003 and absf(bounds.position.y) < 0.003, row.id + "：身高匹配，足底贴地")
		check(actor.get_node("Collision").shape != null and actor.get_node("Collision").position.y > 0 and actor.get_meta("godot_level_editor_entity").validate().is_empty(), row.id + "：碰撞与实例属性有效")
		if row.category == "humanoid":
			actual_variants[row.source] = true
			check(visual.pose_status == "T Pose", row.id + "：人形初始 T Pose")
		else:
			check(visual.pose_status == "自然静止姿态", row.id + "：非人形保留自然姿态")
		for slot in definition.appearance.motions:
			check(visual.play(slot), row.id + "：播放 " + slot)
			visual.anim.advance(0.01)
			var original := bone_poses(visual.skeleton)
			var changed := false
			for interval in [0.17, 0.23, 0.31]:
				visual.anim.advance(interval)
				changed = changed or original != bone_poses(visual.skeleton)
			check(changed, row.id + "：" + slot + " 实际驱动骨骼变化")
		if row.id in ["animal_pug", "animal_sheep"]:
			check(not definition.appearance.motions.has("walk") and not definition.appearance.motions.has("run") and definition.states[0].behavior == "idle", row.id + "：不伪造走跑，初始仅待机")
		if row.category == "monster":
			visual.play("walk", 0); visual.anim.advance(0.0)
			var root_bone: int = visual.skeleton.find_bone("Body")
			var original_position: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(root_bone).origin
			visual.anim.advance(0.14)
			var movement: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(root_bone).origin - original_position
			check(absf(movement.y) > 0.01 and absf(movement.x) < 0.001 and absf(movement.z) < 0.001, row.id + "：旋转骨架保留真实垂直步态，不产生水平根位移")
			var textured := false
			for mesh in visual.model.find_children("*", "MeshInstance3D", true, false):
				for i in mesh.mesh.get_surface_count():
					var material := mesh.mesh.surface_get_material(i) as StandardMaterial3D
					textured = textured or material != null and material.albedo_texture != null
			check(textured, row.id + "：原始怪物贴图已恢复")
		actor.free()
	check(actual_variants.size() == 6, "六个人形引用六个不同原模型")
	var source := STORE.load_definition(catalog.samples[0].definition)
	var temporary := "res://tools/enemy_editor/npc_samples_v1/.sample_roundtrip.tres"
	check(STORE.save_definition(source, temporary) == OK and STORE.load_definition(temporary).appearance.signature() == source.appearance.signature(), "另存并重读保留样例模型、姿态及动画")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	print("NPC SAMPLES V1: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func bone_poses(rig: Skeleton3D) -> Array:
	var result: Array = []
	for i in rig.get_bone_count(): result.append(rig.get_bone_pose(i))
	return result
