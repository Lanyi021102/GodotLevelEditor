class_name VisionCone
extends Node3D
## 守卫的视觉传感器（docs/GDD.md §6.1）
##
## 判定三件事：距离、视锥角度、视线遮挡（LOS）。
## 距离会被"目标所处光照"和"目标是否蹲着"打折：
##   - 暗区里视距 ×dark_range_scale（默认 0.4）
##   - 蹲着的目标视距 ×crouch_range_scale（默认 0.8）
## LOS 射线只跟第 1 层（世界）碰撞，角色在第 2 层，所以角色不会自己挡住自己。

@export var angle_degrees := 70.0
@export var range_m := 12.0
@export var dark_range_scale := 0.4
@export var crouch_range_scale := 0.8
@export var eye_height := 1.5
@export var target_height := 0.9
## LOS 射线只考虑世界层（第 1 层）
@export var los_mask := 1

## 观察方向（由守卫 AI 每帧写入，水平方向）
var look_dir := Vector3(0.0, 0.0, -1.0)

@export_group("可视化")
## 是否在地上画出视锥扇形（潜行游戏没这个没法玩）
@export var draw_visual := true
@export var visual_segments := 20
@export var visual_alpha := 0.22

var _visual: MeshInstance3D
var _visual_mesh := ImmediateMesh.new()
var _visual_mat := StandardMaterial3D.new()


## 扫一次，返回看到的最优目标
## { seen: bool, target: Node3D, distance: float, range: float, dark: bool, crouched: bool }
func _ready() -> void:
	if not draw_visual:
		return
	_visual_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_visual_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_visual_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_visual_mat.albedo_color = Color(0.85, 0.90, 1.0, visual_alpha)
	_visual = MeshInstance3D.new()
	_visual.name = "ConeVisual"
	_visual.top_level = true          # 顶点直接用世界坐标，不受父节点变换影响
	_visual.mesh = _visual_mesh
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)


## 在地上画一块扇形：白 = 平常，黄 = 起疑，红 = 发现
func _update_visual(reach: float, alert_ratio: float) -> void:
	if _visual == null:
		return
	var origin := global_position + Vector3.UP * 0.08
	var forward := Vector3(look_dir.x, 0.0, look_dir.z)
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	var half := deg_to_rad(angle_degrees * 0.5)
	_visual_mesh.clear_surfaces()
	_visual_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _visual_mat)
	for i in visual_segments:
		var a0 := -half + 2.0 * half * float(i) / float(visual_segments)
		var a1 := -half + 2.0 * half * float(i + 1) / float(visual_segments)
		var p0 := origin + forward.rotated(Vector3.UP, a0) * reach
		var p1 := origin + forward.rotated(Vector3.UP, a1) * reach
		_visual_mesh.surface_add_vertex(origin)
		_visual_mesh.surface_add_vertex(p0)
		_visual_mesh.surface_add_vertex(p1)
	_visual_mesh.surface_end()
	if alert_ratio >= 0.999:
		_visual_mat.albedo_color = Color(1.0, 0.32, 0.26, visual_alpha * 1.9)
	elif alert_ratio > 0.01:
		_visual_mat.albedo_color = Color(1.0, 0.82, 0.30, visual_alpha * 1.5).lerp(
			Color(1.0, 0.32, 0.26, visual_alpha * 1.9), alert_ratio)
	else:
		_visual_mat.albedo_color = Color(0.85, 0.90, 1.0, visual_alpha)


## alert_ratio：守卫当前警觉值（0-100），用来给扇形上色
func scan(alert_ratio := 0.0) -> Dictionary:
	var result := {
		"seen": false, "target": null, "distance": 0.0, "range": 0.0,
		"dark": false, "crouched": false,
	}
	var forward := Vector3(look_dir.x, 0.0, look_dir.z)
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	var origin := global_position + Vector3.UP * eye_height

	var visual_reach := range_m
	for node in get_tree().get_nodes_in_group("stealth_target"):
		if not (node is Node3D) or not (node as Node3D).is_visible_in_tree():
			continue
		var target := node as Node3D
		var tp := target.global_position
		var dark: bool = get_node("/root/GLELightZones").is_dark(tp)
		var crouched: bool = target.has_method("is_crouching") and target.is_crouching()
		var reach := range_m
		if dark:
			reach *= dark_range_scale
		if crouched:
			reach *= crouch_range_scale
		var flat := Vector3(tp.x - global_position.x, 0.0, tp.z - global_position.z)
		var distance := flat.length()
		if distance > reach:
			continue
		if distance > 0.01:
			var dir := flat.normalized()
			if rad_to_deg(forward.angle_to(dir)) > angle_degrees * 0.5:
				continue
		visual_reach = maxf(visual_reach, reach)
		if not _has_line_of_sight(origin, tp + Vector3.UP * target_height):
			continue
		if not result["seen"] or distance < float(result["distance"]):
			result = {
				"seen": true, "target": target, "distance": distance,
				"range": reach, "dark": dark, "crouched": crouched,
			}
	_update_visual(visual_reach, clampf(float(alert_ratio) / 100.0, 0.0, 1.0))
	return result


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = los_mask
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()
