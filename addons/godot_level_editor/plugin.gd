@tool
extends EditorPlugin
## Distribution-only entry point. Development plugins and paths are unchanged.
const ROOT := "res://addons/godot_level_editor"
const USER := "res://content"
const MODULES := ["enemy_editor", "godot_level_editor_mechanisms", "godot_level_editor", "godot_level_editor_narrative", "godot_level_editor_suite"]
const SERVICES := {"GLELightZones": "stealth/light_zones.gd", "GLENoiseBus": "stealth/noise_bus.gd", "GLESaveSystem": "core/save_system.gd"}
const KEYS := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "jump": KEY_SPACE, "sprint": KEY_SHIFT, "interact": KEY_F, "camera_swap_shoulder": KEY_V}
var _started := false

func _enter_tree() -> void:
	_start.call_deferred()

func _start() -> void:
	if not is_inside_tree(): return
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.is_scanning():
		await filesystem.filesystem_changed
		if not is_inside_tree(): return
	# Check every conflict before making any change to the host project.
	for service in SERVICES:
		var expected := "*" + ROOT + "/scripts/" + str(SERVICES[service])
		var key := "autoload/" + str(service)
		if ProjectSettings.has_setting(key) and str(ProjectSettings.get_setting(key)).trim_prefix("*") != expected.trim_prefix("*"):
			push_error("GodotLevelEditor 无法启用：已有不同的运行服务 " + str(service))
			return
	for directory in ["scenes/levels", "scenes/mechanisms", "scenes/npcs", "resources/enemies", "resources/task_graphs", "resources/level_previews", "resources/narrative", "resources/sky_presets/custom", "assets/sky_hdri", "tables"]:
		if DirAccess.make_dir_recursive_absolute(USER + "/" + directory) != OK:
			push_error("GodotLevelEditor 无法创建作品目录：" + directory)
			return
	for name in ["levels", "events", "dialogues"]:
		var destination: String = USER + "/tables/" + str(name) + ".xlsx"
		if not FileAccess.file_exists(destination):
			if DirAccess.copy_absolute(ROOT + "/defaults/" + name + ".xlsx", destination) != OK:
				push_error("GodotLevelEditor 无法初始化配表：" + name)
				return
	for service in SERVICES:
		if not ProjectSettings.has_setting("autoload/" + str(service)):
			ProjectSettings.set_setting("autoload/" + str(service), "*" + ROOT + "/scripts/" + str(SERVICES[service]))
	for action in KEYS:
		if not ProjectSettings.has_setting("input/" + str(action)):
			var event := InputEventKey.new()
			event.physical_keycode = KEYS[action]
			ProjectSettings.set_setting("input/" + str(action), {"deadzone": 0.2, "events": [event]})
	if str(ProjectSettings.get_setting("application/run/main_scene", "")).is_empty():
		if not _create_start_scene(): return
	ProjectSettings.save()
	EditorInterface.get_resource_filesystem().scan()
	for module in MODULES:
		var path := "godot_level_editor/modules/" + str(module)
		if not EditorInterface.is_plugin_enabled(path): EditorInterface.set_plugin_enabled(path, true)
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	ProjectSettings.set_setting("editor_plugins/enabled", PackedStringArray(Array(enabled).filter(func(path: String): return not path.begins_with(ROOT + "/modules/"))))
	ProjectSettings.save()
	_started = true
	print("GODOT_LEVEL_EDITOR_READY")
	if OS.get_cmdline_user_args().has("--release-smoke"):
		var test: Node = load("res://release_smoke.gd").new()
		add_child(test)
		test.run.call_deferred(self)

func _create_start_scene() -> bool:
	var levels = load(ROOT + "/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	if levels.catalog == null:
		push_error("GodotLevelEditor 无法创建起始场景：关卡配表无效。")
		return false
	var world: Node3D = load(ROOT + "/templates/empty_level.tscn").instantiate()
	var id: String = levels.catalog.allocate_id()
	world.name = "Start"
	world.level_id = id
	world.world_id = "level_" + id
	for key in ["topology", "events", "level_logic"]:
		var graph: Resource = world.get(key).duplicate(true)
		graph.graph_id = world.world_id + "_" + str(key)
		world.set(key, graph)
	var path := USER + "/scenes/levels/start.tscn"
	var number := 1
	while FileAccess.file_exists(path):
		path = USER + "/scenes/levels/start_" + str(number) + ".tscn"
		number += 1
	var scene := PackedScene.new()
	var result := scene.pack(world)
	world.free()
	if result != OK or ResourceSaver.save(scene, path) != OK:
		push_error("GodotLevelEditor 无法保存起始场景。")
		return false
	preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/native_level_registry.gd").saved(path)
	ProjectSettings.set_setting("application/run/main_scene", path)
	print("RELEASE_DEFAULT_READY: ", path)
	return true

func _disable_plugin() -> void:
	# Called on an explicit disable, not on editor shutdown. Keep user content,
	# input bindings and runtime services so authored games remain runnable.
	for index in range(MODULES.size() - 1, -1, -1):
		var path := "godot_level_editor/modules/" + str(MODULES[index])
		if EditorInterface.is_plugin_enabled(path): EditorInterface.set_plugin_enabled(path, false)
	_started = false
