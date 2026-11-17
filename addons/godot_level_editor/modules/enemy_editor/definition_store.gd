@tool
extends RefCounted
## Save through a sibling file; refuse invalid data and external file conflicts.
static func load_definition(path: String) -> EnemyDefinition:
	if not path.begins_with("res://") or not path.ends_with(".tres"):
		return null
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return resource.duplicate(true) as EnemyDefinition if resource is EnemyDefinition else null

static func is_builtin(path: String) -> bool:
	return path.simplify_path().to_lower().begins_with("res://addons/")

## allow_builtin is reserved for the explicit developer sample rebuild tool.
static func save_definition(definition: EnemyDefinition, path: String, expected_hash := "", allow_builtin := false) -> Error:
	if definition == null or not definition.validate().is_empty():
		return ERR_INVALID_DATA
	if not path.begins_with("res://") or not path.ends_with(".tres"):
		return ERR_FILE_BAD_PATH
	path = path.simplify_path()
	if is_builtin(path) and not allow_builtin: return ERR_UNAUTHORIZED
	if not expected_hash.is_empty() and FileAccess.get_sha256(path) != expected_hash:
		return ERR_BUSY
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if directory_error != OK: return directory_error
	var previous_uid := ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID
	var temporary := path.get_base_dir().path_join("." + path.get_file().get_basename() + ".enemy_tmp.tres")
	var error := ResourceSaver.save(definition.duplicate(true), temporary)
	if error != OK:
		return error
	var temporary_uid := ResourceLoader.get_resource_uid(temporary)
	var final_uid := previous_uid if previous_uid != ResourceUID.INVALID_ID else temporary_uid
	if final_uid == ResourceUID.INVALID_ID: final_uid = ResourceUID.create_id()
	if final_uid != temporary_uid:
		error = ResourceSaver.set_uid(temporary, final_uid)
		if error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return error
	# Atomic rename must also move Godot's UID registration, or a saved scene can
	# resolve its external definition back to the now-missing temporary filename.
	if temporary_uid != final_uid and ResourceUID.has_id(temporary_uid) and ResourceUID.get_id_path(temporary_uid) == temporary:
		ResourceUID.remove_id(temporary_uid)
	if ResourceUID.has_id(final_uid): ResourceUID.set_id(final_uid, path)
	else: ResourceUID.add_id(final_uid, path)
	# Packed scenes and native Inspectors can retain the canonical resource loaded
	# before this atomic write. Refresh it in place, otherwise a later native Save
	# can serialize that stale instance over the newly saved definition.
	ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return OK
