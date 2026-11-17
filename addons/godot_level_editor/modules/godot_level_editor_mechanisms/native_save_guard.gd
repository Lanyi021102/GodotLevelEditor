@tool
class_name MechanismNativeSaveGuard
extends ResourceFormatSaver
## Native editor hooks cannot veto a save. Own assembly serialization before the
## built-in saver runs, including rejection: returning an error would fall through
## to Godot's next saver and overwrite the file (core/io/resource_saver.cpp).
const ASSEMBLY := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/runtime/assembly.gd")
const DEFINITION := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/graph/definition.gd")
const POLICY := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/save_policy.gd")
# Godot rebuilds global custom savers after filesystem scans. Shared state keeps
# the newly registered saver connected to the plugin's live scene baselines.
static var enabled := false
static var panel: WeakRef
static var roots: Callable
static var current_root: Callable
static var mark_unsaved: Callable
static var records: Dictionary = {}
static var blocked: Dictionary = {}
static var pending: Dictionary = {}
static var delegating := 0
static var registered: WeakRef

func _init(controller := false) -> void:
	if controller or not Engine.is_editor_hint(): return
	registered = weakref(self)
	_prioritize.call_deferred()

func _prioritize() -> void:
	# Auto-registration appends custom savers after the built-in text saver.
	# Run after registration (and after every scan) to handle assemblies first.
	if not enabled or registered == null or registered.get_ref() != self: return
	ResourceSaver.remove_resource_format_saver(self)
	ResourceSaver.add_resource_format_saver(self, true)

func ensure_first() -> void:
	if registered != null and registered.get_ref() != null: registered.get_ref()._prioritize()

static func pair_hash(path: String) -> String:
	var graph_path := path.get_basename() + ".graph.tres"
	return (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "") + ":" + (FileAccess.get_sha256(graph_path) if FileAccess.file_exists(graph_path) else "")

func track(root: Node, reload_disk := false) -> void:
	if not root is ASSEMBLY or root.scene_file_path.is_empty(): return
	var path := root.scene_file_path
	if reload_disk or not records.has(path) or records[path].root.get_ref() != root:
		records[path] = {"hash": pair_hash(path), "root": weakref(root)}
		blocked.erase(path)

func conflict(path: String) -> bool:
	return records.has(path) and str(records[path].hash) != pair_hash(path)

func forget_scene(path: String) -> void:
	records.erase(path); blocked.erase(path); pending.erase(path)

func begin_pair(root: Node, path: String) -> bool:
	if conflict(path): reject(path, "磁盘文件已被其他编辑修改；请重载检查或另存为。", root); return false
	delegating += 1
	return true

func end_pair(root: Node, path: String, success: bool) -> void:
	delegating = maxi(0, delegating - 1)
	if not success: return
	var tracked: WeakRef = records.get(path, {}).get("root", weakref(root))
	records[path] = {"hash": pair_hash(path), "root": tracked}
	blocked.erase(path)
	_clear_rejections(root)

func _clear_rejections(root: Node) -> void:
	for path in blocked.keys():
		var target: WeakRef = blocked[path].root
		if target != null and target.get_ref() == root:
			blocked.erase(path); pending.erase(path)

func _assembly_scene(resource: Resource) -> bool:
	if not resource is PackedScene: return false
	var state: SceneState = resource.get_state()
	while state != null:
		if state.get_node_count() > 0:
			for index in state.get_node_property_count(0):
				if state.get_node_property_name(0, index) == &"script" and state.get_node_property_value(0, index) == ASSEMBLY: return true
		state = state.get_base_scene_state()
	return false

func _recognize(resource: Resource) -> bool:
	return enabled and delegating == 0 and (_assembly_scene(resource) or resource.get_script() == DEFINITION)

func _get_recognized_extensions(resource: Resource) -> PackedStringArray:
	return PackedStringArray(["tscn", "scn"]) if resource is PackedScene else PackedStringArray(["tres", "res"])

