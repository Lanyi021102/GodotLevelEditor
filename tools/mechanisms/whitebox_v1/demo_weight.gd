@tool
extends RigidBody3D
## Only the demonstration's movable weight; interaction still uses the standard F interface.
@export var object_id := "demo_weight"
var _carrier: Node3D
var _caption: Label3D

func _ready() -> void:
	collision_layer = 4; collision_mask = 3; mass = 4.0
	var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(0.8, 0.8, 0.8); mesh.mesh = box
	var material := StandardMaterial3D.new(); material.albedo_color = Color("c7a65c"); mesh.material_override = material; add_child(mesh)
	var shape := CollisionShape3D.new(); var collision := BoxShape3D.new(); collision.size = box.size; shape.shape = collision; add_child(shape)
	_caption = Label3D.new(); _caption.text = "配重箱 [F 拿起 / 放下]"; _caption.position.y = 0.9; _caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED; _caption.pixel_size = 0.003; add_child(_caption)
	if not Engine.is_editor_hint(): add_to_group("godot_level_editor_interactable")

func can_interact(actor: Node3D) -> bool:
	return actor != null and actor.is_in_group("godot_level_editor_player") and actor.global_position.distance_to(global_position) < 2.3

func interact(actor: Node3D) -> bool:
	if not can_interact(actor): return false
	if _carrier != null:
		_carrier = null; freeze = false; collision_layer = 4; linear_velocity = Vector3.ZERO
	else:
		_carrier = actor; freeze = true; collision_layer = 0
	return true

func _physics_process(_delta: float) -> void:
	if not Engine.is_editor_hint() and is_instance_valid(_carrier): global_position = _carrier.global_position - _carrier.global_basis.z * 1.2 + Vector3.UP * 0.8
