extends Node
const VISUAL := preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd")
const DATA := preload("res://addons/godot_level_editor/modules/enemy_editor/appearance_data.gd")
var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1
	print("[PASS] " if value else "[FAIL] ", label)

func bounds_of(visual: Node3D, model: Node3D) -> AABB:
	return VISUAL.model_bounds(model)

func fixture(scale_value: Vector3, angles: Vector3, offset: Vector3) -> Node3D:
	var root := Node3D.new()
	root.rotation_degrees = angles
	root.scale = scale_value
	root.position = offset
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 2.4, 1.1)
	part.mesh = mesh
	part.position = Vector3(0.8, 3.5, -0.6)
	part.rotation_degrees = Vector3(-8, 12, 5)
	root.add_child(part)
	return root

func verify_fit(model: Node3D, height: float, label: String) -> void:
	var visual := VISUAL.new()
	visual.target_height = height
	visual.model = model
	visual.add_child(model)
	var before := model.transform
	var before_bounds := bounds_of(visual, model)
	var factor := height / before_bounds.size.y
	visual._fit_to_height(model)
	var after := model.transform
	var bounds := bounds_of(visual, model)
	check(is_equal_approx(bounds.size.y, height) and absf(bounds.position.y) < 0.0001, label + "：实际高度准确且脚底贴地")
	check(after.basis.is_equal_approx(before.basis.scaled(Vector3.ONE * factor)), label + "：保留根旋转与非均匀缩放比例")
	check(is_equal_approx(after.origin.x, before.origin.x * factor) and is_equal_approx(after.origin.z, before.origin.z * factor), label + "：水平偏移按同一尺度转换")
	visual._fit_to_height(model)
	check(model.transform.is_equal_approx(after), label + "：重复适配不会累计缩放或偏移")
	visual.free()

func pose_fixture() -> PackedScene:
	var root := Node3D.new(); root.name = "FourLegPoseFixture"
	var mesh := MeshInstance3D.new(); mesh.name = "Body"; mesh.mesh = BoxMesh.new(); root.add_child(mesh); mesh.owner = root
	var rig := Skeleton3D.new(); rig.name = "Skeleton"; root.add_child(rig); rig.owner = root
	var names := ["root", "LeftUpperArm", "LeftForeArm", "LeftHand", "RightUpperArm", "RightForeArm", "RightHand"]
	var parents := [-1, 0, 1, 2, 0, 4, 5]
	var positions := [Vector3.ZERO, Vector3(-0.2, 0.75, 0), Vector3(-0.2, -0.3, 0), Vector3(-0.1, -0.25, 0), Vector3(0.2, 0.75, 0), Vector3(0.2, -0.3, 0), Vector3(0.1, -0.25, 0)]
	for i in names.size():
		rig.add_bone(names[i]); rig.set_bone_parent(i, parents[i]); rig.set_bone_rest(i, Transform3D(Basis.IDENTITY, positions[i]))
	var packed := PackedScene.new(); packed.pack(root); root.free(); return packed

func verify_pose_modes() -> void:
	var data := DATA.new(); data.model = pose_fixture()
	check(data.pose_mode == "humanoid_t", "旧资源及新配置的默认模式仍为人形 T Pose")
	var visual := VISUAL.new(); visual.appearance = data; add_child(visual)
	check(visual.pose_status == "T Pose", "默认模式仍识别并展开同名手臂骨骼")
	var signature := data.signature()
	data.pose_mode = "rest"
	check(signature != data.signature() and data.validate().is_empty(), "自然静止模式计入外观变更签名且通过校验")
	visual.reset_pose()
	var all_rest := true
	for i in visual.skeleton.get_bone_count():
		all_rest = all_rest and visual.skeleton.get_bone_global_pose(i).is_equal_approx(visual.skeleton.get_bone_global_rest(i))
	check(all_rest and visual.pose_status == "自然静止姿态", "自然模式重置到绑定姿态，不强制抬起四足同名手臂")
	var direction: Vector3 = visual.skeleton.get_bone_global_pose(3).origin - visual.skeleton.get_bone_global_pose(1).origin
	check(direction.y < -0.5, "自然模式保留前腿向下的原始方向")
	check(not visual.play("Walking_A") and visual.pose_status == "自然静止姿态", "未配置动作回到自然静止姿态")
	data.pose_mode = "unsupported"
	check(not data.validate().is_empty(), "拒绝不支持的静止姿态模式")
	visual.free()

