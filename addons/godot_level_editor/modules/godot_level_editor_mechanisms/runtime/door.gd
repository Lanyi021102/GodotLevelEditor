@tool
extends "res://addons/godot_level_editor/scripts/world/power_door.gd"
## Reuses the campaign door's collision, interpolation and source API; pivot stays at floor.
signal power_changed(powered: bool)
@export var object_id := "door"
@export var display_name := "开关门"
@export var initially_open := false
var _command := false
var _graph_driven := false
var _initial_signature := false

func _init() -> void:
	set_meta("mechanism_kind", "door")

func _ready() -> void:
	super._ready()
	reset_state()

func _process(delta: float) -> void:
	super._process(delta)
	if Engine.is_editor_hint() and _initial_signature != initially_open: reset_state()

func reset_state() -> void:
	_initial_signature = initially_open
	_command = initially_open
	_graph_driven = false
	_powered = initially_open
	open_ratio = 1.0 if initially_open else 0.0
	_apply_offset()

func set_graph_powered(value: bool) -> void:
	_command = value
	_graph_driven = true

func _any_powered() -> bool:
	return _command if _graph_driven else (super._any_powered() if not power_nodes.is_empty() or not source_paths.is_empty() else initially_open)

func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint(): advance(delta)

func advance(delta: float) -> void:
	var previous := _powered
	_powered = _any_powered()
	open_ratio = move_toward(open_ratio, 1.0 if _powered else 0.0, delta / maxf(slide_time, 0.01))
	_apply_offset()
	if previous != _powered: power_changed.emit(_powered)

func _apply_offset() -> void:
	# Move geometry and collision together; assembly placement and graph binding remain stable.
	if is_instance_valid(_panel): _panel.position.y = panel_size.y * 0.5 + open_ratio * open_height
	if is_instance_valid(_shape): _shape.position.y = panel_size.y * 0.5 + open_ratio * open_height
	_refresh_visual()

func tl_capture() -> Dictionary:
	var state := super.tl_capture()
	state["command"] = _command
	state["graph_driven"] = _graph_driven
	return state

func tl_restore(state: Dictionary) -> void:
	_command = bool(state.get("command", false))
	_graph_driven = bool(state.get("graph_driven", false))
	super.tl_restore(state)
