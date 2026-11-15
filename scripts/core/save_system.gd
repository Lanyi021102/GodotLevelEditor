extends Node
## 存档（Autoload: SaveSystem）
##
## 保存用户配置的世界与任务持续进度；旧存档的 abilities 字段忽略。

signal saved(data: Dictionary)
signal loaded(data: Dictionary)

const PATH := "user://godot_level_editor_world_progress.json"
const VERSION := 2
var storage_path := PATH


func has_save() -> bool:
	return FileAccess.file_exists(storage_path)


func save_path() -> String:
	return ProjectSettings.globalize_path(storage_path)


## 汇总当前进度并写盘
func save_game() -> Dictionary:
	var data := collect_state()
	var f := FileAccess.open(storage_path, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败：%s" % storage_path)
		return {}
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	saved.emit(data)
	return data


func collect_state() -> Dictionary:
	var progress := {}
	for node in get_tree().get_nodes_in_group("main"):
		if node.has_method("save_payload"):
			progress = node.save_payload()
	return {
		"version": VERSION,
		"progress": progress,
	}


func load_game() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(storage_path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("存档解析失败：%s" % storage_path)
		return {}
	var data: Dictionary = parsed
	apply_state(data)
	loaded.emit(data)
	return data


func apply_state(data: Dictionary) -> void:
	var progress: Variant = data.get("progress", {})
	if progress is Dictionary:
		for node in get_tree().get_nodes_in_group("main"):
			if node.has_method("apply_progress"):
				node.apply_progress(progress)


## 清档（测试/新游戏用）
func reset() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(storage_path))
