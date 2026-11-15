@tool
extends RefCounted
## Accept catalog scene drops in the existing native view; keep its camera and
## all ordinary mouse input native. This makes grouping part of the add action.
const SURFACE := preload("res://addons/godot_level_editor/asset_drop_surface.gd")
const CATALOG := preload("res://addons/godot_level_editor/asset_catalog.gd")
var plugin: EditorPlugin
var surfaces: Array[Control] = []
var _active := false
var _signature := ""
var _surface: Control

func assets_for(data: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not data is Dictionary or data.get("type") != "files": return result
	var files: Variant = data.get("files", [])
	if not files is Array and not files is PackedStringArray: return result
	for path in files:
		var asset := CATALOG.find_asset(str(path))
		if asset.is_empty(): return []
		if files.size() > 1 and asset.category == "玩家出生点": return []
		result.append(asset)
	return result

func sync() -> void:
	var usable: bool = plugin.radial_tool.usable_root() != null and not EditorInterface.is_playing_scene()
	var dragging := false
	for i in 4:
		var view := EditorInterface.get_editor_viewport_3d(i)
		if view == null: continue
		var surface: Control
		for candidate in surfaces:
			if is_instance_valid(candidate) and candidate.editor_view == view: surface = candidate; break
		if surface == null:
			var parent := view.get_parent() as Control
			while parent.get_parent() is Control and parent.get_class() != "Node3DEditorViewport": parent = parent.get_parent()
			surface = SURFACE.new(); surface.tool = self; surface.editor_view = view
			parent.add_child(surface); surfaces.append(surface)
		var viewport := surface.get_viewport()
		var accepts: bool = usable and viewport.gui_is_dragging() and not assets_for(viewport.gui_get_drag_data()).is_empty()
		surface.mouse_filter = Control.MOUSE_FILTER_PASS if accepts else Control.MOUSE_FILTER_IGNORE
		if accepts:
			dragging = true
			surface.move_to_front()
	if _active and not dragging: _cancel()

func preview_drop(surface: Control, at: Vector2, data: Variant) -> bool:
	var assets := assets_for(data)
	if assets.is_empty() or plugin.radial_tool.usable_root() == null: return false
	var camera: Camera3D = surface.editor_view.get_camera_3d()
	var point: Vector2 = surface.camera_point(at)
	var signature := JSON.stringify(data.files)
	if not _active or signature != _signature or _surface != surface:
		plugin.radial_tool.open_wheel(camera, point)
		if not plugin.radial_tool.begin_asset(assets[0]): return false
		_active = true; _signature = signature; _surface = surface
	plugin.radial_tool.update_preview(camera, point)
	return plugin.radial_tool.placement_valid

func commit_drop(surface: Control, at: Vector2, data: Variant) -> void:
	if not preview_drop(surface, at, data): return
	var assets := assets_for(data)
	var radial: RefCounted = plugin.radial_tool
	if assets.size() == 1 and assets[0].category == "玩家出生点":
		radial.place()
	else:
		var nodes: Array[Node] = []
		for asset in assets:
			if not radial.begin_asset(asset):
				for node in nodes: node.free()
				_cancel(); return
			radial.update_preview(surface.editor_view.get_camera_3d(), surface.camera_point(at))
			var node: Node3D = radial.placement_instance(asset, radial.placement_transform)
			if node == null:
				for prepared in nodes: prepared.free()
				_cancel(); return
			nodes.append(node)
		var root: Node = radial.scene_root
		plugin._add_nodes_undoable(root, nodes, root, "拖放关卡素材")
		for asset in assets: radial.remember_asset(asset)
	_cancel()

func _cancel() -> void:
	_active = false; _signature = ""; _surface = null
	if plugin.radial_tool != null: plugin.radial_tool.cancel()

func dispose() -> void:
	_cancel()
	for surface in surfaces:
		if is_instance_valid(surface): surface.queue_free()
	surfaces.clear()
