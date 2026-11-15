extends Node
signal task_started(task_id: String)
signal task_completed(task_id: String)
const RUNNER := preload("res://addons/godot_level_editor/runtime/event_runner.gd")
@export var definition: GodotLevelEditorLevelGraph
var library: Resource
@export var world_path: NodePath
var runner: RefCounted
var dialogue: CanvasLayer
var tasks: Dictionary = {}
var objective := ""
var objective_label: Label
var valid := false
var _npcs: Dictionary = {}
var _debug_clock := 0.0
var _conversation_ui: Dictionary = {}

func _ready() -> void:
	process_physics_priority = 510
	var world := get_node_or_null(world_path)
	if definition == null or world == null: return
	var csv: Dictionary = definition.load_dialogue()
	if not csv.errors.is_empty():
		push_error("任务对白 XLSX 无效：" + "; ".join(csv.errors))
		return
	library = csv.library
	var errors := validate_bindings(world)
	if not errors.is_empty():
		push_error("任务拒绝运行：" + "; ".join(errors))
		return
	runner = RUNNER.new()
	if not runner.configure(definition, world.object_by_id, _action): return
	dialogue = preload("res://addons/godot_level_editor_narrative/runtime/dialogue_player.gd").new()
	dialogue.library = library
	add_child(dialogue)
	dialogue.dialogue_completed.connect(_dialogue_completed)
	var overlay := CanvasLayer.new()
	overlay.layer = 20
	add_child(overlay)
	objective_label = Label.new()
	objective_label.position = Vector2(28, 80)
	objective_label.add_theme_font_size_override("font_size", 22)
	objective_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	objective_label.add_theme_constant_override("shadow_offset_x", 2)
	objective_label.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(objective_label)
	runner.objective_requested.connect(_set_objective)
	for room in world.rooms():
		room.player_entered.connect(func(id: String, _actor: Node3D): runner.queue_trigger("room_enter", {"room": id}))
	for child in _npc_nodes(world):
		if child.get_script() == preload("res://addons/godot_level_editor_narrative/runtime/npc.gd"):
			_npcs[child.object_id] = child
			child.interacted.connect(_npc_interacted)
	dialogue.opened.connect(_hide_conversation_ui)
	dialogue.closed.connect(_restore_conversation_ui)
	valid = true

func validate_bindings(world: Node) -> PackedStringArray:
	var errors: PackedStringArray = definition.validate()
	if not errors.is_empty(): return errors
	for n in definition.nodes:
		if n.kind not in definition.BASE_KINDS: errors.append("新增任务节点请使用当前套件 event_director 执行：" + str(n.kind))
	if not errors.is_empty(): return errors
	var rooms := {}
	for room in world.rooms(): rooms[room.room_id] = true
	var npcs := {}
	for child in _npc_nodes(world):
		if child.get_script() == preload("res://addons/godot_level_editor_narrative/runtime/npc.gd"):
			if npcs.has(child.object_id): errors.append("NPC ID 重复：" + child.object_id)
			npcs[child.object_id] = true
	for n in definition.nodes:
		if n.kind == "room_enter" and not rooms.has(n.params.get("room")): errors.append("房间不存在：" + str(n.params.get("room")))
		if n.kind == "npc_interact" and not npcs.has(n.params.get("npc")): errors.append("NPC 不存在：" + str(n.params.get("npc")))
	return errors

func _physics_process(delta: float) -> void:
	if valid:
		runner.tick()
		_refresh_npcs()
		_debug_clock += delta
		if _debug_clock > 0.15 or get_tree().paused:
			_debug_clock = 0.0
			_send_debug()

