@tool
extends CharacterModel
## The same model, skeleton and optional animations are used in the editor and game.
const DATA := preload("res://addons/godot_level_editor/modules/enemy_editor/appearance_data.gd")
var appearance: Resource
## Generated NPC scenes reference the same definition for native 3D editor preview.
@export var npc_definition: EnemyDefinition
var errors := PackedStringArray()
var skeleton: Skeleton3D
var pose_status := ""

func _ready() -> void:
	if npc_definition != null: appearance = npc_definition.appearance
	setup()

func setup() -> void:
	if appearance == null: return
	errors = appearance.validate()
	if not errors.is_empty(): return
	model = instantiate_model(appearance.model)
	if model == null:
		errors.append("模型必须是三维场景。")
		return
	add_child(model)
	target_height = appearance.height
	skeleton = model.get_node_or_null(appearance.skeleton_path) as Skeleton3D if not appearance.skeleton_path.is_empty() else null
	if skeleton == null and not skeletons(model).is_empty(): skeleton = skeletons(model)[0]
	if not appearance.skeleton_path.is_empty() and skeleton == null: errors.append("所选骨骼已不存在，请重新选择。")
	if appearance.skeleton_source != null: _replace_skeleton()
	if not errors.is_empty(): return
	anim = AnimationPlayer.new()
	anim.name = "NPCMotion"
	anim.root_node = NodePath("..")
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	add_child(anim)
	var library := AnimationLibrary.new()
	for slot in appearance.motions:
		var motion: Animation = _motion(appearance.motions[slot])
		if motion != null: library.add_animation(slot, motion)
	anim.add_animation_library("", library)
	reset_pose()
	_fit_to_height(model)

func _fit_to_height(inst: Node3D) -> void:
	# Bounds include the imported root transform. Scale that entire transform
	# uniformly, then offset its lowest point to this component's local floor.
	# Replacing root.scale would discard source units and nonuniform proportions.
	if not is_finite(target_height) or target_height <= 0.0: return
	var combined := model_bounds(inst)
	if not combined.position.is_finite() or not combined.size.is_finite() or combined.size.y <= 0.000000001: return
	var factor := target_height / combined.size.y
	if not is_finite(factor) or factor <= 0.0: return
	var fitted := inst.transform
	fitted.basis = fitted.basis.scaled(Vector3.ONE * factor)
	fitted.origin *= factor
	fitted.origin.y -= combined.position.y * factor
	inst.transform = fitted

static func model_bounds(node: Node3D) -> AABB:
	# Evaluate skinning from CPU authoring data. Some FBX meshes have a static
	# vertex box that differs greatly from their visible, bound rest shape.
	# This is an explicit load/inspection operation, never a per-frame GPU read.
	var transforms: Dictionary = {}
	var meshes: Array[MeshInstance3D] = []
	_bounds_nodes(node, Transform3D.IDENTITY, transforms, meshes)
	var result := AABB(); var first := true
	for mesh in meshes:
		var transform: Transform3D = transforms[mesh]
		var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		var skin := mesh.skin
		if skin == null or rig == null:
			var bounds := transform * mesh.get_aabb()
			result = bounds if first else result.merge(bounds); first = false
			continue
		var bind_transforms: Array[Transform3D] = []
		var bind_valid := PackedByteArray()
		for i in skin.get_bind_count():
			var bone := rig.find_bone(skin.get_bind_name(i)) if not str(skin.get_bind_name(i)).is_empty() else skin.get_bind_bone(i)
			var valid := bone >= 0 and bone < rig.get_bone_count()
			bind_valid.append(1 if valid else 0)
			bind_transforms.append(rig.get_bone_global_pose(bone) * skin.get_bind_pose(i) if valid else Transform3D.IDENTITY)
		var skinned := false
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			var bones: Variant = arrays[Mesh.ARRAY_BONES]
			var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			if not vertices is PackedVector3Array or vertices.is_empty(): continue
			var influences := int(bones.size() / vertices.size()) if bones != null else 0
			var has_weights: bool = influences in [4, 8] and weights != null and weights.size() == bones.size()
			for vertex in vertices.size():
				var original: Vector3 = vertices[vertex]
				var point := original
				if has_weights:
					for influence in influences:
						var index: int = vertex * influences + influence
						var weight: float = weights[index]
						var bind: int = bones[index]
						if weight <= 0.0 or bind < 0 or bind >= bind_valid.size() or bind_valid[bind] == 0: continue
						point += (bind_transforms[bind] * original - original) * weight
				point = transform * point
				if first: result = AABB(point, Vector3.ZERO); first = false
				else: result = result.expand(point)
				skinned = true
		if not skinned:
			var bounds := transform * mesh.get_aabb()
			result = bounds if first else result.merge(bounds); first = false
	return result

