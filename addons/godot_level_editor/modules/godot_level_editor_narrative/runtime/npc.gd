@tool
class_name GLEDialogueNPC
extends Node3D
const LABEL := preload("res://addons/godot_level_editor/scripts/ui/interaction_label.gd")
const VISUAL := preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd")
const DEFAULT_MODEL := preload("res://addons/godot_level_editor/resources/enemies/samples_v1/human_medium_male.tres")
signal interacted(npc_id: String, actor: Node3D)
@export var object_id := "receptionist"
@export var display_name := "接待员"
@export var interaction_radius := 2.6
var interaction_allowed := false
var prompt: Label3D

func _ready() -> void:
	if not Engine.is_editor_hint(): add_to_group("godot_level_editor_interactable")
	# Retain existing dialogue IDs and interaction while replacing the old capsule.
	var model := VISUAL.new()
	model.name = "ModelRoot"
	model.npc_definition = DEFAULT_MODEL
	add_child(model)
	model.play("idle")
	prompt = LABEL.new()
	prompt.configure(self, display_name, "[F 对话]")
	prompt.position.y = 2.1
	add_child(prompt)

static func supports(node: Node) -> bool:
	return node is GLEDialogueNPC or (node.get("allow_conversation") == true and node.get("enemy_instance_id") is String)

static func speaker_id(node: Node) -> String:
	return str(node.object_id) if node is GLEDialogueNPC else str(node.enemy_instance_id)

static func speaker_name(node: Node) -> String:
	return str(node.display_name) if node is GLEDialogueNPC else str(node.name)

static func actor_in_reach(npc: Node3D, actor: Node3D, radius: float) -> bool:
	return npc.is_visible_in_tree() and npc.can_process() and actor != null and actor.is_in_group("godot_level_editor_player") and not (actor.has_method("is_clone") and actor.is_clone()) and npc.global_position.distance_squared_to(actor.global_position) <= radius * radius

func can_interact(actor: Node3D) -> bool:
	return interaction_allowed and actor_in_reach(self, actor, interaction_radius)

func interact(actor: Node3D) -> bool:
	if not can_interact(actor): return false
	interacted.emit(object_id, actor)
	return true
