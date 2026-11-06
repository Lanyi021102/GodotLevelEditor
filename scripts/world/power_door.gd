@tool
class_name PowerDoor
extends StaticBody3D
const METRIC_GRID := preload("res://scripts/tools/metric_grid.gd")
## 受机关驱动的门（docs/GDD.md §8）：任意一个电源（压力板 / 电闸）通电就升起，断电就落下。
## 门是实体障碍——所以"分身的重放轨迹会被门挡住"，正是 P3 想展示的因果。

@export var panel_size := Vector3(3.2, 2.3, 0.4)
@export var open_height := 2.6
@export var slide_time := 0.9
@export var color_closed := Color(0.42, 0.48, 0.62, 1.0)
@export var color_open := Color(0.36, 0.80, 0.55, 1.0)
@export var use_metric_grid := false
## 代码里直接连的电源（房间生成器用），也支持在检查器里连 NodePath
@export var source_paths: Array[NodePath] = []
@export var require_all_sources := false
var power_nodes: Array[Node] = []

var open_ratio := 0.0

var _closed_y := 0.0
var _powered := false
var _material: StandardMaterial3D
var _grid_material: ShaderMaterial
var _panel: MeshInstance3D
var _shape: CollisionShape3D
var _design_signature: Array = []


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_closed_y = position.y
	rebuild_design()


## Geometry is generated without an owner, so authored scenes store parameters only.
func rebuild_design() -> void:
	for generated in [_panel, _shape]:
		if is_instance_valid(generated):
			generated.free()
	_material = StandardMaterial3D.new()
	_material.albedo_color = color_closed
	_material.roughness = 0.55
	_grid_material = METRIC_GRID.material(color_closed) if use_metric_grid else null
	_panel = MeshInstance3D.new()
	_panel.name = "Panel"
	var mesh := BoxMesh.new()
	mesh.size = panel_size
	_panel.mesh = mesh
	_panel.material_override = _grid_material if use_metric_grid else _material
	add_child(_panel)
	_shape = CollisionShape3D.new()
	_shape.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = panel_size
	_shape.shape = shape
	add_child(_shape)
	_design_signature = [panel_size, color_closed, color_open, open_height, use_metric_grid]
	_apply_offset()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _design_signature != [panel_size, color_closed, color_open, open_height, use_metric_grid]:
		rebuild_design()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_powered = _any_powered()
	var target := 1.0 if _powered else 0.0
	if not is_equal_approx(open_ratio, target):
		open_ratio = move_toward(open_ratio, target, delta / maxf(slide_time, 0.01))
		_apply_offset()


func _any_powered() -> bool:
	var sources: Array[Node] = power_nodes.duplicate()
	for path in source_paths:
		var node := get_node_or_null(path)
		if node != null:
			sources.append(node)
	if sources.is_empty():
		return false
	for node in sources:
		var active: bool = is_instance_valid(node) and node.has_method("is_powered") and node.is_powered()
		if require_all_sources and not active:
			return false
		if not require_all_sources and active:
			return true
	return require_all_sources


func _apply_offset() -> void:
	if not Engine.is_editor_hint():
		position.y = _closed_y + open_ratio * open_height
	_refresh_visual()


func _refresh_visual() -> void:
	if _material == null:
		return
	_material.albedo_color = color_closed.lerp(color_open, open_ratio)
	_material.emission_enabled = _powered
	_material.emission = color_open
	_material.emission_energy_multiplier = 0.5
	METRIC_GRID.update_state(_grid_material, _material.albedo_color, color_open, 0.5 if _powered else 0.0)


func is_open() -> bool:
	return open_ratio >= 0.99


func is_powered() -> bool:
	return _powered


func add_power_source(node: Node) -> void:
	if node != null and not power_nodes.has(node):
		power_nodes.append(node)


# --------------------------------------------------------------------------
# 时间线接口
# --------------------------------------------------------------------------
func tl_capture() -> Dictionary:
	return {"ratio": open_ratio, "powered": _powered}


func tl_restore(state: Dictionary) -> void:
	open_ratio = float(state["ratio"])
	_powered = bool(state["powered"])
	_apply_offset()
