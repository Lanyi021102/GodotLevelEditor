@tool
extends Resource
## Instance-only authoring data; definitions and source scenes are never modified.
const META := &"godot_level_editor_entity"
const BINDING := &"EntityProperties"
@export var version := 1
@export_enum("npc", "mechanism", "room") var kind := "npc"
@export_enum("level", "task") var lifetime := "level"
@export var task_id := ""
@export var model_id := "default"
@export var model_scene: PackedScene
@export_enum("friendly", "hostile") var faction := "friendly"
@export var default_action := "idle"
@export var behavior_definition: Resource
@export_range(0.1, 10.0, 0.1) var body_height := 1.7
@export_range(0.1, 5.0, 0.05) var body_radius := 0.3
@export var initially_enabled := true

func signature() -> Array:
	return [model_id, model_scene, faction, default_action, body_height, body_radius, behavior_definition]

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if version != 1: errors.append("对象属性版本不受支持")
	if lifetime == "task" and task_id.is_empty(): errors.append("请选择所属任务")
	if body_height < body_radius * 2: errors.append("胶囊高度不能小于直径")
	return errors
