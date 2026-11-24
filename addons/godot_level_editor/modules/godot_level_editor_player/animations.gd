@tool
extends RefCounted
## Extra stock clips for the bundled Quaternius rig. Kinematic movement owns root translation.
const SOURCE := preload("res://addons/godot_level_editor/assets/characters/quaternius_base/UAL1_Standard.glb")
const CMU_CLIMB := preload("res://addons/godot_level_editor/assets/characters/player_motion/ladder_climb.tres")
const CMU_STEP := preload("res://addons/godot_level_editor/assets/characters/player_motion/step_over.tres")
const CLIPS := {"Sprint": "Sprint", "Roll": "Roll", "Interact": "Interact"}
static var _library: AnimationLibrary

static func find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found := find_player(child)
		if found != null: return found
	return null

static func attach(player: AnimationPlayer) -> void:
	if player == null or player.has_animation_library("moves"): return
	if _library == null: _library = _build(player)
	if _library != null: player.add_animation_library("moves", _library.duplicate_deep(Resource.DEEP_DUPLICATE_ALL))

static func external_library(player: AnimationPlayer, packed: PackedScene, selected := PackedStringArray()) -> AnimationLibrary:
	if player == null or packed == null: return null
	var target_root := player.get_node_or_null(player.root_node)
	if target_root == null: return null
	var target := _first_skeleton(target_root)
	if target == null or target.find_bone("pelvis") < 0: return null
	var source_scene := packed.instantiate()
	var source_player := find_player(source_scene)
	var source := _first_skeleton(source_scene)
	var library := AnimationLibrary.new()
	if source_player != null and source != null and source.find_bone("pelvis") >= 0:
		var matching := 0
		for i in source.get_bone_count():
			if target.find_bone(source.get_bone_name(i)) >= 0: matching += 1
		if matching * 4 >= mini(source.get_bone_count(), target.get_bone_count()) * 3:
			var path := str(target_root.get_path_to(target))
			for name: String in source_player.get_animation_list():
				if not selected.is_empty() and name not in selected: continue
				if not name.is_valid_filename() or name.contains("/"): continue
				var clip := _retarget(source_player.get_animation(name), source, target, path)
				if clip.get_track_count() > 0: library.add_animation(name, clip)
	source_scene.free()
	return library

static func _first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	var found := node.find_children("*", "Skeleton3D", true, false)
	return found.front() as Skeleton3D if not found.is_empty() else null


static func attach_vehicle(player: AnimationPlayer) -> void:
	if player.has_animation_library("vehicle"): return
	var library := external_library(player, SOURCE, PackedStringArray(["Sitting_Enter", "Sitting_Idle", "Sitting_Exit"]))
	if library == null: return
	if library.has_animation("Sitting_Idle"):
		library.get_animation("Sitting_Idle").loop_mode = Animation.LOOP_LINEAR
	player.add_animation_library("vehicle", library)

static func _build(player: AnimationPlayer) -> AnimationLibrary:
	var target := player.get_parent().get_node_or_null("Body/Armature/Skeleton3D") as Skeleton3D
	if target == null: return null
	var library := AnimationLibrary.new()
	var source := SOURCE.instantiate()
	var source_player := find_player(source)
	var source_root := source_player.get_node(source_player.root_node)
	var source_skeleton := source_root.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var path := str(player.get_node(player.root_node).get_path_to(target))
	for alias: String in CLIPS:
		if not source_player.has_animation(CLIPS[alias]): continue
		var clip := _retarget(source_player.get_animation(CLIPS[alias]), source_skeleton, target, path)
		library.add_animation(alias, clip)
	source.free()
	library.add_animation("Vault", _pose_clip(target, path, 0.45, [
		[0.0, {}],
		[0.26, {"spine_01": [-26, 0, 0], "upperarm_l": [-35, -20, -22], "upperarm_r": [-45, 25, 31], "thigh_l": [-30, 0, 0], "calf_l": [63, 0, 0]}],
		[0.53, {"spine_01": [-31, 0, 0], "upperarm_l": [-74, -15, -15], "upperarm_r": [-57, 16, 21], "thigh_r": [-78, 0, 4], "thigh_l": [-63, 0, -5], "calf_r": [83, 0, 0], "calf_l": [72, 0, 0]}],
		[0.78, {"spine_01": [-14, 0, 0], "thigh_r": [-15, 0, 0], "thigh_l": [-30, 0, 0], "calf_l": [44, 0, 0]}],
		[1.0, {}],
	]))
	library.add_animation("Mantle", _pose_clip(target, path, 0.65, [
		[0.0, {}],
		[0.22, {"upperarm_l": [-85, -8, -23], "upperarm_r": [-85, 8, 23], "lowerarm_l": [-17, 0, 0], "lowerarm_r": [-17, 0, 0]}],
		[0.48, {"spine_01": [-19, 0, 0], "upperarm_l": [-100, -8, -28], "upperarm_r": [-100, 8, 28], "thigh_l": [-55, 0, 0], "calf_l": [64, 0, 0]}],
		[0.75, {"spine_01": [-34, 0, 0], "upperarm_l": [-42, -8, -25], "upperarm_r": [-42, 8, 25], "thigh_l": [-66, 0, 0], "calf_l": [73, 0, 0], "thigh_r": [-19, 0, 0]}],
		[1.0, {}],
	]))
	library.add_animation("Climb", CMU_CLIMB)
	library.add_animation("StepOver", CMU_STEP)
	return library

static func _retarget(original: Animation, source: Skeleton3D, target: Skeleton3D, path: String) -> Animation:
	var clip := original.duplicate(true) as Animation
	var scale := target.get_bone_global_rest(target.find_bone("pelvis")).origin.y / source.get_bone_global_rest(source.find_bone("pelvis")).origin.y
	for track in range(clip.get_track_count() - 1, -1, -1):
		var input_path := clip.track_get_path(track)
		var bone := str(input_path.get_subname(0)) if input_path.get_subname_count() > 0 else ""
		var source_index := source.find_bone(bone)
		var target_index := target.find_bone(bone)
		var kind := clip.track_get_type(track)
		if source_index < 0 or target_index < 0 or kind not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]:
			clip.remove_track(track)
			continue
		clip.track_set_path(track, NodePath(path + ":" + bone))
		var src := source.get_bone_rest(source_index)
		var dst := target.get_bone_rest(target_index)
		var retarget := (dst.basis.orthonormalized() * src.basis.orthonormalized().inverse()).get_rotation_quaternion()
		for key in clip.track_get_key_count(track):
			if kind == Animation.TYPE_ROTATION_3D:
				var rotation: Quaternion = clip.track_get_key_value(track, key)
				clip.track_set_key_value(track, key, (retarget * rotation).normalized())
			else:
				var position: Vector3 = clip.track_get_key_value(track, key)
				clip.track_set_key_value(track, key, dst.origin if bone == "root" else dst.origin + (position - src.origin) * scale)
	return clip

static func _pose_clip(skeleton: Skeleton3D, path: String, duration: float, poses: Array) -> Animation:
	var animation := Animation.new()
	animation.length = duration
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath(path + ":" + bone))
		var rest := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		for pose in poses:
			var angles: Array = pose[1].get(bone, [0.0, 0.0, 0.0])
			var rotation := Quaternion.from_euler(Vector3(angles[0], angles[1], angles[2]) * PI / 180.0)
			animation.rotation_track_insert_key(track, float(pose[0]) * duration, (rest * rotation).normalized())
	return animation
