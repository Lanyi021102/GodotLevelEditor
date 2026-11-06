@tool
extends EditorPlugin
const PanelScript := preload("res://addons/branch_mechanisms/editor_panel.gd")
const Debugger := preload("res://addons/branch_mechanisms/debugger.gd")
var panel: Control
var debugger: EditorDebuggerPlugin
func _enter_tree() -> void:
	panel = PanelScript.new()
	panel.plugin = self
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
func _has_main_screen() -> bool:
	return true
func _get_plugin_name() -> String:
	return "机关蓝图"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("VisualShader", "EditorIcons")
func _make_visible(value: bool) -> void:
	if is_instance_valid(panel): panel.visible = value
func _get_unsaved_status(_for_scene: String) -> String:
	return "机关图有未保存修改，请使用机关蓝图中的保存。" if is_instance_valid(panel) and panel.dirty else ""
func _exit_tree() -> void:
	if debugger != null: remove_debugger_plugin(debugger)
	if is_instance_valid(panel):
		if EditorInterface.get_selection().selection_changed.is_connected(panel.scene_selection_changed): EditorInterface.get_selection().selection_changed.disconnect(panel.scene_selection_changed)
		if EditorInterface.get_inspector().property_edited.is_connected(panel.inspector_edited): EditorInterface.get_inspector().property_edited.disconnect(panel.inspector_edited)
		panel.queue_free()

func _apply_changes() -> void:
	if is_instance_valid(panel): panel.save_before_editor()

func _build() -> bool:
	if is_instance_valid(panel) and is_instance_valid(panel.assembly): return panel._validate()
	return true

func _run_canvas_test() -> void:
	get_tree().create_timer(80, true).timeout.connect(func(): get_tree().quit(2))
	var test: RefCounted = load("res://tools/mechanisms/test_canvas.gd").new()
	await test.run(panel, self)
