@tool
extends RefCounted

const SEQUENCE := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sequence.gd")
var root: Node3D
var sequence: Resource
var camera: Camera3D
var base_camera: Camera3D
var fallback_pose := Transform3D.IDENTITY
var fallback_lens := {}
var shot: Dictionary = {}
var bindings := {}
var ordered: Array[Dictionary] = []

func bind(data: Resource, source: Node3D, display: Node3D, shot_camera: Camera3D) -> void:
	sequence = data
	root = display
	camera = shot_camera
	ordered = data.ordered_clips()
	bindings.clear()
	var candidates := SEQUENCE.npc_choices(source)
	for key in candidates:
		if not data.clips.any(func(clip: Dictionary): return clip.get("actor", "") == key): continue
		var original: Node3D = candidates[key]
		var actor := display.get_node_or_null(source.get_path_to(original)) as Node3D
		if actor == null: continue
		var facing := SEQUENCE.visual_root(actor) if original.get("enemy_instance_id") is String else actor
		var motion := SEQUENCE.motion_player(actor)
		bindings[key] = {
			"actor": actor, "facing": facing, "position": display.to_local(actor.global_position),
			"basis": display.global_basis.inverse() * facing.global_basis, "motion": motion,
			"motion_names": SEQUENCE.motion_names(actor), "physics": actor.is_physics_processing(),
			"process": actor.is_processing(), "input": actor.is_processing_input(),
			"velocity": actor.velocity if actor is CharacterBody3D else Vector3.ZERO,
		}

func sample(time: float, preview := false) -> bool:
	shot = {}
	var poses := {}
	for key in bindings:
		var binding: Dictionary = bindings[key]
		if not is_instance_valid(binding.actor) or not is_instance_valid(binding.facing): return false
		poses[key] = {"point": binding.position, "basis": binding.basis, "motion": _default_motion(binding, false), "elapsed": time}
	for clip in ordered:
		if float(clip.start) > time: break
		var active := time < SEQUENCE.end_of(clip)
		if clip.kind == "camera":
			if active: shot = clip
			continue
		if not poses.has(clip.actor): continue
		var pose: Dictionary = poses[clip.actor]
		var elapsed := time - float(clip.start)
		match str(clip.kind):
			"place": pose.point = clip.point
			"turn": _face(pose, clip.point - pose.point)
			"move":
				var path := PackedVector3Array([pose.point])
				path.append_array(clip.get("via", PackedVector3Array()))
				path.append(clip.point)
				_step(pose, path, clampf(elapsed / float(clip.duration), 0.0, 1.0))
				if active:
					pose.motion = _default_motion(bindings[clip.actor], true)
					pose.elapsed = elapsed
	for clip in ordered:
		if clip.kind != "action" or time < float(clip.start) or time >= SEQUENCE.end_of(clip) or not poses.has(clip.actor): continue
		poses[clip.actor].motion = str(clip.motion)
		poses[clip.actor].elapsed = time - float(clip.start)
	for key in poses:
		var binding: Dictionary = bindings[key]
		var pose: Dictionary = poses[key]
		binding.actor.global_position = root.to_global(pose.point)
		binding.facing.global_basis = root.global_basis * pose.basis
		_apply_motion(binding.motion, pose.motion, pose.elapsed)
	if is_instance_valid(camera):
		if not shot.is_empty():
			camera.global_transform = (root.global_transform * shot.pose).orthonormalized()
			_apply_lens(shot)
			camera.make_current()
		elif preview:
			camera.global_transform = fallback_pose
			_apply_lens(fallback_lens)
			camera.make_current()
		elif is_instance_valid(base_camera):
			base_camera.make_current()
	return true

func _apply_lens(lens: Dictionary) -> void:
	camera.keep_aspect = int(lens.get("keep_aspect", Camera3D.KEEP_HEIGHT))
	camera.projection = int(lens.get("projection", Camera3D.PROJECTION_PERSPECTIVE))
	camera.fov = float(lens.get("fov", 65.0))
	camera.size = float(lens.get("size", 6.0))

