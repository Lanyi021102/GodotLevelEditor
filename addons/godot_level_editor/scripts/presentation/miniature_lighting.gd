@tool
extends Node3D
## Only adjusts the V2 environment's depth of field; camera controls stay unchanged.
@export_range(1.0, 12.0, 0.1) var sharp_near_margin := 4.5
@export_range(1.0, 12.0, 0.1) var sharp_far_margin := 5.5
@export var runtime_depth_of_field := true
@export var runtime_camera_attributes: CameraAttributesPractical
@onready var attributes: CameraAttributesPractical = runtime_camera_attributes

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10
	# Keep cached editor instances sharp too, without changing their camera.
	if Engine.is_editor_hint():
		_disable_editor_blur()
		return
	# Blur is enabled only on the private resource of a running game instance.
	$WorldEnvironment.camera_attributes = attributes
	attributes.dof_blur_near_enabled = runtime_depth_of_field
	attributes.dof_blur_far_enabled = runtime_depth_of_field
	_update_focus()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_disable_editor_blur()
		return
	_update_focus()

func _disable_editor_blur() -> void:
	var world_environment: WorldEnvironment = get_node_or_null("WorldEnvironment")
	if world_environment == null: return
	if world_environment.camera_attributes != null:
		world_environment.camera_attributes = null

func _update_focus() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or attributes == null: return
	# Miniature blur suits an overview; close gameplay cameras must keep distant clues readable.
	var blur := runtime_depth_of_field and camera.projection != Camera3D.PROJECTION_PERSPECTIVE
	if attributes.dof_blur_near_enabled != blur:
		attributes.dof_blur_near_enabled = blur
	if attributes.dof_blur_far_enabled != blur:
		attributes.dof_blur_far_enabled = blur
	var rig := camera.get_parent().get_parent()
	var focus: Vector3
	if rig is Node3D and rig.has_method("get_yaw_radians"):
		# Follow the same smoothed pivot used by the camera, even while time is paused.
		focus = rig.global_position - Vector3.UP * 0.3
	else:
		var direction := -camera.global_basis.z
		if direction.y >= -0.01: return
		focus = camera.global_position + direction * (-camera.global_position.y / direction.y)
	var depth := -camera.to_local(focus).z
	var near_depth := maxf(0.1, depth - sharp_near_margin)
	var far_depth := maxf(1.0, depth + sharp_far_margin)
	if not is_equal_approx(attributes.dof_blur_near_distance, near_depth):
		attributes.dof_blur_near_distance = near_depth
	if not is_equal_approx(attributes.dof_blur_far_distance, far_depth):
		attributes.dof_blur_far_distance = far_depth
