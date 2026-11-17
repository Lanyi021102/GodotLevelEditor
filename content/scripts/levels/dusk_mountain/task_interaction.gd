@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/interaction_point.gd"
## Content-only interaction adapter. Progression and rewards live in editable task graphs.
@export var required_task := ""

func can_interact(actor: Node3D) -> bool:
	if not super.can_interact(actor): return false
	if required_task.is_empty(): return true
	for director in get_tree().get_nodes_in_group("godot_level_editor_task_directors"):
		if director.get("world") != null and director.world.is_ancestor_of(self):
			return director.task_states.get(required_task) == "active"
	return false
