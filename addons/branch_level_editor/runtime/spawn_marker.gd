@tool
extends Marker3D
@export var object_id := ""
@export_enum("player", "enemy", "checkpoint") var role := "player"
func _enter_tree() -> void:
	if object_id.is_empty(): object_id = "spawn_" + Crypto.new().generate_random_bytes(10).hex_encode()
func _ready() -> void:
	if not Engine.is_editor_hint(): return
	var label := Label3D.new()
	label.text = {"player": "玩家出生点", "enemy": "敌人出生点", "checkpoint": "检查点"}.get(role, "出生点")
	label.position.y = 1
	label.font_size = 40
	add_child(label)
