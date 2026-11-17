@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor/graph_panel.gd"
const LOGIC := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_logic_graph.gd")
const TASK_PICKER := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/task_picker.gd")
var _saving := false

func _ready() -> void:
	super._ready()
	mode.hide()
	get_child(0).get_child(0).hide()
	canvas.zoom_min = 0.25
	_button(get_child(0), "适合画布", fit_graph)

func fit_graph() -> void:
	if graph == null or graph.nodes.is_empty(): return
	await get_tree().process_frame
	var bounds := Rect2()
	var first := true
	for card in canvas.get_children():
		if not card is GraphNode: continue
		var rect := Rect2(card.position_offset, card.size)
		bounds = rect if first else bounds.merge(rect); first = false
	if first: return
	canvas.zoom = clampf(minf((canvas.size.x - 80) / bounds.size.x, (canvas.size.y - 120) / bounds.size.y), canvas.zoom_min, 1.0)
	canvas.scroll_offset = bounds.position * canvas.zoom - Vector2(40, 80)

func bind_world(source: Node, create := true) -> void:
	if source == world and graph != null and is_instance_valid(source) and graph == source.level_logic: return
	world = source
	graph = null
	undo.clear_history(); dirty = false; selected_id = ""
	if is_instance_valid(world):
		if world.level_logic == null and create:
			world.level_logic = LOGIC.new()
			world.level_logic.graph_id = world.world_id + "_level_logic"
			EditorInterface.mark_scene_as_unsaved()
		if world.level_logic != null: open_graph(world.level_logic)
	_rebuild()

func use_current_world() -> void:
	var root := EditorInterface.get_edited_scene_root()
	bind_world(root if root != null and root.get_script() == WORLD else root.get_node_or_null("World") if root != null else null)

func _switch_graph() -> void: pass

func _can_offer_node(kind: String) -> bool:
	return graph.allowed_kinds().has(kind)

func _node_parameters(kind: String, params: Dictionary) -> Dictionary:
	if kind in ["npc_interact", "dialog_completed"]: params.erase("task")
	if kind == "npc_interact": params.npc = ""
	if kind == "task_accept": params = {"task": ""}
	return params

func _reference_field(key: String, value: String) -> bool:
	if key == "npc":
		var npcs := LOGIC.permanent_npcs(world)
		_option_field("npc", "关卡常驻 NPC", [""] + npcs.keys(), value)
		for i in _fields.npc.item_count:
			var id := str(_fields.npc.get_item_metadata(i))
			if npcs.has(id): _fields.npc.set_item_text(i, str(npcs[id].display_name) + "  (" + id + ")")
		return true
	if key == "task":
		var label := Label.new(); label.text = "备注 · 接受任务"; parameters.add_child(label)
		var field := TASK_PICKER.new(); field.workbook = graph.events_xlsx; field.level_id = world.level_id if is_instance_valid(world) else ""
		parameters.add_child(field); field.select_id(value); _fields.task = field
		return true
	return false

func _show_parameters() -> void:
	if graph != null:
		var selected := graph.node_by_id(selected_id)
		if not selected.is_empty() and preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_nodes.gd").DEFINITIONS.has(selected.kind):
			preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/task_parameters.gd").draw(self, selected)
			return
	super._show_parameters()

func _apply(target: GodotLevelEditorLevelGraph, state: Dictionary) -> void:
	super._apply(target, state)
	EditorInterface.mark_scene_as_unsaved()

func save_graph() -> bool:
	if _saving: return true
	if graph == null or not is_instance_valid(world): return false
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path.is_empty() or root.scene_file_path.begins_with("res://addons/"):
		status.text = "请先使用 Godot“场景 → 另存为”将关卡保存到插件目录外。"
		return false
	var errors := graph.validate()
	errors.append_array(graph.validate_bindings(world))
	if not errors.is_empty(): status.text = "未保存：" + "; ".join(errors); return false
	graph.view_scroll = canvas.scroll_offset; graph.view_zoom = canvas.zoom
	var error := OK
	if graph.resource_path.ends_with(".tres"): error = ResourceSaver.save(graph, graph.resource_path)
	if error == OK:
		_saving = true
		if DisplayServer.get_name() == "headless": EditorInterface.save_scene_as(root.scene_file_path, false)
		else: error = EditorInterface.save_scene()
		_saving = false
	if error != OK: status.text = "保存失败：" + error_string(error); return false
	dirty = false
	status.text = "已保存关卡图"
	return true

func save_external() -> void:
	# Godot is already saving the scene when it calls the plugin hook.
	if graph == null or not is_instance_valid(world): return
	var errors := graph.validate()
	errors.append_array(graph.validate_bindings(world))
	if not errors.is_empty(): status.text = "关卡图校验失败：" + "; ".join(errors); return
	graph.view_scroll = canvas.scroll_offset; graph.view_zoom = canvas.zoom
	if graph.resource_path.ends_with(".tres") and ResourceSaver.save(graph, graph.resource_path) != OK: return
	dirty = false

func save_reload() -> void:
	if not save_graph(): return
	var root := EditorInterface.get_edited_scene_root()
	var saved: Node = ResourceLoader.load(root.scene_file_path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var saved_world: Node = saved if saved.get_script() == WORLD else saved.get_node_or_null("World")
	if saved_world == null or saved_world.level_logic == null: status.text = "关卡图重载失败"
	else: graph.apply_snapshot(saved_world.level_logic.snapshot()); _rebuild(); status.text = "关卡图已保存并重载"
	saved.free()
