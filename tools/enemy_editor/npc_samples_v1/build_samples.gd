extends Node
## Rebuild only this explicitly selected sample library, never user scenes.
const INPUT := "res://tools/enemy_editor/npc_samples_v1/sources.json"
const OUTPUT := "res://addons/godot_level_editor/resources/enemies/samples_v1/catalog.json"
const DATA := preload("res://addons/godot_level_editor/modules/enemy_editor/appearance_data.gd")
const VISUAL := preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd")
const IMPORT := preload("res://addons/godot_level_editor/modules/enemy_editor/model_import.gd")
const STORE := preload("res://addons/godot_level_editor/modules/enemy_editor/definition_store.gd")
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
var failed := false
var _cache: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	var catalog: Array[Dictionary] = []
	for row in config.samples:
		var result := build(row)
		if result.is_empty(): failed = true
		else: catalog.append(result)
	if not failed:
		var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
		output.store_string(JSON.stringify({"version": 1, "date": "2026-11-16", "sources": config.sources, "samples": catalog}, "\t")); output.close()
	print("NPC SAMPLE BUILD: ", catalog.size(), " built; failed=", failed)
	get_tree().quit(1 if failed else 0)

func import_model(path: String, id: String, yaw: float) -> PackedScene:
	var target := "res://addons/godot_level_editor/assets/characters/npc_samples_v1/imported/" + id + ".scn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	var document: GLTFDocument = FBXDocument.new() if path.get_extension().to_lower() == "fbx" else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if path.get_extension().to_lower() == "fbx" else GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	var error := document.append_from_file(path, state)
	if error != OK: push_error("Cannot import " + path); return null
	var model := document.generate_scene(state)
	if model == null: return null
	model = IMPORT._materialize(model)
	model.name = id.to_pascal_case()
	var texture_path := str(_cache.get("texture:" + id, ""))
	if not texture_path.is_empty():
		var image := Image.load_from_file(ProjectSettings.globalize_path(texture_path))
		if image == null: model.free(); push_error("Missing model texture " + texture_path); return null
		image.generate_mipmaps()
		var texture := ImageTexture.create_from_image(image)
		for instance in model.find_children("*", "MeshInstance3D", true, false):
			for surface in instance.mesh.get_surface_count():
				var original: Material = instance.mesh.surface_get_material(surface)
				var material: StandardMaterial3D = original.duplicate(true) as StandardMaterial3D if original is StandardMaterial3D else StandardMaterial3D.new()
				material.albedo_color = Color.WHITE; material.albedo_texture = texture
				instance.mesh.surface_set_material(surface, material)
	model.rotate_y(deg_to_rad(yaw))
	if id.begins_with("human_small_") or id.begins_with("human_medium_"):
		_neutral_idle_arm(model)
	IMPORT._own_children(model, model)
	var scene := PackedScene.new(); error = scene.pack(model); model.free()
	var uid := ResourceLoader.get_resource_uid(target) if FileAccess.file_exists(target) else ResourceUID.INVALID_ID
	if error == OK: error = ResourceSaver.save(scene, target, ResourceSaver.FLAG_BUNDLE_RESOURCES | ResourceSaver.FLAG_COMPRESS)
	if error == OK and uid != ResourceUID.INVALID_ID: error = ResourceSaver.set_uid(target, uid)
	if error != OK: push_error("Cannot save " + target); return null
	return ResourceLoader.load(target, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene

func _neutral_idle_arm(model: Node3D) -> void:
	# The old free FBX idle animates the left arm but omits the right arm,
	# leaving its bind pose extended. Prepare a neutral idle only on these
	# imported sample copies; all original files and other clips stay intact.
	get_tree().root.add_child(model)
	var rig: Skeleton3D = model.get_node("CharacterArmature/Skeleton3D")
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	var animation := player.get_animation("CharacterArmature|Idle")
	var direction := (rig.global_transform.basis.inverse() * Vector3.DOWN).normalized()
	for pair in [["UpperArm.R", "LowerArm.R"], ["LowerArm.R", "Fist.R"]]:
		var bone := rig.find_bone(pair[0]); var child := rig.find_bone(pair[1])
		var path := NodePath(str(player.get_node(player.root_node).get_path_to(rig)) + ":" + str(pair[0]))
		var exists := false
		for track in animation.get_track_count():
			if animation.track_get_path(track) == path and animation.track_get_type(track) == Animation.TYPE_ROTATION_3D: exists = true
		if exists or bone < 0 or child < 0: continue
		var pose := rig.get_bone_global_pose(bone)
		var axis := (rig.get_bone_global_pose(child).origin - pose.origin).normalized()
		pose.basis = Basis(Quaternion(axis, direction)) * pose.basis
		rig.set_bone_global_pose(bone, pose)
		var rotation := rig.get_bone_pose_rotation(bone)
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, path); animation.track_insert_key(track, 0.0, rotation); animation.track_insert_key(track, animation.length, rotation)
	rig.reset_bone_poses()
	model.set_meta("sample_idle_preparation", "Missing right-arm idle channels held in a neutral down pose")
	get_tree().root.remove_child(model)

