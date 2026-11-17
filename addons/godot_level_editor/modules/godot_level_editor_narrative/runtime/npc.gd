@tool
extends Node3D
const VISUAL := preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd")
const DEFAULT_MODEL := preload("res://addons/godot_level_editor/resources/enemies/samples_v1/human_medium_male.tres")
signal interacted(npc_id: String, actor: Node3D)
@export var object_id := "receptionist"
@export var display_name := "接待员"
@export var interaction_radius := 2.6
var interaction_allowed := false:
	set(value):
		interaction_allowed = value
		if not value and is_instance_valid(prompt): prompt.text = display_name
var prompt: Label3D

func _ready() -> void:
	if not Engine.is_editor_hint(): add_to_group("godot_level_editor_interactable")
	# Retain existing dialogue IDs and interaction while replacing the old capsule.
	var model := VISUAL.new()
	model.name = "ModelRoot"
	model.npc_definition = DEFAULT_MODEL
	add_child(model)
	model.play("idle")
	prompt = Label3D.new()
	prompt.position.y = 2.1
	prompt.font_size = 42
	prompt.pixel_size = 0.007
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(prompt)
	prompt.text = display_name

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	var actor := get_tree().get_first_node_in_group("godot_level_editor_player") as Node3D
	prompt.text = display_name + ("  [F 对话]" if actor != null and can_interact(actor) else "")

func can_interact(actor: Node3D) -> bool:
	return interaction_allowed and is_visible_in_tree() and actor != null and actor.is_in_group("godot_level_editor_player") and not (actor.has_method("is_clone") and actor.is_clone()) and global_position.distance_to(actor.global_position) <= interaction_radius

func interact(actor: Node3D) -> bool:
	if not can_interact(actor): return false
	interacted.emit(object_id, actor)
	return true
