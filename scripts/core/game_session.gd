extends Node3D
## 白盒试玩会话：角色、镜头和掉落复位，不包含特殊能力。
@onready var camera_rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD
var player: CharacterBody3D

func _ready() -> void:
	add_to_group("main")
	player = $Player
	player.camera_rig = camera_rig
	player.get_node("ModelRoot").use_textured_body()
	camera_rig.target = player
	camera_rig.snap_to_target()
	camera_rig.arm.add_excluded_object(player.get_rid())

func _physics_process(_delta: float) -> void:
	if player.global_position.y < -8:
		_reset_room()

func _reset_room() -> void:
	player.reset_to_spawn()
	camera_rig.snap_to_target()
