@tool
extends EditorPlugin
var panel: TabContainer
var dialogue_panel: Control
var task_panel: Control
var debugger: EditorDebuggerPlugin
var csv_export: EditorExportPlugin
func _enter_tree() -> void:
	set_meta("godot_level_editor_module", "narrative")
	add_to_group("godot_level_editor_suite_modules")
	csv_export = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/export_plugin.gd").new()
	add_export_plugin(csv_export)
	panel = TabContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EditorInterface.get_editor_main_screen().add_child(panel)
	dialogue_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/dialogue_panel.gd").new()
	dialogue_panel.name = "台本编辑器"
	panel.add_child(dialogue_panel)
	task_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/task_panel.gd").new()
	task_panel.name = "任务编辑器"
	task_panel.plugin = self
	panel.add_child(task_panel)
	debugger = preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/debugger.gd").new()
	debugger.state_received.connect(task_panel.receive_runtime)
	debugger.instance_removed.connect(task_panel.remove_runtime)
	debugger.session_cleared.connect(task_panel.clear_session)
	debugger.session_paused.connect(task_panel.set_session_paused)
	add_debugger_plugin(debugger)
	scene_changed.connect(func(_root: Node): task_panel.use_current_world.call_deferred())
	panel.hide()
	if OS.get_cmdline_user_args().has("--godot-level-editor-narrative-smoke"):
		_run_smoke.call_deferred()
func _has_main_screen() -> bool: return not _in_suite()
func _get_plugin_name() -> String: return "台本与任务"
func _get_plugin_icon() -> Texture2D: return EditorInterface.get_base_control().get_theme_icon("Edit", "EditorIcons")
func _make_visible(value: bool) -> void:
	if is_instance_valid(panel): panel.visible = value
func _save_external_data() -> void:
	if is_instance_valid(dialogue_panel) and dialogue_panel.dirty: dialogue_panel.save()
	if is_instance_valid(task_panel) and task_panel.dirty and not task_panel.graph.resource_path.is_empty(): task_panel.save_graph()
func _exit_tree() -> void:
	if csv_export != null: remove_export_plugin(csv_export)
	if debugger != null: remove_debugger_plugin(debugger)
	if is_instance_valid(panel): panel.queue_free()

func _run_smoke() -> void:
	var smoke = load("res://tools/narrative/editor_smoke.gd").new()
	await smoke.run(self)

func _in_suite() -> bool:
	return "res://addons/godot_level_editor/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
