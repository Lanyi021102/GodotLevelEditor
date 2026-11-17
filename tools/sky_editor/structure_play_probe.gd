extends Node
## Only attached to the disposable inherited QA map, never shipped content.
func _ready() -> void:
	for i in 40: await get_tree().physics_frame
	var world := get_parent()
	var runtime: Node = world.sky_runtime
	var session := get_tree().get_first_node_in_group("main")
	var data := {
		"scene": world.scene_file_path,
		"binding": world.sky_preset.resource_path if world.sky_preset != null else "",
		"active": runtime.active_preset.display_name if runtime != null and runtime.active_preset != null else "",
		"hdri": runtime.environment.sky.sky_material is PanoramaSkyMaterial if runtime != null and runtime.environment != null else false,
		"valid": world.runtime_valid,
		"player": session != null and session.player != null,
	}
	FileAccess.open("user://sky-structure-play.json", FileAccess.WRITE).store_string(JSON.stringify(data))
	print("SKY_STRUCTURE_PLAY ", JSON.stringify(data))
