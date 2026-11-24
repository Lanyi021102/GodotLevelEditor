@tool
extends VBoxContainer
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")
const MOTION := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/ui_motion.gd")
const WIKI := "https://lanyi021102.github.io/GodotLevelEditor/"
var suite: EditorPlugin
var scale_picker: OptionButton
var animation_toggle: CheckBox
var scale_status: Label
var resume_button: Button
var _building := false

func _ready() -> void:
	var title := Label.new(); title.text = "工作台"; title.add_theme_font_size_override("font_size", 28); add_child(title)
	var actions := HFlowContainer.new()
	add_child(actions)
	var create := _button(actions, "新建关卡", suite.create_level)
	create.theme_type_variation = "PrimaryButton"
	resume_button = _button(actions, "继续上次关卡", suite.resume_level)
	_button(actions, "我的关卡", func(): suite.open_tab("关卡"); suite.level_panel.set_mode(0))
	var gap := Control.new(); gap.custom_minimum_size.y = 12; add_child(gap)
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(scroll)
	var columns := HBoxContainer.new(); columns.add_theme_constant_override("separation", 20); columns.size_flags_vertical = Control.SIZE_EXPAND_FILL; columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(columns)
	var preferences := _card(columns, "界面偏好")
	preferences.size_flags_stretch_ratio = 1.25
	_label(preferences, "界面缩放")
	scale_picker = OptionButton.new(); scale_picker.name = "DisplayScale"; scale_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for factor in [0.0, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]:
		scale_picker.add_item("自动 · 跟随系统" if factor == 0.0 else "%d%%" % roundi(factor * 100))
		scale_picker.set_item_metadata(scale_picker.item_count - 1, factor)
	preferences.add_child(scale_picker)
	scale_picker.item_selected.connect(_scale_selected)
	scale_status = _label(preferences, "")
	scale_status.add_theme_color_override("font_color", STYLE.MUTED)
	_label(preferences, "动效")
	animation_toggle = CheckBox.new(); animation_toggle.name = "InterfaceAnimations"; animation_toggle.text = "播放图标与界面动画"; preferences.add_child(animation_toggle)
	animation_toggle.toggled.connect(_animations_changed)
	var hint := _label(preferences, "设置仅保存在本机当前项目，修改后立即生效。")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hint.add_theme_color_override("font_color", STYLE.MUTED)
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; preferences.add_child(spacer)
	_button(preferences, "恢复默认偏好", restore_defaults)
	var help := _card(columns, "文档与快捷入口")
	_button(help, "打开在线 Wiki", func(): OS.shell_open(WIKI))
	if FileAccess.file_exists("res://site/index.html"):
		_button(help, "打开本地 Wiki", func(): OS.shell_open(ProjectSettings.globalize_path("res://site/index.html")))
	_button(help, "打开项目文件夹", func(): OS.shell_open(ProjectSettings.globalize_path("res://")))
	var heading := _label(help, "开始制作"); heading.add_theme_color_override("font_color", STYLE.MUTED)
	for section in ["任务图", "机关"]:
		_button(help, "打开" + section, func(): suite.open_tab(section))
	var version := _label(help, "Godot " + str(Engine.get_version_info().string))
	version.add_theme_color_override("font_color", STYLE.MUTED)
	visibility_changed.connect(_refresh)
	suite.display_adapter.scale_changed.connect(func(_factor: float): _refresh())
	_refresh()

func _card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", STYLE.bordered(STYLE.PAPER, STYLE.BORDER, 12, 24)); parent.add_child(panel)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 18); panel.add_child(content)
	var heading := _label(content, title); heading.add_theme_font_size_override("font_size", 21)
	return content

func _label(parent: Node, text: String) -> Label:
	var label := Label.new(); label.text = text; parent.add_child(label); return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text; button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.custom_minimum_size.y = 42; button.pressed.connect(callback); parent.add_child(button)
	return button

func _refresh() -> void:
	if not is_instance_valid(scale_picker): return
	_building = true
	var settings := EditorInterface.get_editor_settings()
	var recent: String = suite.recent_level()
	resume_button.disabled = recent.is_empty()
	resume_button.tooltip_text = recent if not recent.is_empty() else "打开或保存自己的关卡后，可从这里继续。"
	var factor := float(settings.get_project_metadata("godot_level_editor_suite", "ui_scale", 0.0))
	for i in scale_picker.item_count:
		if is_equal_approx(float(scale_picker.get_item_metadata(i)), factor): scale_picker.select(i)
	animation_toggle.set_pressed_no_signal(MOTION.enabled)
	scale_status.text = "当前显示：%d%%" % roundi(suite.display_adapter.scale_factor * 100)
	_building = false

func _scale_selected(index: int) -> void:
	if _building: return
	suite.display_adapter.set_user_scale(float(scale_picker.get_item_metadata(index)))
	_refresh()

func _animations_changed(value: bool) -> void:
	if _building: return
	MOTION.enabled = value
	EditorInterface.get_editor_settings().set_project_metadata("godot_level_editor_suite", "animations_enabled", value)
	for button in suite.window.find_children("*", "Button", true, false):
		if button.has_meta(MOTION.BUTTON_META):
			button.get_meta(MOTION.BUTTON_META).enabled = value
			if not value: button.get_meta(MOTION.BUTTON_META).settle()
		if not value and button.has_meta("navigation_icon_motion"): button.get_meta("navigation_icon_motion").reset()
	if not value:
		for control in suite.window.find_children("*", "Control", true, false):
			if control.has_meta(MOTION.REVEAL_META): control.get_meta(MOTION.REVEAL_META).stop()

func restore_defaults() -> void:
	suite.display_adapter.set_user_scale(0.0)
	_animations_changed(true)
	_refresh()
