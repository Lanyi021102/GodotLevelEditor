extends SceneTree
## Print the actual rig/clip inventory before choosing an animation binding.
func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var document: GLTFDocument = FBXDocument.new() if path.get_extension().to_lower() == "fbx" else GLTFDocument.new()
		var state: GLTFState = FBXState.new() if path.get_extension().to_lower() == "fbx" else GLTFState.new()
		state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
		var error := document.append_from_file(path, state)
		if error != OK:
			print(JSON.stringify({"path": path, "error": error_string(error)})); continue
		var model := document.generate_scene(state)
		var bones: Array = []
		var animations: Array = []
		var meshes: Array = []
		var queue: Array[Node] = [model]
		while not queue.is_empty():
			var node: Node = queue.pop_back(); queue.append_array(node.get_children())
			if node is Skeleton3D:
				var names := PackedStringArray()
				for i in node.get_bone_count(): names.append(node.get_bone_name(i))
				bones.append({"path": str(model.get_path_to(node)), "count": node.get_bone_count(), "names": names})
			if node is AnimationPlayer:
				for clip in node.get_animation_list():
					var animation: Animation = node.get_animation(clip)
					animations.append({"player": str(model.get_path_to(node)), "name": str(clip), "length": animation.length, "tracks": animation.get_track_count()})
			if node is MeshInstance3D: meshes.append({"name": str(node.name), "aabb": str(node.get_aabb()), "transform": str(node.transform)})
		print(JSON.stringify({"path": path, "root_transform": str(model.transform), "bones": bones, "animations": animations, "meshes": meshes}))
		model.free()
	quit()
