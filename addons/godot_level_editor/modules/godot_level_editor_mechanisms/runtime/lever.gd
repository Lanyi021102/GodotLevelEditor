@tool
extends Node3D
const METRIC_GRID := preload("res://addons/godot_level_editor/scripts/tools/metric_grid.gd")
## Passive interaction endpoint; the host provides actor input and interaction routing.
signal power_changed(powered: bool)
signal interacted(object_id: String, action: String, actor: Node3D)
@export var object_id := "lever"
@export var display_name := "拉杆"
@export var enabled := true
@export var initially_powered := false
@export_range(0.2, 6.0, 0.05) var interaction_radius := 1.8
@export_enum("保持开关", "定时复位", "单次开启") var mode := 0
@export_range(0.05, 60.0, 0.05) var reset_delay := 1.0
@export var box_size := Vector3(0.7, 0.9, 0.45)
@export var color_idle := Color("344b60")
@export var color_active := Color("5ed8c1")
@export var use_metric_grid := false
var powered := false
var remaining := 0.0
var used := false
var interaction_serial := 0
var _geometry: Node3D
var _pivot: Node3D
var _light: StandardMaterial3D
var _grid_light: ShaderMaterial
var _grid_casing: ShaderMaterial
var _signature: Array = []

func _init() -> void:
	set_meta("mechanism_kind", "lever")

func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("godot_level_editor_interactable")
		var prompt := preload("res://addons/godot_level_editor/scripts/ui/interaction_label.gd").new()
		prompt.configure(self, display_name, "[F]", true)
		prompt.position.y = 1.25
		add_child(prompt)
	reset_state()
	rebuild_design()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _signature != _design_values():
		reset_state()
		rebuild_design()

func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint(): advance(delta)

func advance(delta: float) -> void:
	if mode == 1 and powered:
		remaining = maxf(remaining - delta, 0.0)
		if remaining <= 0: set_powered(false)

func can_interact(actor: Node3D = null) -> bool:
	if not enabled or (mode == 2 and used): return false
	return actor == null or (is_instance_valid(actor) and actor.is_visible_in_tree() and global_position.distance_to(actor.global_position) <= interaction_radius)

func interact(actor: Node3D = null) -> bool:
	if not can_interact(actor): return false
	used = true
	interaction_serial += 1
	set_powered(not powered if mode == 0 else true)
	interacted.emit(object_id, "interact", actor)
	return true

func set_powered(value: bool) -> void:
	remaining = reset_delay if value and mode == 1 else 0.0
	if powered == value: return
	powered = value
	_refresh_visual()
	power_changed.emit(powered)

func is_powered() -> bool:
	return powered

func reset_state() -> void:
	powered = initially_powered
	remaining = reset_delay if powered and mode == 1 else 0.0
	used = false
	interaction_serial = 0
	_refresh_visual()

func _design_values() -> Array:
	return [box_size, color_idle, color_active, interaction_radius, initially_powered, mode, reset_delay, enabled, use_metric_grid]

func rebuild_design() -> void:
	if is_instance_valid(_geometry): _geometry.free()
	_geometry = Node3D.new()
	_geometry.name = "Generated"
	add_child(_geometry)
	var casing := StandardMaterial3D.new()
	casing.albedo_color = color_idle
	casing.roughness = 0.65
	_light = StandardMaterial3D.new()
	_light.emission_enabled = true
	_grid_casing = METRIC_GRID.material(color_idle) if use_metric_grid else null
	_grid_light = METRIC_GRID.material(color_idle) if use_metric_grid else null
	_box("Plinth", Vector3(box_size.x + 0.2, 0.12, box_size.z + 0.2), Vector3(0, 0.06, 0), casing, _geometry)
	_box("Box", box_size, Vector3(0, box_size.y * 0.5 + 0.12, 0), casing, _geometry)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, box_size.y * 0.65 + 0.12, box_size.z * 0.5)
	_geometry.add_child(_pivot)
	_box("Handle", Vector3(0.09, box_size.y * 0.7, 0.09), Vector3(0, box_size.y * 0.35, 0), _light, _pivot)
	_box("Grip", Vector3(box_size.x * 0.65, 0.13, 0.15), Vector3(0, box_size.y * 0.7, 0), _light, _pivot)
	var area := Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	_geometry.add_child(area)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_radius
	shape.shape = sphere
	area.add_child(shape)
	_signature = _design_values()
	_refresh_visual()

func _box(label: String, dimensions: Vector3, offset: Vector3, material: Material, parent: Node3D) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.position = offset
	visual.material_override = material
	if use_metric_grid:
		visual.material_override = _grid_light if material == _light else _grid_casing
	parent.add_child(visual)

func _refresh_visual() -> void:
	if not is_instance_valid(_pivot): return
	_pivot.rotation_degrees.x = -35.0 if powered else 35.0
	_light.albedo_color = color_active if powered else color_idle.lightened(0.22)
	_light.emission = color_active
	_light.emission_energy_multiplier = 0.6 if powered else 0.0
	METRIC_GRID.update_state(_grid_light, _light.albedo_color, color_active, _light.emission_energy_multiplier)

func tl_capture() -> Dictionary:
	return {"powered": powered, "remaining": remaining, "used": used, "serial": interaction_serial}

func tl_restore(state: Dictionary) -> void:
	powered = bool(state.get("powered", false))
	remaining = float(state.get("remaining", 0.0))
	used = bool(state.get("used", false))
	interaction_serial = int(state.get("serial", 0))
	_refresh_visual()
	# Restore is silent: no interactions, energy spending or event re-entry.
