@tool
extends RefCounted
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")

static func world_for(root: Node) -> Node3D:
	if root == null: return null
	if root.get_script() == WORLD: return root
	var world := root.get_node_or_null("World")
	return world if world != null and world.get_script() == WORLD else null

static func editable_root(root: Node) -> bool:
	return is_instance_valid(world_for(root)) and not root.scene_file_path.is_empty() and not root.scene_file_path.begins_with("res://addons/")

static func apply(history: EditorUndoRedoManager, root: Node, preset: Resource) -> bool:
	if not editable_root(root): return false
	var world := world_for(root)
	if world.player_preset == preset: return true
	history.create_action("设置玩家预设", UndoRedo.MERGE_DISABLE, root)
	history.add_do_property(world, &"player_preset", preset)
	history.add_undo_property(world, &"player_preset", world.player_preset)
	history.commit_action()
	return true
