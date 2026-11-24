class_name CharacterModel
extends Node3D
## 角色模型组件：把下载来的 .glb 角色装进场景，并统一处理
##   - 灰白覆写材质与可配置角色染色
##   - 按包围盒缩放到 target_height，脚底贴 y = 0
##   - 动画跟随固定物理帧推进
##   - 位移动画设为循环（否则播完会被引擎重置成空动画名）
##
## 基础玩家和兼容角色共用此组件；自定义 NPC 由其外观资源配置。

@export_file("*.glb", "*.gltf", "*.scn", "*.tscn") var model_scene := "res://addons/godot_level_editor/assets/characters/quaternius_base/adapted_human.tscn"
@export var target_height := 1.8
## 是否在 _ready 里自动装载（关掉则由宿主脚本手动 setup()）
@export var auto_setup := true
## 覆写成灰白材质，贴合白模风格
@export var white_model := true
@export var white_albedo := Color(0.86, 0.86, 0.875)

@export_group("动画片段")
@export var idle_clip := "Idle"
@export var walk_clip := "Walking_A"
@export var run_clip := "Running_A"
@export var crouch_clip := "Walking_C"
## 这些片段会被设成循环播放
@export var loop_hints: PackedStringArray = ["Idle", "Walking", "Running"]

var anim: AnimationPlayer
var model: Node3D
var model_override: PackedScene

var _native_overrides: Dictionary = {}
var _material: StandardMaterial3D
var _tint := Color(0.86, 0.86, 0.875)
var _tint_alpha := 1.0


func _ready() -> void:
	if auto_setup:
		setup()


func setup() -> void:
	var packed := model_override
	if packed == null and not model_scene.is_empty() and ResourceLoader.exists(model_scene):
		packed = load(model_scene) as PackedScene
	if packed == null:
		push_error("角色模型不存在：%s" % model_scene)
		return
	var instance := packed.instantiate()
	if not instance is Node3D:
		instance.free()
		push_error("角色模型需要 Node3D 场景根。")
		return
	model = instance
	add_child(model)
	_remember_overrides(model)
	if white_model:
		_apply_white_material(model)
	_fit_to_height(model)
	anim = _find_animation_player(model)
	if anim == null:
		push_warning("模型里没有 AnimationPlayer：%s" % model_scene)
	else:
		_configure_animations(anim)


# --------------------------------------------------------------------------
# 对外
# --------------------------------------------------------------------------
## 播放动画（同一片段正在播就跳过）。返回是否真的调用了 play
func play(clip: String, blend := 0.15) -> bool:
	if anim == null or clip == "" or not anim.has_animation(clip):
		return false
	if anim.current_animation == clip and anim.is_playing():
		return false
	anim.play(clip, blend)
	return true


func current_clip() -> String:
	return anim.current_animation if anim != null else ""


func set_speed_scale(value: float) -> void:
	if anim != null:
		anim.speed_scale = value


## 染色；alpha < 1 时使用半透明材质。
func set_tint(color: Color, alpha := 1.0) -> void:
	_tint = color
	_tint_alpha = alpha
	_apply_tint()


func use_textured_body() -> void:
	white_model = false
	_apply_tint()

func _remember_overrides(node: Node) -> void:
	if node is MeshInstance3D:
		_native_overrides[node] = node.material_override
	for child in node.get_children():
		_remember_overrides(child)

func _apply_tint() -> void:
	if not white_model and _tint_alpha >= 0.999 and _tint.is_equal_approx(white_albedo):
		for mesh in _native_overrides:
			mesh.material_override = _native_overrides[mesh]
		return
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.roughness = 0.75
	_override_materials(model, _material)
	for mesh in _native_overrides:
		mesh.material_overlay = null
	_material.emission_enabled = _tint_alpha < 0.999
	_material.emission = _tint
	_material.emission_energy_multiplier = 0.45
	_material.albedo_color = Color(_tint.r, _tint.g, _tint.b, _tint_alpha)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if _tint_alpha < 0.999 \
		else BaseMaterial3D.TRANSPARENCY_DISABLED


func measured_height() -> float:
	if model == null:
		return 0.0
	var acc: Array[AABB] = []
	_collect_aabbs(model, Transform3D.IDENTITY, acc, false)
	if acc.is_empty():
		return 0.0
	var union: AABB = acc[0]
	for i in range(1, acc.size()):
		union = union.merge(acc[i])
	# _collect_aabbs already includes the model root's transform and scale.
	return union.size.y


# --------------------------------------------------------------------------
# 内部
# --------------------------------------------------------------------------
func _apply_white_material(node: Node) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = white_albedo
	m.roughness = 0.85
	m.metallic = 0.0
	m.metallic_specular = 0.2
	_material = m
	_override_materials(node, m)


func _override_materials(node: Node, m: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = m
	for c in node.get_children():
		_override_materials(c, m)


## 关键：动画必须跟着固定步长的物理帧推进，否则时间线回退不可复现（GDD §10.3）
func _configure_animations(ap: AnimationPlayer) -> void:
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	for lib_name in ap.get_animation_library_list():
		var lib := ap.get_animation_library(lib_name)
		for clip_name in lib.get_animation_list():
			var is_loop := clip_name in loop_hints
			if not is_loop:
				for hint in loop_hints:
					if String(clip_name).contains(String(hint)):
						is_loop = true
						break
			if is_loop:
				lib.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR


## 把模型缩放到 target_height，并让脚底贴在 y = 0
func _fit_to_height(inst: Node3D) -> void:
	var acc: Array[AABB] = []
	_collect_aabbs(inst, Transform3D.IDENTITY, acc, false)
	if acc.is_empty():
		return
	var union: AABB = acc[0]
	for i in range(1, acc.size()):
		union = union.merge(acc[i])
	if union.size.y < 0.05:
		return
	var s := clampf(target_height / union.size.y, 0.2, 5.0)
	inst.scale = Vector3.ONE * s
	inst.position.y = -union.position.y * s


## 只统计骨架上的网格；挂在骨骼挂点上的装饰（披风等）会干扰包围盒，跳过
func _collect_aabbs(node: Node3D, xform: Transform3D, acc: Array[AABB], under_bone_attach: bool) -> void:
	var t := xform * node.transform
	var skip := under_bone_attach or node is BoneAttachment3D
	if node is MeshInstance3D and not skip:
		acc.append(t * (node as MeshInstance3D).get_aabb())
	for c in node.get_children():
		if c is Node3D:
			_collect_aabbs(c, t, acc, skip)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null
