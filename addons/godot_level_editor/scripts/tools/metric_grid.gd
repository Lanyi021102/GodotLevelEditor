@tool
extends RefCounted
## One shared grid definition; tint/state are private to each generated object.
const MATERIAL := preload("res://addons/godot_level_editor/resources/materials/whitebox_metric_grid.tres")

static func material(tint: Color) -> ShaderMaterial:
	var result := MATERIAL.duplicate() as ShaderMaterial
	result.set_shader_parameter("base_color", tint)
	return result

static func update_state(target: ShaderMaterial, tint: Color, emission := Color.BLACK, energy := 0.0) -> void:
	if target == null: return
	target.set_shader_parameter("base_color", tint)
	target.set_shader_parameter("state_emission", emission)
	target.set_shader_parameter("state_energy", energy)
