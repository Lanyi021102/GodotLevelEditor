@tool
extends Resource
## Optional appearance. A null appearance on old definitions keeps their original model.
@export var model: PackedScene
@export var skeleton_path: NodePath
@export var skeleton_source: PackedScene
@export var source_skeleton_path: NodePath
@export var animation_sources: Array[PackedScene] = []
## idle/walk/run -> {source: PackedScene, player: NodePath, clip: String}.
@export var motions: Dictionary = {}
@export var height := 1.8

func signature() -> String:
	var sources: Array[String] = []
	for source in animation_sources: sources.append(source.resource_path)
	var clips: Array = []
	for slot in ["idle", "walk", "run"]:
		var motion: Dictionary = motions.get(slot, {})
		clips.append([slot, motion.source.resource_path, motion.player, motion.clip] if not motion.is_empty() else [slot])
	return var_to_str([model.resource_path if model != null else "", skeleton_path, skeleton_source.resource_path if skeleton_source != null else "", source_skeleton_path, sources, clips, height])

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if model == null: errors.append("请先导入 NPC 模型。")
	if not is_finite(height) or height < 0.1 or height > 20.0: errors.append("角色身高应在 0.1–20 m 之间。")
	for slot in motions:
		var motion: Variant = motions[slot]
		if slot not in ["idle", "walk", "run"] or not motion is Dictionary:
			errors.append("动画配置无效。")
		elif not motion.get("source") is PackedScene or not motion.get("player") is NodePath or str(motion.get("clip", "")).is_empty():
			errors.append("动画来源或片段缺失。")
	return errors
