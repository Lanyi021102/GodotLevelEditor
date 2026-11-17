extends Node
const COMPONENT := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/runtime/stateful_component.gd")
var checks := 0
var failures := 0

func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", title)

func fixture(kind: String) -> Node3D:
	var item := COMPONENT.new()
	item.component_type = kind
	item.initial_state = "ready" if kind == "terminal" else ""
	add_child(item)
	item.set_physics_process(false)
	return item

func _ready() -> void:
	for kind in COMPONENT.KINDS:
		if kind == "pressure_plate": continue # Sensor-driven states have no authored action transitions.
		var item := fixture(kind)
		var initial: String = item.get_state()
		item.custom_states = PackedStringArray(["broken", "fixed"])
		item.transition_rules.assign([{"from": "broken", "action": "repair", "to": "fixed"}])
		var completed: Array = []
		item.action_finished.connect(func(action: String, ok: bool): completed.append([action, ok]))
		check(item.validate_component().is_empty(), kind + " accepts a valid custom action rule")
		var result: Dictionary = item.perform_action("repair")
		check(result.has("ok") and not result.ok and not str(result.get("reason", "")).is_empty() and item.get_state() == initial and completed.is_empty(), kind + " rejects unavailable custom action without state change, success signal or script exception")
		item.initial_state = "broken"; item.reset_state()
		check(item.perform_action("repair").ok and item.get_state() == "fixed" and completed == [["repair", true]], kind + " still executes an available custom action")
		item.free()
	var actor := CharacterBody3D.new()
	actor.add_to_group("godot_level_editor_player"); add_child(actor)
	var button := fixture("button")
	button.reset_after = 2.0
	button.transition_rules.assign([{"from": "idle", "action": "interact", "to": "pressed"}])
	check(button.validate_component().is_empty() and button.interact(actor), "custom button interaction enters pressed")
	button.advance(1.0 / 60.0)
	check(button.get_state() == "pressed", "custom pressed survives the first physics frame")
	button.advance(1.88)
	check(button.get_state() == "pressed", "custom pressed retains the configured two-second duration")
	var saved: Dictionary = button.tl_capture()
	button.advance(0.11)
	check(button.get_state() == "idle", "custom pressed releases after reset_after elapses")
	var transitions: Array = []
	button.state_changed.connect(func(old: String, state: String): transitions.append([old, state]))
	button.tl_restore(saved)
	check(button.get_state() == "pressed" and transitions.is_empty(), "restoring the remaining timer is silent")
	button.advance(0.11)
	check(button.get_state() == "idle" and transitions.size() == 1, "restored custom timer completes at its saved deadline")
	button.transition_rules.clear(); button.reset_state(); button.perform_action("press"); button.advance(1.9)
	check(button.get_state() == "pressed", "built-in press retains the same two-second duration")
	button.advance(0.11)
	check(button.get_state() == "idle", "built-in press still resets normally")
	button.transition_rules.assign([{"from": "idle", "action": "interact", "to": "pressed"}])
	button.reset_after = 0; button.reset_state(); button.interact(actor); button.advance(10)
	check(button.get_state() == "pressed", "zero reset_after keeps a custom pressed state until explicitly released")
	print("MECHANISM QA RUNTIME: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