func verify_animal_skin(id: String, height: float) -> void:
	var definition := load("res://addons/godot_level_editor/resources/enemies/samples_v1/" + id + ".tres") as EnemyDefinition
	var visual := VISUAL.new(); visual.appearance = definition.appearance; add_child(visual)
	var rest := VISUAL.model_bounds(visual.model)
	check(visual.errors.is_empty() and absf(rest.size.y - height) < 0.0001 and absf(rest.position.y) < 0.0001, id + "：真实蒙皮高度正确且脚底贴地")
	visual.play("idle", 0); visual.anim.advance(0.35); visual.anim.pause()
	var pose := VISUAL.model_bounds(visual.model)
	check(absf(pose.size.y - height) < height * 0.05 and absf(pose.position.y) < height * 0.05, id + "：原始待机动作不再放大、缩小或悬空")
	visual.free()

func verify_skin_influences(influences: int, named: bool) -> void:
	var root := Node3D.new(); root.position = Vector3(3, 4, 5); root.rotation_degrees.y = 23; root.scale = Vector3(2, 3, 4)
	var rig := Skeleton3D.new(); root.add_child(rig)
	var skin := Skin.new(); skin.set_bind_count(influences)
	for i in influences:
		rig.add_bone("bone_" + str(i))
		var rest := Transform3D(Basis.IDENTITY, Vector3(0, i * 3.0, 0)); rig.set_bone_rest(i, rest)
		skin.set_bind_pose(i, rest.affine_inverse())
		if named: skin.set_bind_name(i, "bone_" + str(i))
		else: skin.set_bind_bone(i, i)
	rig.reset_bone_poses()
	for i in influences: rig.set_bone_pose_position(i, rig.get_bone_rest(i).origin + Vector3(0, 2, 0))
	var vertices := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var bones := PackedInt32Array(); var weights := PackedFloat32Array()
	for vertex in vertices.size():
		for i in influences: bones.append(i); weights.append(1.0 / influences)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_BONES] = bones; arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if influences == 8 else 0)
	var instance := MeshInstance3D.new(); instance.mesh = mesh; instance.skin = skin; instance.skeleton = NodePath(".."); instance.position.y = 0.5; rig.add_child(instance)
	var bounds := VISUAL.model_bounds(root)
	# ArrayMesh stores normalized skin weights at finite precision.
	check(absf(bounds.position.y - 11.5) < 0.001 and absf(bounds.size.y - 3) < 0.0001, "%d 权重与%s正确映射骨骼，包含模型根及网格变换" % [influences, "骨骼名称" if named else "骨骼索引"])
	var attachment := BoneAttachment3D.new(); rig.add_child(attachment)
	var accessory := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3.ONE * 1000; accessory.mesh = box; attachment.add_child(accessory)
	check(VISUAL.model_bounds(root).is_equal_approx(bounds), "%d 权重边界保持排除骨骼挂件约定" % influences)
	root.free()

func _ready() -> void:
	verify_fit(fixture(Vector3(0.01, 0.03, 0.02), Vector3(17, 33, -11), Vector3(2.5, -4.2, 1.7)), 1.85, "厘米级带旋转的人形源")
	verify_fit(fixture(Vector3(40, 55, 30), Vector3(-13, 72, 8), Vector3(-1.6, 7.8, 3.1)), 0.25, "小动物目标与超大源尺度")
	verify_fit(fixture(Vector3.ONE, Vector3.ZERO, Vector3(0, 1.2, 0)), 0.12, "小体型静止模型")
	var packed := load("res://addons/godot_level_editor/assets/characters/quaternius_base/adapted_human.tscn") as PackedScene
	var model := VISUAL.instantiate_model(packed)
	check(model != null, "已有真实角色仍可读取")
	if model != null: verify_fit(model, 1.8, "已有 Quaternius 角色")
	verify_pose_modes()
	verify_animal_skin("animal_pug", 0.45)
	verify_animal_skin("animal_sheep", 0.9)
	verify_skin_influences(4, false)
	verify_skin_influences(8, true)
	print("NPC VISUAL FIT: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