static func _bounds_nodes(node: Node, parent_transform: Transform3D, transforms: Dictionary, meshes: Array[MeshInstance3D]) -> void:
	if node is BoneAttachment3D: return
	var transform := parent_transform
	if node is Node3D:
		transform *= node.transform
		transforms[node] = transform
	if node is MeshInstance3D and node.mesh != null: meshes.append(node)
	for child in node.get_children(): _bounds_nodes(child, transform, transforms, meshes)

static func instantiate_model(scene: PackedScene) -> Node3D:
	if scene == null: return null
	var node := scene.instantiate()
	if not node is Node3D:
		node.free()
		return null
	_sanitize(node)
	return node

static func _sanitize(node: Node) -> void:
	# Imported art is data; never run scene scripts or autoplay while previewing it.
	node.owner = null
	node.set_script(null)
	if node is AnimationPlayer:
		node.stop()
		node.autoplay = ""
		node.active = false
	if node is AnimationTree: node.active = false
	if node is SkeletonModifier3D: node.active = false
	for child in node.get_children(): _sanitize(child)

static func skeletons(node: Node) -> Array[Skeleton3D]:
	var result: Array[Skeleton3D] = []
	if node is Skeleton3D: result.append(node)
	for child in node.get_children(): result.append_array(skeletons(child))
	return result

static func animation_catalog(scene: PackedScene) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var node := instantiate_model(scene)
	if node == null: return result
	for player in node.find_children("*", "AnimationPlayer", true, false):
		for clip in player.get_animation_list():
			if clip != "RESET": result.append({"source": scene, "player": node.get_path_to(player), "clip": str(clip)})
	node.free()
	return result

func _replace_skeleton() -> void:
	var donor := instantiate_model(appearance.skeleton_source)
	var imported: Skeleton3D = donor.get_node_or_null(appearance.source_skeleton_path) as Skeleton3D if donor != null else null
	if skeleton == null or imported == null:
		errors.append("请先选择模型内已蒙皮的骨架，再导入匹配的骨骼。")
	else:
		var compatible := skeleton.get_bone_count() == imported.get_bone_count()
		for i in skeleton.get_bone_count():
			if not compatible: break
			compatible = skeleton.get_bone_name(i) == imported.get_bone_name(i) and skeleton.get_bone_parent(i) == imported.get_bone_parent(i) and skeleton.get_bone_rest(i).is_equal_approx(imported.get_bone_rest(i))
		if not compatible:
			errors.append("骨骼与模型的蒙皮不匹配：骨骼名称、层级及绑定姿态必须一致。")
		else:
			var replacement := imported.duplicate() as Skeleton3D
			for child in replacement.get_children(): child.free()
			replacement.name = skeleton.name
			replacement.transform = skeleton.transform
			var parent := skeleton.get_parent()
			var children := skeleton.get_children()
			parent.remove_child(skeleton)
			parent.add_child(replacement)
			for child in children:
				skeleton.remove_child(child)
				replacement.add_child(child)
			if skeleton == model: model = replacement
			skeleton.free()
			skeleton = replacement
	if donor != null: donor.free()

