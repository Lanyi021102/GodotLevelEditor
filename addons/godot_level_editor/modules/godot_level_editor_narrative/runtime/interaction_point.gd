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
	prompt = preload("res://addons/godot_level_editor/scripts/ui/interaction_label.gd").new()
	prompt.configure(self, display_name, "[F]")
	prompt.position.y = 1.4
	add_child(prompt)

func can_interact(actor: Node3D) -> bool:
	return enabled and is_visible_in_tree() and actor != null and actor.is_in_group("godot_level_editor_player") and global_position.distance_to(actor.global_position) <= interaction_radius

func interact(actor: Node3D) -> bool:
	if not can_interact(actor): return false
	interacted.emit(object_id, "interact", actor)
	return true

func tl_capture() -> Dictionary: return {"enabled": enabled}
func tl_restore(data: Dictionary) -> void: enabled = bool(data.get("enabled", true))