func _step(pose: Dictionary, path: PackedVector3Array, fraction: float) -> void:
	var total := 0.0
	for index in range(1, path.size()): total += path[index - 1].distance_to(path[index])
	var remaining := total * fraction
	for index in range(1, path.size()):
		var start := path[index - 1]
		var end := path[index]
		var length := start.distance_to(end)
		if is_zero_approx(length): continue
		if remaining <= length or index == path.size() - 1:
			pose.point = start.lerp(end, clampf(remaining / length, 0.0, 1.0))
			_face(pose, end - start)
			return
		remaining -= length

func _face(pose: Dictionary, direction: Vector3) -> void:
	var target := Vector2(direction.x, direction.z)
	var forward := Vector2(pose.basis.z.x, pose.basis.z.z)
	if target.length_squared() > 0.000001 and forward.length_squared() > 0.000001:
		var delta := atan2(target.x, target.y) - atan2(forward.x, forward.y)
		pose.basis = Basis(Vector3.UP, delta) * pose.basis

func _default_motion(binding: Dictionary, walk: bool) -> String:
	var names: PackedStringArray = binding.motion_names
	var aliases := ["walk", "walking"] if walk else ["idle", "idle0"]
	for key in names:
		if key.get_file().to_lower() in aliases: return key
	return _default_motion(binding, false) if walk else ""

func _apply_motion(player: AnimationPlayer, name_text: String, elapsed: float) -> void:
	if not is_instance_valid(player): return
	if name_text.is_empty():
		if player.is_playing(): player.stop()
		return
	if player.assigned_animation != name_text or not player.is_playing():
		if player.name == &"NPCMotion":
			for skeleton in player.get_parent().find_children("*", "Skeleton3D", true, false): skeleton.reset_bone_poses()
		player.play(name_text, 0.0)
	var animation := player.get_animation(name_text)
	var time := fposmod(elapsed, animation.length) if animation.loop_mode != Animation.LOOP_NONE else minf(elapsed, animation.length)
	player.seek(time, true, true)

func suspend_actors() -> void:
	for binding in bindings.values():
		var actor: Node3D = binding.actor
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.set_process_input(false)
		if actor is CharacterBody3D: actor.velocity = Vector3.ZERO
		var motion: AnimationPlayer = binding.motion
		if is_instance_valid(motion):
			binding["callback_mode"] = motion.callback_mode_process
			binding["previous_motion"] = str(motion.assigned_animation)
			binding["previous_playing"] = motion.is_playing()
			binding["previous_time"] = motion.current_animation_position if motion.is_playing() else 0.0
			motion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

func release_actors(keep_pose: bool) -> void:
	for binding in bindings.values():
		var actor: Node3D = binding.actor
		if not is_instance_valid(actor): continue
		if not keep_pose and is_instance_valid(binding.facing):
			actor.global_position = root.to_global(binding.position)
			binding.facing.global_basis = root.global_basis * binding.basis
		if actor is CharacterBody3D: actor.velocity = Vector3.ZERO if keep_pose else binding.velocity
		if keep_pose and actor.has_method("finish_performance_pose"): actor.finish_performance_pose(binding.facing.transform.basis.z)
		var motion: AnimationPlayer = binding.motion
		if is_instance_valid(motion):
			motion.callback_mode_process = binding.callback_mode
			if not keep_pose and binding.previous_playing:
				_apply_motion(motion, binding.previous_motion, binding.previous_time)
			elif not keep_pose: motion.stop(true)
			elif not str(motion.assigned_animation).is_empty(): motion.play(str(motion.assigned_animation))
		actor.set_physics_process(binding.physics)
		actor.set_process(binding.process)
		actor.set_process_input(binding.input)
