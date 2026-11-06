@tool
extends Node3D
## Delegates runtime occupancy/delay/snapshot semantics to the existing PressurePlate.
@export var object_id := "plate"
@export var display_name := "压力板"
@export var plate_size := Vector2(2.0, 2.0)
@export_range(0.0, 15.0, 0.05) var release_delay := 0.3
@export var color_idle := Color("344b60")
@export var color_active := Color("5ed8c1")
var _plate: Node3D
var _editor_visual: MeshInstance3D
var _signature: Array = []
var _preview_power := false

func _init() -> void:
	set_meta("mechanism_kind", "plate")

func _ready() -> void:
	rebuild_design()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _signature != [plate_size, color_idle, color_active, release_delay]: rebuild_design()

func rebuild_design() -> void:
	if is_instance_valid(_plate): _plate.free()
	if is_instance_valid(_editor_visual): _editor_visual.free()
	if not Engine.is_editor_hint():
		_plate = preload("res://scripts/world/pressure_plate.gd").new()
		_plate.plate_size = plate_size
		_plate.release_delay = release_delay
		_plate.color_idle = color_idle
		_plate.color_active = color_active
		add_child(_plate)
	else:
		_editor_visual = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(plate_size.x, 0.14, plate_size.y)
		_editor_visual.mesh = mesh
		_editor_visual.position.y = 0.07
		add_child(_editor_visual)
		set_preview_powered(_preview_power)
	_signature = [plate_size, color_idle, color_active, release_delay]

func set_preview_powered(value: bool) -> void:
	_preview_power = value
	if is_instance_valid(_editor_visual):
		var material := StandardMaterial3D.new()
		material.albedo_color = color_active if value else color_idle
		_editor_visual.material_override = material

func is_powered() -> bool:
	return _preview_power if Engine.is_editor_hint() else (is_instance_valid(_plate) and _plate.is_powered())

func tl_capture() -> Dictionary:
	return _plate.tl_capture() if is_instance_valid(_plate) else {"powered": _preview_power, "timer": 0.0}

func tl_restore(state: Dictionary) -> void:
	if is_instance_valid(_plate): _plate.tl_restore(state)
	else: set_preview_powered(bool(state.get("powered", false)))
