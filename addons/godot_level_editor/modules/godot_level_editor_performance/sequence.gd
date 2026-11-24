@tool
extends Resource

const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const MIN_LENGTH := 0.1
const MAX_TIME := 300.0
const LABELS := {"camera": "镜头", "place": "设定站位", "move": "移动到", "turn": "转向", "action": "播放动作"}

@export_storage var id := ""
@export_storage var display_name := "新演出"
@export_storage var input_mode := 0 # 0: 根据镜头自动选择，1: 保留操作，2: 锁定操作
@export_storage var actors := PackedStringArray()
@export_storage var clips: Array[Dictionary] = []

static func lookup(world: Node, key: String) -> Resource:
	if not is_instance_valid(world) or key.is_empty(): return null
	for item in world.get("performances"):
		if item != null and item.id == key: return item
	return null

static func choices(world: Node) -> Dictionary:
	var result := {}
	if not is_instance_valid(world): return result
	for item in world.get("performances"):
		if item != null: result[item.id] = item.display_name
	return result

static func npc_choices(world: Node) -> Dictionary:
	var result := {}
	var ambiguous := {}
	var groups := preload("res://addons/godot_level_editor/modules/godot_level_editor/scene_groups.gd")
	_index_npcs(groups.contents(world), "$world", result, ambiguous)
	for room in world.rooms(): _index_npcs(groups.contents(room), str(room.room_id), result, ambiguous)
	return result

static func _index_npcs(nodes: Array[Node], scope: String, result: Dictionary, ambiguous: Dictionary) -> void:
	for node in nodes:
		if not node is Node3D: continue
		var profile: Resource = node.get_meta(PROFILE.META) if node.has_meta(PROFILE.META) else null
		var id: Variant = node.get("enemy_instance_id")
		if not id is String:
			if not (node is GLEDialogueNPC or (profile != null and profile.kind == "npc")): continue
			id = node.get("object_id")
		if not id is String or not id.is_valid_identifier(): continue
		var key: String = scope + "/" + id
		if ambiguous.has(key): continue
		if result.has(key):
			result.erase(key)
			ambiguous[key] = true
		else:
			result[key] = node

static func visual_root(actor: Node3D) -> Node3D:
	var preview := actor.get_node_or_null("ModelPreview") as Node3D
	if preview != null and preview.visible: return preview
	var model := actor.get_node_or_null("ModelRoot") as Node3D
	return model if model != null else actor

static func motion_player(actor: Node3D) -> AnimationPlayer:
	var scope := visual_root(actor)
	var fallback: AnimationPlayer
	for player in scope.find_children("*", "AnimationPlayer", true, false):
		if player.name == &"NPCMotion": return player
		if fallback == null and not player.get_animation_list().is_empty(): fallback = player
	return fallback

static func motion_names(actor: Node3D) -> PackedStringArray:
	var player := motion_player(actor)
	var names := PackedStringArray()
	if player != null:
		for key in player.get_animation_list():
			if key.get_file() != "RESET":
				var animation := player.get_animation(key)
				var pose_only := true
				for track in animation.get_track_count():
					if animation.track_get_type(track) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION]:
						pose_only = false
						break
				if pose_only: names.append(key)
	return names

static func end_of(clip: Dictionary) -> float:
	return snappedf(float(clip.start) + float(clip.duration), 0.001)

static func track_of(clip: Dictionary) -> String:
	return "" if clip.kind == "camera" else str(clip.actor) + ("/action" if clip.kind == "action" else "/pose")

func duration() -> float:
	var latest := 0.0
	for clip in clips: latest = maxf(latest, end_of(clip))
	return latest

func ordered_clips() -> Array[Dictionary]:
	var sorted: Array[Dictionary] = clips.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.start) < float(b.start))
	return sorted

func locks_input() -> bool:
	return input_mode == 2 or (input_mode == 0 and clips.any(func(clip: Dictionary): return clip.kind == "camera"))

func validate(world: Node, task_id := "", restrict_scope := false, check_motions := true) -> PackedStringArray:
	var errors := PackedStringArray()
	var npcs := npc_choices(world)
	var ends := {}
	var ids := {}
	for clip in ordered_clips():
		var label := str(clip.get("label", LABELS.get(clip.kind, "")))
		var start := float(clip.start)
		var length := float(clip.duration)
		if not LABELS.has(clip.kind) or ids.has(clip.id) or not is_finite(start + length) or start < 0 or length < MIN_LENGTH or end_of(clip) > MAX_TIME:
			errors.append("片段无效：" + label)
			continue
		ids[clip.id] = true
		var track := track_of(clip)
		if start + 0.0001 < float(ends.get(track, 0.0)): errors.append("同一轨道的片段重叠：" + label)
		ends[track] = end_of(clip)
		if clip.kind == "camera":
			if not clip.get("pose") is Transform3D or not clip.pose.is_finite(): errors.append("请设置镜头构图：" + label)
			continue
		var actor: Node3D = npcs.get(clip.actor)
		if actor == null or not clip.actor in actors:
			errors.append("找不到片段绑定的 NPC：" + label)
			continue
		if restrict_scope:
			var parent: Node = actor
			while parent != world and parent != null:
				var profile: Resource = parent.get_meta(PROFILE.META) if parent.has_meta(PROFILE.META) else null
				if profile != null and profile.lifetime == "task" and (task_id.is_empty() or str(profile.task_id) != task_id):
					errors.append("NPC 不属于当前演出的触发范围：" + str(actor.name))
					break
				parent = parent.get_parent()
		if clip.kind in ["place", "move", "turn"] and (not clip.get("point") is Vector3 or not clip.point.is_finite()):
			errors.append("请在视口设置目标点：" + label)
		if check_motions and clip.kind == "action" and not str(clip.get("motion", "")) in motion_names(actor):
			errors.append("找不到 NPC 动作：" + label)
	return errors

static func validate_graph_binding(world: Node3D, node: Dictionary, task_id := "") -> PackedStringArray:
	var data := lookup(world, str(node.params.get("performance", "")))
	var prefix := str(node.id) + "："
	if data == null: return PackedStringArray([prefix + "当前关卡找不到绑定的演出"])
	if data.clips.is_empty(): return PackedStringArray([prefix + "演出没有片段"])
	var errors: PackedStringArray = data.validate(world, task_id, true)
	for index in errors.size(): errors[index] = prefix + errors[index]
	return errors
