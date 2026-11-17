@tool
extends RefCounted
## Plain organizational nodes are transparent to object/Room scopes.
const META := &"godot_level_editor_content_group"
const NAMES := {"whitebox": "Whitebox", "room": "Rooms", "mechanism": "Mechanisms", "npc": "NPCs"}
const CATEGORIES := {"Layout 白盒": "whitebox", "常驻 Room": "room", "常驻机关": "mechanism", "常驻 NPC": "npc"}

static func is_group(node: Node) -> bool:
	return node != null and node.get_class() == "Node3D" and node.get_script() == null and NAMES.has(str(node.get_meta(META, "")))

static func contents(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if is_group(child): result.append_array(contents(child))
		else: result.append(child)
	return result

static func kind(node: Node) -> String:
	if node.has_meta("godot_level_editor_entity"):
		var profile: Variant = node.get_meta("godot_level_editor_entity")
		if profile is Resource and NAMES.has(str(profile.get("kind"))): return str(profile.get("kind"))
	var script: Script = node.get_script()
	var path := script.resource_path if script != null else ""
	match path:
		"res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd": return "whitebox"
		"res://addons/godot_level_editor/modules/godot_level_editor/runtime/room.gd": return "room"
		"res://addons/godot_level_editor/modules/godot_level_editor/runtime/placement.gd": return "npc" if node.get("component_kind") == "guard" else "mechanism"
		"res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/npc.gd", "res://addons/godot_level_editor/scripts/stealth/guard_ai.gd": return "npc"
	if path.begins_with("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/runtime/"): return "mechanism"
	var scene := node.scene_file_path
	if scene.begins_with("res://addons/godot_level_editor/scenes/npcs/"): return "npc"
	if scene.begins_with("res://addons/godot_level_editor/scenes/mechanisms/"): return "mechanism"
	if scene.begins_with("res://content/scenes/level_editor/rooms/"): return "room"
	return ""

static func find_group(root: Node, category: String) -> Node3D:
	for child in root.get_children():
		if is_group(child) and str(child.get_meta(META)) == category and child.owner == root: return child
	# A user-created plain organizational node with the same name can be reused.
	var candidate := root.get_node_or_null(NodePath(str(NAMES.get(category, ""))))
	if candidate != null and candidate.get_parent() == root and candidate.get_class() == "Node3D" and candidate.get_script() == null and candidate.owner == root:
		return candidate
	return null

static func new_group(category: String) -> Node3D:
	var group := Node3D.new()
	group.name = NAMES[category]
	group.set_meta(META, category)
	return group

static func group_new_node(root: Node3D, node: Node3D) -> void:
	# For newly generated scenes only, before saving them for the first time.
	var category := kind(node)
	if category.is_empty(): return
	if node.get_parent() != root: return
	var parent := find_group(root, category)
	var local := node.transform
	var owned: Array[Node] = [node]
	for child in node.find_children("*", "Node", true, false):
		if child.owner == root: owned.append(child)
	for child in owned: child.owner = null
	root.remove_child(node)
	if parent == null:
		parent = new_group(category)
		root.add_child(parent, true)
		parent.owner = root
	elif not parent.has_meta(META): parent.set_meta(META, category)
	parent.add_child(node, true)
	node.transform = parent.transform.affine_inverse() * local
	for child in owned: child.owner = root
