@tool
extends Node3D
signal interacted(object_id: String, action: String, actor: Node3D)
@export var object_id := "interaction_point"
@export var display_name := "交互点"
@export var interaction_radius := 2.5
@export var enabled := true
var prompt: Label3D

func _ready() -> void:
	if Engine.is_editor_hint(): return
	add_to_group("godot_level_editor_interactable")
	prompt = Label3D.new()
	prompt.position.y = 1.4
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.font_size = 32
	add_child(prompt)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	var actor := get_tree().get_first_node_in_group("godot_level_editor_player") as Node3D
	prompt.text = display_name + (" [F]" if can_interact(actor) else "")

func can_interact(actor: Node3D) -> bool:
	return enabled and is_visible_in_tree() and actor != null and actor.is_in_group("godot_level_editor_player") and global_position.distance_to(actor.global_position) <= interaction_radius

func interact(actor: Node3D) -> bool:
	if not can_interact(actor): return false
	interacted.emit(object_id, "interact", actor)
	return true

func tl_capture() -> Dictionary: return {"enabled": enabled}
func tl_restore(data: Dictionary) -> void: enabled = bool(data.get("enabled", true))
