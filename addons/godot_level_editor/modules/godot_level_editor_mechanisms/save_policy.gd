@tool
extends RefCounted
## Shipped resources are replaced on plugin updates. Authoring must not write there.
const PERSONAL_DIRECTORY := "res://content/scenes/mechanisms"
const BUILTIN_MESSAGE := "内置机关由插件管理，请另存到 content/scenes/mechanisms 制作个人版本。"

static func canonical(path: String) -> String:
	return ProjectSettings.localize_path(path).simplify_path()

static func is_plugin_path(path: String) -> bool:
	return canonical(path).to_lower().begins_with("res://addons/")

static func personal_path(source: String) -> String:
	var name_ := source.get_file().get_basename()
	if name_.is_empty(): name_ = "new_mechanism"
	var base := PERSONAL_DIRECTORY.path_join(name_)
	var path := base + ".tscn"
	var suffix := 2
	while FileAccess.file_exists(path) or FileAccess.file_exists(path.get_basename() + ".graph.tres"):
		path = base + "_%d.tscn" % suffix
		suffix += 1
	return path
