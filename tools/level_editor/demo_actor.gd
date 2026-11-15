extends CharacterBody3D
## Isolated tool demonstration only; does not replace the shared player controller.
@export var input_enabled := true
var travel := Vector3.ZERO
var clone_actor := false
func _ready() -> void:
	add_to_group("godot_level_editor_player")
	add_to_group("stealth_target")
func _physics_process(_delta: float) -> void:
	var direction := Vector3(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"), 0, Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")) if input_enabled else travel
	velocity = direction.limit_length(1) * 3.5
	velocity.y = -1
	move_and_slide()
func is_clone() -> bool: return clone_actor
func _unhandled_key_input(event: InputEvent) -> void:
	if not input_enabled or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_R: get_tree().reload_current_scene()