func _live_root(path: String, draft: Node = null) -> Node:
	for root in roots.call():
		if root is ASSEMBLY and (root.scene_file_path == path or POLICY.is_plugin_path(path) and root.scene_file_path.to_lower() == path.to_lower()): return root
	if records.has(path):
		var tracked: Node = records[path].root.get_ref()
		if is_instance_valid(tracked) and tracked in roots.call(): return tracked
	var current: Node = current_root.call()
	return current if current is ASSEMBLY and draft is ASSEMBLY and current.instance_id == draft.instance_id else null # Native Save As.

func reject(path: String, reason: String, root: Node = null) -> void:
	if not is_instance_valid(root) and blocked.has(path) and blocked[path].root != null:
		root = blocked[path].root.get_ref()
	blocked[path] = {"reason": reason, "root": weakref(root) if is_instance_valid(root) else null}
	if is_instance_valid(root): pending[path] = {"root": weakref(root), "success": false}
	var view: Control = panel.get_ref() if panel != null else null
	if is_instance_valid(view):
		view.status.text = "未保存：" + reason
		if view.assembly == root: view.dirty = true
	_restore_unsaved.call_deferred(path)

func _restore_unsaved(path: String) -> void:
	if not blocked.has(path): return
	var current: Node = current_root.call()
	var target: WeakRef = blocked[path].root
	if current is ASSEMBLY and (current.scene_file_path == path or target != null and target.get_ref() == current):
		# A handled native Save As still changes the live root's file path after
		# our rejection. Recover its tracked identity before restoring dirty state.
		if current.scene_file_path == path:
			for known in records:
				if known != path and records[known].root.get_ref() == current:
					current.scene_file_path = known
					break
		mark_unsaved.call()

func _save(resource: Resource, path: String, flags: int) -> Error:
	path = POLICY.canonical(path)
	if POLICY.is_plugin_path(path):
		var scene_path := path.trim_suffix(".graph.tres") + ".tscn" if path.ends_with(".graph.tres") else path
		var draft: Node = resource.instantiate() if resource is PackedScene else null
		var live := _live_root(scene_path, draft)
		if draft != null: draft.free()
		reject(scene_path, POLICY.BUILTIN_MESSAGE, live)
		# A handled rejection must not fall through to Godot's text saver.
		return OK
	if resource.get_script() == DEFINITION:
		var scene_path := path.trim_suffix(".graph.tres") + ".tscn"
		if path.ends_with(".graph.tres") and (blocked.has(scene_path) or conflict(scene_path)):
			reject(scene_path, "机关配对保存已被拒绝，保留磁盘图资源。", _live_root(scene_path))
			return OK # Handled without writing; do not let another saver overwrite it.
		delegating += 1
		var result := ResourceSaver.save(resource, path, flags)
		delegating -= 1
		return result
	var root: Node = resource.instantiate()
	var live := _live_root(path, root)
	var store: Script = load("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd")
	var errors: PackedStringArray = store.validate(root)
	if conflict(path): errors.append("磁盘文件已被其他编辑修改；请重载检查或另存为。")
	if path.get_extension() != "tscn": errors.append("机关成对保存请使用 .tscn 场景格式。")
	if not errors.is_empty():
		reject(path, "；".join(errors), live); root.free(); return OK
	var result: Dictionary = store.save_pair(root, path)
	if not result.ok:
		reject(path, "；".join(result.errors), live); root.free(); return OK
	# Update the engine's cached PackedScene too: disk and cache reference the same
	# external definition, never a second embedded authoring graph.
	resource.pack(root)
	pending[path] = {"root": weakref(live), "success": true} if live != null else {"success": true}
	root.free()
	return OK

func scene_saved(path: String) -> void:
	path = ProjectSettings.localize_path(path)
	if not pending.has(path): return
	var outcome: Dictionary = pending[path]; pending.erase(path)
	if not outcome.success: _restore_unsaved.call_deferred(path); return
	var root: Node = outcome.root.get_ref() if outcome.has("root") else null
	if not is_instance_valid(root): return
	_clear_rejections(root)
	root.definition = ResourceLoader.load(path.get_basename() + ".graph.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	records[path] = {"hash": pair_hash(path), "root": weakref(root)}
	var view: Control = panel.get_ref() if panel != null else null
	if is_instance_valid(view) and view.assembly == root:
		view.dirty = false; view._known_hash = view._disk_hash(path)
		view.status.text = "已保存场景与图定义：" + path
		view._render.call_deferred()
