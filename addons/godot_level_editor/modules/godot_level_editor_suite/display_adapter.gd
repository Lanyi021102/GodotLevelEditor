@tool
extends Node
signal scale_changed(factor: float)
const MOTION := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/ui_motion.gd")
## Scale the editor's logical UI once; never multiply both font sizes and DPI.
var window: Window
var scale_factor := 1.0
var _screen := -1
var _elapsed := 0.0
var _popups: Array[Window] = []

static func choose_scale(editor_scale: float, screen_scale: float, dpi: int, manual: bool, platform: String) -> float:
	var value := editor_scale
	if not manual:
		if platform == "macOS" or screen_scale > 1.0: value = screen_scale
		elif dpi >= 144: value = maxf(editor_scale, snappedf(float(dpi) / 96.0, 0.25))
	if not is_finite(value) or value <= 0.0: value = 1.0
	return clampf(value, 0.85, 3.0)

func configure(target: Window) -> void:
	window = target
	window.dpi_changed.connect(refresh)
	window.focus_entered.connect(refresh)
	get_tree().node_added.connect(_node_added)
	MOTION.enabled = bool(EditorInterface.get_editor_settings().get_project_metadata("godot_level_editor_suite", "animations_enabled", true))
	refresh()
	for popup in window.find_children("*", "Window", true, false): _track_popup(popup)
	for button in window.find_children("*", "Button", true, false): _bind_button(button)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5 or not is_instance_valid(window) or not window.visible: return
	_elapsed = 0.0
	if window.current_screen != _screen: refresh()

func refresh() -> void:
	if not is_instance_valid(window): return
	_screen = window.current_screen
	var settings := EditorInterface.get_editor_settings()
	var key := "interface/editor/appearance/display_scale"
	if not settings.has_setting(key): key = "interface/editor/display_scale"
	var manual: bool = settings.has_setting(key) and int(settings.get_setting(key)) != 0
	var factor := EditorInterface.get_editor_scale()
	if DisplayServer.get_name() != "headless":
		factor = choose_scale(factor, DisplayServer.screen_get_scale(_screen), DisplayServer.screen_get_dpi(_screen), manual, OS.get_name())
	var preferred := float(settings.get_project_metadata("godot_level_editor_suite", "ui_scale", 0.0))
	if preferred > 0.0: factor = preferred
	var logical_size := Vector2(window.size) / scale_factor
	var changed := not is_equal_approx(factor, scale_factor)
	apply_scale(factor)
	if changed and window.visible: restore_geometry(Rect2i(window.position, Vector2i(logical_size * factor)), true)

func set_user_scale(factor: float) -> void:
	EditorInterface.get_editor_settings().set_project_metadata("godot_level_editor_suite", "ui_scale", factor)
	refresh()

func apply_scale(factor: float) -> void:
	factor = clampf(factor, 0.85, 3.0)
	var previous := scale_factor
	scale_factor = factor
	window.content_scale_factor = factor
	window.content_scale_size = Vector2i.ZERO
	# Disabled stretch mode still applies content_scale_factor, retaining sharp
	# vector/UI rendering and allowing responsive containers to relayout.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var minimum := Vector2i(Vector2(1040, 700) * factor)
	if DisplayServer.get_name() != "headless": minimum = minimum.min(DisplayServer.screen_get_usable_rect(_screen).size - Vector2i(32, 64))
	window.min_size = minimum
	for i in range(_popups.size() - 1, -1, -1):
		if not is_instance_valid(_popups[i]): _popups.remove_at(i)
		else: _popups[i].content_scale_factor = factor
	window.set_meta("ui_display_scale", factor)
	if not is_equal_approx(previous, factor): scale_changed.emit(factor)

func restore_geometry(saved: Rect2i, has_saved: bool) -> void:
	var usable := Rect2i(Vector2i.ZERO, Vector2i(1920, 1080))
	if DisplayServer.get_name() != "headless": usable = DisplayServer.screen_get_usable_rect(window.current_screen)
	var available := usable.size - Vector2i(32, 64)
	window.size = (saved.size if has_saved else Vector2i(Vector2(1360, 900) * scale_factor)).max(window.min_size).min(available)
	window.position = saved.position if has_saved else usable.position + (usable.size - window.size) / 2
	window.position = window.position.clamp(usable.position + Vector2i(8, 28), usable.end - window.size - Vector2i(8, 8))

func _node_added(node: Node) -> void:
	if not is_instance_valid(window) or not window.is_ancestor_of(node): return
	# Configure before popup() creates the native window, including tooltips
	# which Godot creates and shows synchronously in the same frame.
	if node is Window: _track_popup(node)
	if node is Button: _bind_dynamic_button.call_deferred(weakref(node))

func _bind_dynamic_button(reference: WeakRef) -> void:
	var button := reference.get_ref() as Button
	if is_instance_valid(button) and button.is_inside_tree() and is_instance_valid(window) and window.is_ancestor_of(button):
		_bind_button(button)

func _bind_button(button: Button) -> void:
	if is_instance_valid(button) and not button is CheckBox and not button is CheckButton: MOTION.button(button)

func _track_popup(popup: Window) -> void:
	if not is_instance_valid(popup) or _popups.has(popup): return
	_popups.append(popup)
	popup.content_scale_factor = scale_factor
	if popup is Popup:
		# The shared outer style covers the entire opaque native surface.
		# Avoid transparent black corners without changing project/game settings.
		popup.transparent = false
		popup.transparent_bg = false

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