func _motion(spec: Dictionary) -> Animation:
	if skeleton == null:
		errors.append("模型没有骨架，无法添加骨骼动画。")
		return null
	var source := instantiate_model(spec.source)
	var player: AnimationPlayer = source.get_node_or_null(spec.player) as AnimationPlayer if source != null else null
	if player == null or not player.has_animation(spec.clip):
		errors.append("动画片段已不存在：" + str(spec.clip))
		if source != null: source.free()
		return null
	var motion := player.get_animation(spec.clip).duplicate(true) as Animation
	var animation_root := player.get_node_or_null(player.root_node)
	# FBX armatures can be rotated, so local Z may be the visible up axis.
	var rig_basis := Basis.IDENTITY
	var ancestor: Node = skeleton
	while ancestor != null and ancestor != self:
		if ancestor is Node3D: rig_basis = ancestor.transform.basis * rig_basis
		ancestor = ancestor.get_parent()
	var missing := PackedStringArray()
	for track in range(motion.get_track_count() - 1, -1, -1):
		var path := motion.track_get_path(track)
		var kind := motion.track_get_type(track)
		var source_rig: Skeleton3D = animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D if animation_root != null else null
		if source_rig == null or path.get_subname_count() != 1 or kind not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
			motion.remove_track(track)
			continue
		var bone := str(path.get_subname(0))
		var target_index := skeleton.find_bone(bone)
		var source_index := source_rig.find_bone(bone)
		if target_index < 0 or source_index < 0:
			missing.append(bone)
			continue
		motion.track_set_path(track, NodePath(str(get_path_to(skeleton)) + ":" + bone))
		var target_rest := skeleton.get_bone_rest(target_index)
		var source_rest := source_rig.get_bone_rest(source_index)
		var correction := (target_rest.basis.orthonormalized() * source_rest.basis.orthonormalized().inverse()).get_rotation_quaternion()
		var ratio := target_rest.origin.length() / source_rest.origin.length() if source_rest.origin.length() > 0.0001 else 1.0
		for key in motion.track_get_key_count(track):
			if kind == Animation.TYPE_ROTATION_3D:
				var value: Quaternion = motion.track_get_key_value(track, key)
				motion.track_set_key_value(track, key, (correction * value).normalized())
			elif kind == Animation.TYPE_POSITION_3D:
				var value: Vector3 = motion.track_get_key_value(track, key)
				var position := target_rest.origin + (value - source_rest.origin) * ratio
				if skeleton.get_bone_parent(target_index) < 0:
					# Kinematic movement owns horizontal travel; preserve authored
					# vertical bob/jump in component space, including rotated FBX rigs.
					var movement := rig_basis * (position - target_rest.origin)
					position = target_rest.origin + rig_basis.inverse() * Vector3(0, movement.y, 0)
				motion.track_set_key_value(track, key, position)
	if not missing.is_empty(): errors.append("动画骨骼不匹配：" + ", ".join(missing.slice(0, 5)))
	if motion.get_track_count() == 0: errors.append("动画没有可用于所选骨架的轨道。")
	source.free()
	if not errors.is_empty(): return null
	motion.loop_mode = Animation.LOOP_LINEAR
	return motion

func play(clip: String, blend := 0.15) -> bool:
	var slot: String = {"Idle": "idle", "Walking_A": "walk", "Running_A": "run"}.get(clip, clip)
	if anim == null or not anim.has_animation(slot):
		reset_pose()
		return false
	if anim.current_animation == slot and anim.is_playing(): return false
	# Clear the static T pose before applying tracks, including unanimated bones.
	if skeleton != null: skeleton.reset_bone_poses()
	anim.play(slot, blend)
	return true

func set_tint(_color: Color, _alpha := 1.0) -> void:
	pass # Imported NPCs retain their own materials.

func reset_pose() -> void:
	if anim != null: anim.stop()
	if model == null: return
	for rig in skeletons(model): rig.reset_bone_poses()
	if appearance != null and appearance.pose_mode == "rest":
		pose_status = "自然静止姿态"
		return
	pose_status = "静态模型" if skeleton == null else "静止姿态（未识别人形手臂）"
	if skeleton == null: return
	var arms := 0
	for side in ["left", "right"]:
		var upper := _find_bone(side, "upper")
		var lower := _find_bone(side, "lower")
		var hand := _find_bone(side, "hand")
		if upper < 0 or lower < 0 or hand < 0: continue
		var direction := skeleton.get_bone_global_rest(hand).origin - skeleton.get_bone_global_rest(upper).origin
		if absf(direction.x) < 0.0001: continue
		var horizontal := Vector3(signf(direction.x), 0, 0)
		_align_bone(upper, lower, horizontal)
		_align_bone(lower, hand, horizontal)
		arms += 1
	if arms == 2: pose_status = "T Pose"

func _find_bone(side: String, part: String) -> int:
	var suffix := "l" if side == "left" else "r"
	var roots: Array = {"upper": ["upperarm", "arm"], "lower": ["lowerarm", "forearm"], "hand": ["hand", "wrist", "fist"]}[part]
	for i in skeleton.get_bone_count():
		var bone := str(skeleton.get_bone_name(i)).get_slice(":", str(skeleton.get_bone_name(i)).get_slice_count(":") - 1).to_lower().replace("_", "").replace(".", "").replace("-", "")
		for key in roots:
			if bone in [side + key, key + suffix, suffix + key, key + side]: return i
	return -1

func _align_bone(bone: int, child: int, direction: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := skeleton.get_bone_global_pose(child).origin - pose.origin
	if current.length_squared() < 0.000001: return
	pose.basis = Basis(Quaternion(current.normalized(), direction)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
