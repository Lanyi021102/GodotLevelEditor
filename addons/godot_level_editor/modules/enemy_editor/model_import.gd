@tool
extends RefCounted
const FORMATS := ["glb", "gltf", "fbx", "tscn", "scn"]
const TEXTURES := ["png", "jpg", "jpeg", "webp", "tga", "bmp", "dds", "ktx", "ktx2"]

## Prepare local art for Godot's importer. No existing project file is overwritten.
static func prepare(path: String) -> Dictionary:
	var source := ProjectSettings.globalize_path(path).simplify_path()
	var local := ProjectSettings.localize_path(source)
	if source.get_extension().to_lower() not in FORMATS: return {"error": "请选择 GLB、glTF、FBX 或 Godot 三维场景。"}
	if not FileAccess.file_exists(source): return {"error": "找不到所选文件。"}
	if local.begins_with("res://"): return {"path": local}
	if source.get_extension().to_lower() in ["tscn", "scn"]: return {"error": "Godot 场景请先连同依赖放入项目，再选择该文件。"}
	var files := PackedStringArray([source])
	if source.get_extension().to_lower() == "gltf":
		var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		if not json is Dictionary: return {"error": "glTF 文件格式无效。"}
		for list in [json.get("buffers", []), json.get("images", [])]:
			for entry in list:
				var uri := str(entry.get("uri", ""))
				if uri.is_empty() or uri.begins_with("data:"): continue
				uri = uri.uri_decode()
				var dependency := source.get_base_dir().path_join(uri).simplify_path()
				if uri.contains(":") or uri.is_absolute_path() or not dependency.begins_with(source.get_base_dir() + "/"): return {"error": "glTF 依赖必须位于模型所在文件夹内。"}
				if not FileAccess.file_exists(dependency): return {"error": "缺少模型依赖：" + uri}
				if not files.has(dependency): files.append(dependency)
	if source.get_extension().to_lower() == "fbx":
		# Common FBX exports keep textures alongside the file, in textures/, or *.fbm/.
		for file in DirAccess.get_files_at(source.get_base_dir()):
			if file.get_extension().to_lower() in TEXTURES: files.append(source.get_base_dir().path_join(file))
		for folder in DirAccess.get_directories_at(source.get_base_dir()):
			if folder.to_lower() in ["textures", "texture"] or folder.to_lower().ends_with(".fbm"):
				_collect_textures(source.get_base_dir().path_join(folder), files)
	var name := source.get_file().get_basename().validate_filename().replace(" ", "_")
	var folder := "res://addons/godot_level_editor/assets/characters/npc_imports/" + name + "_" + Crypto.new().generate_random_bytes(5).hex_encode()
	var source_folder := folder.path_join("source")
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source_folder))
	if directory_error != OK: return {"error": "无法创建素材目录：" + error_string(directory_error)}
	# Keep the original package without making Godot import it a second time.
	var ignore := FileAccess.open(source_folder.path_join(".gdignore"), FileAccess.WRITE)
	if ignore == null: return {"error": "无法保存素材来源目录。"}
	ignore.close()
	var created := PackedStringArray()
	for file in files:
		var relative := file.trim_prefix(source.get_base_dir() + "/")
		var target := source_folder.path_join(relative)
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
		if error == OK: error = DirAccess.copy_absolute(file, ProjectSettings.globalize_path(target))
		if error != OK:
			for copied in created: DirAccess.remove_absolute(ProjectSettings.globalize_path(copied))
			return {"error": "导入文件失败：" + error_string(error)}
		created.append(target)
	return {"path": source_folder.path_join(source.get_file()), "copied": true}

static func scene_snapshot(path: String, copied := false, original_path := "") -> Dictionary:
	if path.get_extension().to_lower() in ["tscn", "scn"]: return {"path": path}
	var document: GLTFDocument = FBXDocument.new() if path.get_extension().to_lower() == "fbx" else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if path.get_extension().to_lower() == "fbx" else GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	var source := original_path if copied and not original_path.is_empty() else path
	var error := document.append_from_file(source, state)
	if error != OK: return {"error": "模型导入失败：" + error_string(error) + "。请检查模型和贴图依赖。"}
	var root := document.generate_scene(state)
	if root == null: return {"error": "模型未生成有效的三维场景。"}
	root = _materialize(root)
	root.name = path.get_file().get_basename().validate_node_name()
	_own_children(root, root)
	var folder := path.get_base_dir().get_base_dir() if copied else "res://addons/godot_level_editor/assets/characters/npc_imports/" + path.get_file().get_basename().validate_filename() + "_" + Crypto.new().generate_random_bytes(5).hex_encode()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var target := folder.path_join(path.get_file().get_basename() + ".scn")
	var scene := PackedScene.new()
	error = scene.pack(root)
	root.free()
	# Bundle textures and meshes so the new scene is immediately loadable, even
	# while the native editor is still indexing the copied source files.
	if error == OK: error = ResourceSaver.save(scene, target, ResourceSaver.FLAG_BUNDLE_RESOURCES | ResourceSaver.FLAG_COMPRESS)
	if error != OK: return {"error": "模型保存失败：" + error_string(error)}
	return {"path": target}

static func _materialize(node: Node) -> Node:
	# GLTFDocument generates intermediate ImporterMeshInstance3D nodes inside
	# the editor. Convert them before saving a scene for preview or gameplay.
	if node.is_class("ImporterMeshInstance3D"):
		var rendered := MeshInstance3D.new()
		rendered.name = node.name
		rendered.transform = node.get("transform")
		rendered.visible = node.get("visible")
		var mesh: Resource = node.get("mesh")
		if mesh != null: rendered.mesh = mesh.call("get_mesh")
		rendered.skin = node.get("skin")
		rendered.skeleton = node.get("skeleton_path")
		if node.get_parent() != null: node.replace_by(rendered)
		else:
			for child in node.get_children(): node.remove_child(child); rendered.add_child(child)
		node.free()
		node = rendered
	for child in node.get_children(): _materialize(child)
	return node

static func _own_children(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own_children(child, root)

static func _collect_textures(folder: String, result: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() in TEXTURES: result.append(folder.path_join(file))
	for child in DirAccess.get_directories_at(folder): _collect_textures(folder.path_join(child), result)
