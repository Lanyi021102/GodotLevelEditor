@tool
extends Area3D
## A spatial trigger only. All completion logic is in the event graph.
signal player_entered(actor: Node3D)
signal player_exited(actor: Node3D)
@export var tint := Color("b99b5f")
@export var object_id := "goal_region"
@export var extent := Vector3(3, 2, 3):
	set(value):
		extent = value.clamp(Vector3.ONE * 0.1, Vector3.ONE * 100)
		if is_inside_tree() and Engine.is_editor_hint(): _refresh_size.call_deferred()
@export var actor_group: StringName = &"branch_player"

func _enter_tree() -> void:
	if object_id.is_empty(): object_id = "region_" + Crypto.new().generate_random_bytes(10).hex_encode()

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := BoxShape3D.new()
	shape.size = extent
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = extent.y * 0.5
	add_child(cs)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(extent.x, 0.04, extent.z)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mesh.material_override = mat
	mesh.position.y = 0.025
	add_child(mesh)
	if not Engine.is_editor_hint():
		body_entered.connect(_entered)
		body_exited.connect(_exited)

func _refresh_size() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			child.shape.size = extent
			child.position.y = extent.y * 0.5
		elif child is MeshInstance3D:
			child.mesh.size = Vector3(extent.x, 0.04, extent.z)

func controlled_actor() -> Node3D:
	for body in get_overlapping_bodies():
		if body.is_in_group(actor_group) and not (body.has_method("is_clone") and body.call("is_clone")):
			return body
	return null

func _entered(body: Node3D) -> void:
	if body.is_in_group(actor_group) and not (body.has_method("is_clone") and body.call("is_clone")): player_entered.emit(body)

func _exited(body: Node3D) -> void:
	if body.is_in_group(actor_group) and not (body.has_method("is_clone") and body.call("is_clone")): player_exited.emit(body)
