extends SceneTree
## Reproducible CC0 assembly: fit the free male and retarget the free locomotion library.
const DIR := "res://addons/godot_level_editor/assets/characters/quaternius_base/"
const CLIPS := {
	"Idle": "Idle", "Walking_A": "Walk", "Running_A": "Jog_Fwd",
	"Walking_C": "Crouch_Fwd", "Crouch_Idle": "Crouch_Idle",
	"Jump_Start": "Jump_Start", "Jump_Idle": "Jump", "Jump_Land": "Jump_Land",
}

func find_type(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := find_type(child, type)
		if found != null: return found
	return null

func own_tree(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		own_tree(child, owner_node)

func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var gltf_error := document.append_from_file(DIR + "Superhero_Male_FullBody.gltf", state)
	if gltf_error != OK:
		push_error("Cannot read the CC0 character glTF")
		quit(1)
		return
	var raw: Node3D = document.generate_scene(state)
	var source: Node3D = load(DIR + "UAL1_Standard.glb").instantiate()
	var result := Node3D.new()
	result.name = "AdaptedHuman"
	root.add_child(result)
	raw.name = "Body"
	raw.scale = Vector3(0.86, 1.0, 0.90)
	result.add_child(raw)
	root.add_child(source)
	var target_skeleton: Skeleton3D = find_type(raw, "Skeleton3D")
	var source_skeleton: Skeleton3D = find_type(source, "Skeleton3D")
	var source_player: AnimationPlayer = find_type(source, "AnimationPlayer")
	var old_player := find_type(raw, "AnimationPlayer")
	if old_player != null: old_player.free()
	var player := AnimationPlayer.new()
	player.name = "Locomotion"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	result.add_child(player)
	var library := AnimationLibrary.new()
	var missing_bones: Array[String] = []
	var pelvis := target_skeleton.find_bone("pelvis")
	var source_pelvis := source_skeleton.find_bone("pelvis")
	var height_ratio := target_skeleton.get_bone_global_rest(pelvis).origin.y / source_skeleton.get_bone_global_rest(source_pelvis).origin.y
	for alias: String in CLIPS:
		var original: Animation = source_player.get_animation(CLIPS[alias])
		var animation: Animation = original.duplicate(true)
		animation.resource_name = alias
		animation.loop_mode = Animation.LOOP_NONE if alias in ["Jump_Start", "Jump_Land"] else Animation.LOOP_LINEAR
		for track in range(animation.get_track_count() - 1, -1, -1):
			var path := animation.track_get_path(track)
			if path.get_subname_count() == 0:
				animation.remove_track(track)
				continue
			var bone := str(path.get_subname(0))
			var target_index := target_skeleton.find_bone(bone)
			var source_index := source_skeleton.find_bone(bone)
			if target_index < 0 or source_index < 0:
				missing_bones.append(bone)
				animation.remove_track(track)
				continue
			var kind := animation.track_get_type(track)
			if kind == Animation.TYPE_SCALE_3D:
				animation.remove_track(track)
				continue
			animation.track_set_path(track, NodePath(str(result.get_path_to(target_skeleton)) + ":" + bone))
			var target_rest := target_skeleton.get_bone_rest(target_index)
			var source_rest := source_skeleton.get_bone_rest(source_index)
			var correction := (target_rest.basis.orthonormalized() * source_rest.basis.orthonormalized().inverse()).get_rotation_quaternion()
			for key in animation.track_get_key_count(track):
				if kind == Animation.TYPE_ROTATION_3D:
					var rotation: Quaternion = animation.track_get_key_value(track, key)
					animation.track_set_key_value(track, key, (correction * rotation).normalized())
				elif kind == Animation.TYPE_POSITION_3D:
					var position: Vector3 = animation.track_get_key_value(track, key)
					# Locomotion is kinematic: root motion must never shift the mesh away from its capsule.
					position = target_rest.origin if bone == "root" else target_rest.origin + (position - source_rest.origin) * height_ratio
					animation.track_set_key_value(track, key, position)
		library.add_animation(alias, animation)
	player.add_animation_library("", library)
	# Retain an adult head width while narrowing the athletic source body's silhouette.
	var head := target_skeleton.find_bone("Head")
	target_skeleton.set_bone_pose_scale(head, Vector3(1.12, 1.10, 1.12))
	result.set_meta("source_model", "Quaternius Superhero Male - free Standard, proportion adjusted")
	result.set_meta("body_width_scale", 0.86)
	result.set_meta("body_depth_scale", 0.90)
	result.set_meta("head_scale", Vector3(1.12, 1.10, 1.12))
	own_tree(result, result)
	var packed := PackedScene.new()
	var err := packed.pack(result)
	if err == OK: err = ResourceSaver.save(packed, DIR + "adapted_human.tscn")
	var info := {
		"source_bones": source_skeleton.get_bone_count(), "target_bones": target_skeleton.get_bone_count(),
		"missing_bones": missing_bones, "pelvis_height_ratio": height_ratio,
		"body_scale": [0.86, 1.0, 0.90], "head_scale": [1.12, 1.10, 1.12],
		"clips": CLIPS, "saved": err == OK,
	}
	var file := FileAccess.open(DIR + "assembly.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(info, "\t"))
	file.close()
	print("HUMANOID_ASSEMBLY ", JSON.stringify(info))
	result.free()
	source.free()
	quit(0 if err == OK and missing_bones.is_empty() else 1)
