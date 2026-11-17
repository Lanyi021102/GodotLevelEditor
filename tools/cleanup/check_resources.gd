extends SceneTree
## Read resource headers and deserialize resources without instantiating scenes.
var checked := 0
var missing: Array[Dictionary] = []
var failed := PackedStringArray()
const EXTENSIONS := ["tscn", "tres", "scn", "res"]

func _initialize() -> void:
	call_deferred("_run")

func _walk(folder: String) -> void:
	for file in DirAccess.get_files_at(folder):
		if not EXTENSIONS.has(file.get_extension()): continue
		var path := folder.path_join(file)
		checked += 1
		for dependency in ResourceLoader.get_dependencies(path):
			var target := str(dependency).split("::")[-1]
			if target.begins_with("uid://"):
				var id := ResourceUID.text_to_id(target)
				if ResourceUID.has_id(id): target = ResourceUID.get_id_path(id)
			if target.begins_with("res://") and not FileAccess.file_exists(target):
				missing.append({"source": path, "target": target})
		if ResourceLoader.load(path) == null: failed.append(path)
	for directory in DirAccess.get_directories_at(folder):
		var path := folder.path_join(directory)
		if not directory.begins_with(".") and not FileAccess.file_exists(path.path_join(".gdignore")): _walk(path)

func _run() -> void:
	for folder in ["res://content/scenes", "res://content/resources", "res://addons/godot_level_editor/assets", "res://addons"]: _walk(folder)
	print("PROJECT RESOURCE AUDIT ", JSON.stringify({"checked": checked, "missing": missing, "failed": failed}))
	quit(0 if missing.is_empty() and failed.is_empty() else 1)
