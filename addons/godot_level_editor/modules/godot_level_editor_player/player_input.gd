extends RefCounted
const PRESET := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/preset.gd")

var actions: Dictionary = {}
var toggles: Dictionary = {}

func setup(profile: Resource, config: Dictionary, owner_id: int) -> void:
	for id: String in PRESET.ACTIONS:
		var name := StringName("gle_3c_%d_%s" % [owner_id, id])
		actions[id] = name
		InputMap.add_action(name, config.move_deadzone if id in ["forward", "back", "left", "right"] else 0.2)
		for event in events_for(profile, id):
			InputMap.action_add_event(name, event)

static func events_for(profile: Resource, id: String) -> Array[InputEvent]:
	var spec: Array = PRESET.ACTIONS[id]
	var result: Array[InputEvent] = []
	if not str(spec[1]).is_empty() and InputMap.has_action(spec[1]):
		result.assign(InputMap.action_get_events(spec[1]))
	var binds: Dictionary = profile.bindings.get(id, {})
	if binds.has("key"):
		result = result.filter(func(event: InputEvent): return not event is InputEventKey)
	if not result.any(func(event: InputEvent): return event is InputEventKey):
		var key := InputEventKey.new()
		key.physical_keycode = int(binds.get("key", spec[2]))
		if key.physical_keycode != 0: result.append(key)
	if id in ["forward", "back", "left", "right"]:
		var axis := InputEventJoypadMotion.new()
		axis.axis = JOY_AXIS_LEFT_X if id in ["left", "right"] else JOY_AXIS_LEFT_Y
		axis.axis_value = -1.0 if id in ["forward", "left"] else 1.0
		if not result.any(func(event: InputEvent): return event is InputEventJoypadMotion): result.append(axis)
	elif binds.has("joy") or not result.any(func(event: InputEvent): return event is InputEventJoypadButton):
		if binds.has("joy"): result = result.filter(func(event: InputEvent): return not event is InputEventJoypadButton)
		var index := int(binds.get("joy", spec[3]))
		if index >= 0:
			var joy := InputEventJoypadButton.new()
			joy.button_index = index
			result.append(joy)
	if id == "focus":
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_RIGHT
		result.append(mouse)
	if id == "recenter":
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_MIDDLE
		result.append(mouse)
	return result

func dispose() -> void:
	for action: StringName in actions.values():
		InputMap.erase_action(action)
	actions.clear()

func movement(deadzone: float) -> Vector2:
	return Input.get_vector(actions.left, actions.right, actions.forward, actions.back, deadzone)

func stick_is_full() -> bool:
	for device in Input.get_connected_joypads():
		var stick := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		if stick.length() >= 0.97: return true
	return false

func just(id: String) -> bool:
	return Input.is_action_just_pressed(actions[id])

func pressed(id: String) -> bool:
	return Input.is_action_pressed(actions[id])

func active(id: String, mode: int) -> bool:
	if mode == 0: return pressed(id)
	if just(id): toggles[id] = not toggles.get(id, false)
	return toggles.get(id, false)

func clear_motion_toggles() -> void:
	for id in ["run", "sprint", "crouch"]:
		toggles.erase(id)