func _action(n: Dictionary, _context: Dictionary) -> Dictionary:
	var p: Dictionary = n.params
	var id := str(p.get("task", ""))
	var ok := false
	match str(n.kind):
		"task_start":
			if not tasks.has(id):
				tasks[id] = "active"
				task_started.emit(id)
				ok = true
		"task_complete":
			if tasks.get(id) == "active":
				tasks[id] = "completed"
				task_completed.emit(id)
				ok = true
		"show_dialog": ok = dialogue.show_dialog(str(p.get("dialog_id", "")))
	_refresh_npcs()
	return {"ok": ok, "reason": "已执行" if ok else "任务已执行／未开始，或对话忙碌／引用无效"}

func _npc_interacted(id: String, _actor: Node3D) -> void:
	for task in tasks:
		if tasks[task] == "active": runner.queue_trigger("npc_interact", {"npc": id, "task": task})

func _dialogue_completed(id: String) -> void:
	for task in tasks:
		if tasks[task] == "active": runner.queue_trigger("dialog_completed", {"dialog_id": id, "task": task})

func _refresh_npcs() -> void:
	for id in _npcs:
		var allowed := false
		for n in definition.nodes:
			if not dialogue.is_active() and n.kind == "npc_interact" and n.params.get("npc") == id and tasks.get(n.params.get("task")) == "active":
				allowed = true
		_npcs[id].interaction_allowed = allowed

func _set_objective(text: String) -> void:
	objective = text
	objective_label.text = text

func capture_progress() -> Dictionary:
	return {"version": 1, "graph_id": definition.graph_id, "tasks": tasks.duplicate(), "dialogues": dialogue.completed.duplicate(), "objective": objective}

func restore_progress(data: Dictionary) -> bool:
	if data.get("version") != 1 or data.get("graph_id") != definition.graph_id or not data.get("tasks") is Dictionary or not data.get("dialogues") is Dictionary: return false
	var known := {}
	for n in definition.nodes:
		if n.kind == "task_start": known[n.params.task] = true
	for id in data.tasks:
		if not known.has(id) or not data.tasks[id] in ["active", "completed"]: return false
	var dialog_ids := {}
	for group in library.groups:
		for comment in group.comments:
			dialog_ids[comment.id] = true
			for line in comment.lines: dialog_ids[line.id] = true
	for id in data.dialogues:
		if not dialog_ids.has(id) or typeof(data.dialogues[id]) != TYPE_BOOL or not data.dialogues[id]: return false
	tasks = data.tasks.duplicate()
	dialogue.completed = data.dialogues.duplicate()
	_set_objective(str(data.get("objective", "")))
	_refresh_npcs()
	return true

func _send_debug() -> void:
	if not EngineDebugger.is_active() or runner == null: return
	var world := get_node_or_null(world_path)
	EngineDebugger.send_message("godot_level_editor_narrative:state", [{"instance": str(get_path()), "world_id": world.world_id, "graph_id": definition.graph_id, "topology_id": "", "event_revision": runner.definition.semantic_hash(), "values": runner.values.duplicate(), "persistent": tasks.duplicate(), "local": runner.local_state.duplicate(), "reasons": runner.last_reason.duplicate(), "counts": runner.counts.duplicate()}])

func _exit_tree() -> void:
	if EngineDebugger.is_active(): EngineDebugger.send_message("godot_level_editor_narrative:remove", [str(get_path())])

func _npc_nodes(world: Node) -> Array[Node]:
	var scope := world.get_parent() if world.get_parent() != null else get_parent()
	return scope.find_children("*", "Node3D", true, false)

func _hide_conversation_ui() -> void:
	var elements: Array[Node] = [objective_label]
	for npc in _npcs.values(): elements.append(npc.prompt)
	var world := get_node_or_null(world_path)
	if world != null and world.get_parent() != null:
		var hud := world.get_parent().get_node_or_null("HUD")
		if hud is CanvasLayer or hud is CanvasItem: elements.append(hud)
	for element in elements:
		_conversation_ui[element] = element.visible
		element.visible = false

func _restore_conversation_ui() -> void:
	for element in _conversation_ui:
		if is_instance_valid(element): element.visible = _conversation_ui[element]
	_conversation_ui.clear()
