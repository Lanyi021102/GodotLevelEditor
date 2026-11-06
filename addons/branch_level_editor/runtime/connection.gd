@tool
extends Node3D
signal crossed(actor: Node3D)
@export var object_id := "port"
@export_range(1.0, 12.0) var width := 4.0:
	set(value):
		width = clampf(value, 1.0, 12.0)
		if is_inside_tree() and Engine.is_editor_hint(): _refresh_width.call_deferred()
var unlocked := false
var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _area: Area3D
var _previous: Dictionary = {}

func _enter_tree() -> void:
	if object_id.is_empty(): object_id = "region_" + Crypto.new().generate_random_bytes(10).hex_encode()

func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var trigger := BoxShape3D.new()
	trigger.size = Vector3(width, 2.4, 2)
	cs.shape = trigger
	cs.position.y = 1.2
	_area.add_child(cs)
	add_child(_area)
	var body := StaticBody3D.new()
	_shape = CollisionShape3D.new()
	var barrier := BoxShape3D.new()
	barrier.size = Vector3(width, 2.5, 0.28)
	_shape.shape = barrier
	_shape.position.y = 1.25
	body.add_child(_shape)
	add_child(body)
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = barrier.size if not Engine.is_editor_hint() else Vector3(width, 0.08, 0.5)
	_mesh.mesh = box
	_mesh.position.y = 1.25 if not Engine.is_editor_hint() else 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("4c8896")
	_mesh.material_override = mat
	add_child(_mesh)
	if Engine.is_editor_hint():
		_shape.disabled = true
		var label := Label3D.new()
		label.text = object_id + "   空间接口 →"
		label.position = Vector3(0, 1, 0)
		add_child(label)
	else:
		set_unlocked(false)

func _refresh_width() -> void:
	if _shape != null: _shape.shape.size.x = width
	if _mesh != null: _mesh.mesh.size.x = width
	if _area != null and _area.get_child_count() > 0: _area.get_child(0).shape.size.x = width

func set_unlocked(value: bool) -> void:
	unlocked = value
	if _shape != null:
		_shape.set_deferred("disabled", value)
	if _mesh != null and not Engine.is_editor_hint():
		_mesh.visible = not value

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _area == null:
		return
	var present := {}
	for body in _area.get_overlapping_bodies():
		if not body.is_in_group("branch_player") or (body.has_method("is_clone") and body.call("is_clone")):
			continue
		var key: int = body.get_instance_id()
		var z: float = to_local(body.global_position).z
		if unlocked and _previous.has(key) and float(_previous[key]) >= 0 and z < 0:
			crossed.emit(body)
		present[key] = z
	_previous = present