func build(row: Dictionary) -> Dictionary:
	var definition_path := "res://addons/godot_level_editor/resources/enemies/samples_v1/" + str(row.id) + ".tres"
	var scene_path := "res://addons/godot_level_editor/scenes/npcs/v1_" + str(row.id) + ".tscn"
	if not OS.get_cmdline_user_args().has("--replace-generated") and (FileAccess.file_exists(definition_path) or FileAccess.file_exists(scene_path)):
		push_error("Sample already exists; explicitly use --replace-generated to rebuild: " + str(row.id)); return {}
	if FileAccess.file_exists(definition_path):
		var existing := STORE.load_definition(definition_path)
		if existing == null or existing.get_meta("npc_sample_v1", {}).get("id", "") != row.id:
			push_error("Refusing to overwrite an unowned NPC definition: " + definition_path); return {}
	_cache["texture:" + str(row.id)] = str(row.get("texture", ""))
	var model := import_model(row.source, row.id, float(row.get("yaw_degrees", 0.0)))
	if model == null: return {}
	var data := DATA.new(); data.model = model; data.height = float(row.height)
	data.pose_mode = "humanoid_t" if str(row.category) == "humanoid" else "rest"
	var node := VISUAL.instantiate_model(model)
	var rigs := VISUAL.skeletons(node)
	if rigs.is_empty(): push_error("Sample has no skeleton: " + str(row.id)); node.free(); return {}
	data.skeleton_path = node.get_path_to(rigs[0]); node.free()
	var animation_source := model
	if row.has("animation_source"):
		animation_source = load(str(row.animation_source)) as PackedScene
		data.animation_sources.append(animation_source)
	var motions := VISUAL.animation_catalog(animation_source)
	for slot in ["idle", "walk", "run"]:
		var clip := str(row.get("motions", {}).get(slot, ""))
		if clip.is_empty(): continue
		var found := false
		for motion in motions:
			if motion.clip == clip: data.motions[slot] = motion; found = true; break
		if not found: push_error("Missing clip " + clip + " for " + str(row.id)); return {}
	var probe := VISUAL.new(); probe.appearance = data; get_tree().root.add_child(probe)
	if not probe.errors.is_empty(): push_error(str(row.id) + ": " + "；".join(probe.errors)); probe.free(); return {}
	var bounds := mesh_bounds(probe.model)
	var bones := probe.skeleton.get_bone_count()
	probe.free()
	var definition := EnemyDefinition.new(); definition.display_name = row.title; definition.initial_state = "patrol"
	var can_walk := data.motions.has("walk")
	definition.states.assign([{"id": "patrol", "label": "平静行走" if can_walk else "原地待机", "behavior": "patrol" if can_walk else "idle", "speed": float(row.get("walk_speed", 1.2)) if can_walk else 0.0, "duration": 0.0, "scan_degrees": 0.0}])
	definition.layout.nodes = {"patrol": Vector2(100, 100)}
	definition.appearance = data
	var metadata: Dictionary = row.duplicate(true)
	metadata.merge({"definition": definition_path, "scene": scene_path, "preview_path": "res://addons/godot_level_editor/resources/enemies/samples_v1/previews/" + str(row.id) + ".png", "bone_count": bones, "animation_count": motions.size(), "available_animations": motions.map(func(item: Dictionary): return item.clip), "bounds": {"x": bounds.size.x, "y": bounds.size.y, "z": bounds.size.z}}, true)
	definition.set_meta("npc_sample_v1", metadata)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(definition_path.get_base_dir()))
	var error := STORE.save_definition(definition, definition_path)
	if error != OK: push_error("Cannot save NPC " + str(row.id)); return {}
	var saved := ResourceLoader.load(definition_path, "", ResourceLoader.CACHE_MODE_REPLACE) as EnemyDefinition
	var actor := preload("res://addons/godot_level_editor/modules/enemy_editor/runtime/npc_actor.tscn").instantiate() as GuardAI
	actor.name = row.title.validate_node_name(); actor.enemy_definition = saved
	var visual := actor.get_node("ModelRoot")
	visual.set_script(VISUAL); visual.npc_definition = saved
	var collision := actor.get_node("Collision") as CollisionShape3D
	if str(row.get("collision", "capsule")) == "box":
		var shape := BoxShape3D.new(); shape.size = Vector3(maxf(bounds.size.x * 0.65, 0.15), float(row.height) * 0.85, maxf(bounds.size.z * 0.7, 0.15))
		collision.shape = shape; collision.position = Vector3(0, shape.size.y * 0.5, 0)
	else:
		var shape := CapsuleShape3D.new(); shape.height = float(row.height); shape.radius = minf(float(row.get("radius", 0.3)), shape.height * 0.45)
		collision.shape = shape; collision.position = Vector3(0, shape.height * 0.5, 0)
	var profile := PROFILE.new(); profile.model_id = "default"; profile.faction = "friendly"; profile.body_height = row.height; profile.body_radius = float(row.get("radius", 0.3)); profile.behavior_definition = saved
	actor.set_meta(PROFILE.META, profile)
	actor.set_meta("npc_sample_v1", str(row.id))
	actor.set_meta("editor_display_name", str(row.title))
	var scene := PackedScene.new(); error = scene.pack(actor); actor.free()
	if error == OK: error = ResourceSaver.save(scene, scene_path)
	if error != OK: push_error("Cannot create NPC scene " + str(row.id)); return {}
	print("BUILT ", row.id, " ", bones, " bones / ", motions.size(), " animations; height=", bounds.size.y)
	return metadata

static func mesh_bounds(node: Node3D) -> AABB:
	return VISUAL.model_bounds(node)
