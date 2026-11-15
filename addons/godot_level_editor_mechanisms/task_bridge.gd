extends Node
## Connect once per actual component; both task and permanent-level runners can share the broadcast.
const ACCESS := preload("res://addons/godot_level_editor_mechanisms/state_access.gd")
var _links: Array[Dictionary] = []
var _publish: Callable
var _world: Node
var _clock := 0.0
var _known: Dictionary = {}

func bind_world(world: Node, publish: Callable) -> void:
	clear(); _world = world; _publish = publish; _refresh()

func clear() -> void:
	for link in _links:
		if is_instance_valid(link.node) and link.node.is_connected(link.signal, link.callback): link.node.disconnect(link.signal, link.callback)
	_links.clear(); _known.clear()

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 0.25: _clock = 0; _refresh()

func _refresh() -> void:
	if not is_instance_valid(_world): return
	var current := ACCESS.targets(_world)
	if _known == current: return
	clear(); _known = current
	for reference in current:
		var component: Node = current[reference]
		var aliases: Array = [reference]
		var base := str(reference).split(ACCESS.SEPARATOR, true, 1)[0]
		if ACCESS.resolve(_world, base) == component: aliases.append(base)
		_link(component, "state_changed", func(previous: String, state: String): _send("mechanism_state_changed", {"from_state": previous, "to_state": state}, aliases))
		_link(component, "action_finished", func(action: String, success: bool): _send("mechanism_action_finished", {"action": action, "succeeded": success}, aliases))
		_link(component, "interacted", func(_id: String, action: String, actor: Node3D): _send("mechanism_interacted", {"action": action, "is_player": actor != null and actor.is_in_group("godot_level_editor_player")}, aliases))
		_link(component, "region_entered", func(actor: Node3D): _send("mechanism_region_enter", {"is_player": actor != null and actor.is_in_group("godot_level_editor_player")}, aliases))
		_link(component, "region_exited", func(actor: Node3D): _send("mechanism_region_exit", {"is_player": actor != null and actor.is_in_group("godot_level_editor_player")}, aliases))

func _link(node: Node, signal_name: String, callback: Callable) -> void:
	if not node.has_signal(signal_name): return
	node.connect(signal_name, callback); _links.append({"node": node, "signal": signal_name, "callback": callback})

func _send(kind: String, context: Dictionary, references: Array) -> void:
	if not is_instance_valid(_world) or not _publish.is_valid(): return
	context["mechanism"] = references[0]; context["references"] = references
	_publish.call(kind, context)

func _exit_tree() -> void: clear()
