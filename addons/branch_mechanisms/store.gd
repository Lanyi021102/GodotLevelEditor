@tool
extends RefCounted
const Assembly := preload("res://addons/branch_mechanisms/runtime/assembly.gd")
const Definition := preload("res://addons/branch_mechanisms/graph/definition.gd")

static func validate(root: Node) -> PackedStringArray:
	if not root is Assembly: return PackedStringArray(["请选择独立机关组合场景根节点"])
	var errors: PackedStringArray = root.configure().duplicate()
	for object in root.bindings.values():
		if object.has_method("set_graph_powered"):
			if object.panel_size.x <= 0 or object.panel_size.y <= 0 or object.panel_size.z <= 0 or object.open_height < 0 or object.slide_time <= 0:
				errors.append("门尺寸、升起距离或滑动时间无效")
			if not object.source_paths.is_empty() or not object.power_nodes.is_empty(): errors.append("图内门使用门目标节点供电，请移除旧 source_paths/power_nodes")
		if object.get_meta("mechanism_kind", "") == "lever":
			if object.box_size.x <= 0 or object.box_size.y <= 0 or object.box_size.z <= 0 or object.interaction_radius <= 0 or object.reset_delay <= 0:
				errors.append("拉杆尺寸、交互半径或复位时间无效")
		if object.get_meta("mechanism_kind", "") == "plate" and (object.plate_size.x <= 0 or object.plate_size.y <= 0 or object.release_delay < 0): errors.append("压力板尺寸或延时无效")
	return errors

static func save_pair(root: Node, path: String) -> Dictionary:
	var errors := validate(root)
	if not errors.is_empty(): return {"ok": false, "errors": errors}
	if not (path.begins_with("res://") or path.begins_with("user://")) or path.get_extension() != "tscn":
		return {"ok": false, "errors": ["请选择项目内 .tscn 路径"]}
	var graph_path := path.get_basename() + ".graph.tres"
	var files := [graph_path, path]
	var existed := {}
	# Final paths keep editor resource UIDs correct; both files have rollback backups.
	for file in files:
		existed[file] = FileAccess.file_exists(file)
		if existed[file]:
			var copied := DirAccess.copy_absolute(file, file + ".mechanism-backup")
			if copied != OK:
				for cleanup in files: _remove(cleanup + ".mechanism-backup")
				return {"ok": false, "errors": ["无法备份已有文件：" + file]}
	var original: Resource = root.definition
	var graph: Resource = original.duplicate(true)
	graph.take_over_path(graph_path)
	var result := ResourceSaver.save(graph, graph_path)
	if result == OK:
		root.definition = graph
		var packed := PackedScene.new()
		result = packed.pack(root)
		if result == OK: result = ResourceSaver.save(packed, path)
	if result != OK:
		root.definition = original
		original.take_over_path(graph_path)
		for file in files:
			if existed[file]: DirAccess.copy_absolute(file + ".mechanism-backup", file)
			else: _remove(file)
		for file in files: _remove(file + ".mechanism-backup")
		return {"ok": false, "errors": ["保存失败，已回滚旧文件：" + error_string(result)]}
	for file in files: _remove(file + ".mechanism-backup")
	return {"ok": true, "scene": path, "graph": graph_path}

static func load_pair(path: String) -> Node3D:
	if not FileAccess.file_exists(path): return null
	var packed: Variant = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not packed is PackedScene: return null
	var root: Node = packed.instantiate()
	if not root is Assembly or not validate(root).is_empty():
		root.free()
		return null
	return root

static func _remove(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
