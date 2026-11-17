@tool
extends EditorPlugin
const PanelScript := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/editor_panel.gd")
const Debugger := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/debugger.gd")
var panel: Control
var debugger: EditorDebuggerPlugin
var native_guard: ResourceFormatSaver
func _enter_tree() -> void:
	native_guard = preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/native_save_guard.gd").new(true)
	preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd").native_guard = native_guard
	native_guard.enabled = true
	native_guard.roots = EditorInterface.get_open_scene_roots
	native_guard.current_root = EditorInterface.get_edited_scene_root
	native_guard.mark_unsaved = EditorInterface.mark_scene_as_unsaved
	native_guard.ensure_first.call_deferred()
	scene_saved.connect(native_guard.scene_saved)
	scene_closed.connect(native_guard.forget_scene)
	set_meta("godot_level_editor_module", "mechanisms")
	add_to_group("godot_level_editor_suite_modules")
	panel = PanelScript.new()
	panel.plugin = self
	native_guard.panel = weakref(panel)
	panel.name = "MechanismBlueprint"
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	scene_changed.connect(panel.bind_scene)
	EditorInterface.get_selection().selection_changed.connect(panel.scene_selection_changed)
	EditorInterface.get_inspector().property_edited.connect(panel.inspector_edited)
	debugger = Debugger.new()
	debugger.state_received.connect(panel.receive_runtime)
	debugger.instance_removed.connect(panel.remove_runtime)
	debugger.session_cleared.connect(panel.clear_session)
	add_debugger_plugin(debugger)
	panel.bind_scene(EditorInterface.get_edited_scene_root())
	if "--mechanism-canvas-test" in OS.get_cmdline_user_args(): _run_canvas_test.call_deferred()
	if "--whitebox-mechanism-editor-test" in OS.get_cmdline_user_args(): _run_whitebox_test.call_deferred()
	if "--mechanism-qa-fixes" in OS.get_cmdline_user_args(): _run_qa_test.call_deferred()
	if "--rotating-door-editor-test" in OS.get_cmdline_user_args(): _run_door_test.call_deferred()
	if "--independent-mechanism-editor-test" in OS.get_cmdline_user_args(): _run_independent_test.call_deferred()
func _has_main_screen() -> bool:
	return not _in_suite()
func _get_plugin_name() -> String:
	return "机关蓝图"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("VisualShader", "EditorIcons")
func _make_visible(value: bool) -> void:
	if is_instance_valid(panel): panel.visible = value
func _get_unsaved_status(for_scene: String) -> String:
	if native_guard != null:
		for path in native_guard.blocked:
			if for_scene.is_empty() or path == for_scene: return "机关未保存：" + str(native_guard.blocked[path].reason)
	return "机关图有未保存修改。" if is_instance_valid(panel) and panel.dirty and (for_scene.is_empty() or is_instance_valid(panel.assembly) and panel.assembly.scene_file_path == for_scene) else ""
func _exit_tree() -> void:
	if native_guard != null:
		native_guard.enabled = false
		native_guard.panel = null
		native_guard.roots = Callable(); native_guard.current_root = Callable(); native_guard.mark_unsaved = Callable()
		native_guard.records.clear(); native_guard.blocked.clear(); native_guard.pending.clear()
		preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd").native_guard = null
	if debugger != null: remove_debugger_plugin(debugger)
	if is_instance_valid(panel):
		if EditorInterface.get_selection().selection_changed.is_connected(panel.scene_selection_changed): EditorInterface.get_selection().selection_changed.disconnect(panel.scene_selection_changed)
		if EditorInterface.get_inspector().property_edited.is_connected(panel.inspector_edited): EditorInterface.get_inspector().property_edited.disconnect(panel.inspector_edited)
		panel.queue_free()

func _apply_changes() -> void:
	# This hook cannot veto writes. Ensure the guard runs before the built-in
	# saver even if a filesystem scan just rebuilt Godot's saver registration.
	if native_guard != null: native_guard.ensure_first()

func _build() -> bool:
	if is_instance_valid(panel) and is_instance_valid(panel.assembly): return panel._validate()
	return true

func _run_canvas_test() -> void:
	get_tree().create_timer(80, true).timeout.connect(func(): get_tree().quit(2))
	var test: RefCounted = load("res://tools/mechanisms/test_canvas.gd").new()
	await test.run(panel, self)

func _in_suite() -> bool:
	return "res://addons/godot_level_editor/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())

func _run_whitebox_test() -> void:
	get_tree().create_timer(90, true).timeout.connect(func(): get_tree().quit(2))
	await load("res://tools/mechanisms/whitebox_v1/test_editor.gd").new().run(panel, self)

func _run_qa_test() -> void:
	get_tree().create_timer(90, true).timeout.connect(func(): get_tree().quit(2))
	await load("res://tools/mechanisms/qa_2026_11_16/test_editor.gd").new().run(panel, self)

func _run_door_test() -> void:
	get_tree().create_timer(100, true).timeout.connect(func(): get_tree().quit(2))
	await load("res://tools/mechanisms/doors_v2/test_editor.gd").new().run(panel, self)

func _run_independent_test() -> void:
	get_tree().create_timer(100, true).timeout.connect(func(): get_tree().quit(2))
	await load("res://tools/mechanisms/independent_v1/test_editor.gd").new().run(panel, self)
