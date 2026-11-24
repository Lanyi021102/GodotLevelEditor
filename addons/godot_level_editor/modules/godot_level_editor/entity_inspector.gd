@tool
extends EditorInspectorPlugin
const PROFILE := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/entity_profile.gd")
const PANEL := preload("res://addons/godot_level_editor/modules/godot_level_editor/entity_inspector_panel.gd")
var plugin: EditorPlugin

func _can_handle(object: Object) -> bool:
	return object is Node3D and object.has_meta(PROFILE.META) and object.get_meta(PROFILE.META) is Resource and object.get_meta(PROFILE.META).get_script() == PROFILE

func _parse_begin(object: Object) -> void:
	var panel := PANEL.new(); panel.entity = object; panel.plugin = plugin
	add_custom_control(panel)

func _parse_property(_object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_text: String, _usage: int, _wide: bool) -> bool:
	if name == "uses_topology" and _object.get_meta(PROFILE.META).kind == "room": return true
	return name in ["metadata/" + str(PROFILE.META), "allow_conversation", "object_id", "room_id", "instance_id", "display_name", "bounds_size", "keep_active_on_exit", "volume_material", "component_scene", "component_definition"]
