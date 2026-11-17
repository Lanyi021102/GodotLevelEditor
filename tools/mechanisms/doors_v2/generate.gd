extends Node
const FACTORY := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/factory.gd")
const DEFINITION := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/graph/definition.gd")
const STORE := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd")

static func fixture(kind: String) -> Node3D:
	var root := FACTORY.Assembly.new(); root.name = kind.to_pascal_case(); root.object_id = kind; root.instance_id = "door_v2_" + kind
	var door := FACTORY.component(kind, "door"); door.name = "Door"; root.add_child(door); door.owner = root; root.primary_component = NodePath("Door")
	var graph := DEFINITION.new(); graph.definition_id = "door_v2_" + kind; graph.display_name = "2×3 单开门" if kind == "single_door" else "4×3 双开门"
	preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/door_blueprint.gd").append_nodes(graph, kind, "door", Vector2(40, 20), true)
	root.definition = graph
	return root

func _ready() -> void:
	var failed := false
	for kind in ["single_door", "double_door"]:
		var path := "res://addons/godot_level_editor/scenes/mechanisms/" + str(kind) + ".tscn"
		if FileAccess.file_exists(path) and "--regenerate-owned-door-assets" not in OS.get_cmdline_user_args(): print("保留已有素材：", path); continue
		var root := fixture(kind)
		var result := STORE.save_pair(root, path); root.free()
		if not result.ok: push_error(str(result.errors)); failed = true
		else: print("已生成 ", path)
	get_tree().quit(1 if failed else 0)
