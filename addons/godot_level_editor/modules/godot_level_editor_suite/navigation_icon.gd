@tool
extends TextureRect
## Animate the glyph only. The Button's original icon still reserves its layout.
const MOTION := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/ui_motion.gd")
var button: Button
var kind := ""
var _palette: Dictionary = {}
var _origin := Vector2.ZERO
var _tween: Tween
var _last_frame := -1
var _last_selected := false

static func install(target: Button, icon_kind: String) -> void:
	if target.has_meta("navigation_icon_motion"): return
	var icon: TextureRect = load("res://addons/godot_level_editor/modules/godot_level_editor_suite/navigation_icon.gd").new()
	icon.name = "NavigationIcon"
	icon.button = target
	icon.kind = icon_kind
	icon.texture = target.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_disabled_color"]:
		icon._palette[state] = target.get_theme_color(state)
		target.add_theme_color_override(state, Color.TRANSPARENT)
	target.set_meta("navigation_icon_motion", icon)
	target.add_child(icon)
	target.resized.connect(icon._layout)
	target.theme_changed.connect(icon._sync_color)
	target.mouse_entered.connect(icon._sync_color)
	target.mouse_exited.connect(icon._sync_color)
	target.pressed.connect(icon._clicked)
	target.visibility_changed.connect(icon._visibility)
	target.get_window().visibility_changed.connect(icon._visibility)
	icon._layout()
	icon._sync_color()

func _layout() -> void:
	if not is_instance_valid(button): return
	var width := float(button.get_theme_constant("icon_max_width"))
	size = Vector2(width, width)
	pivot_offset = size * 0.5
	_origin = Vector2((button.size.x - width) * 0.5, button.get_theme_stylebox("normal").get_content_margin(SIDE_TOP))
	if _tween == null or not _tween.is_running(): position = _origin

func _sync_color() -> void:
	if not is_instance_valid(button): return
	var state := "icon_pressed_color" if button.button_pressed else "icon_normal_color"
	if button.disabled: state = "icon_disabled_color"
	self_modulate = _palette.get(state, Color.WHITE)

func _clicked() -> void:
	play(bool(button.get_meta("navigation_selected", button.button_pressed)))

func play(selected: bool) -> void:
	_sync_color()
	if not MOTION.enabled or not is_visible_in_tree() or not get_window().visible: reset(); return
	var frame := Engine.get_process_frames()
	if frame == _last_frame and selected == _last_selected: return
	reset()
	_last_frame = frame
	_last_selected = selected
	_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	_tween.tween_method(_pose.bind(selected), 0.0, 1.0, 0.44 if selected else 0.24)
	_tween.finished.connect(_rest, CONNECT_ONE_SHOT)

func _pose(t: float, selected: bool) -> void:
	var pulse := sin(PI * t)
	var wobble := sin(TAU * t) * (1.0 - t)
	var strength := 1.0 if selected else -0.35
	var offset := Vector2.ZERO
	var angle := 0.0
	var stretch := Vector2.ONE
	match kind:
		"mechanism": angle = deg_to_rad(38) * pulse * strength
		"task":
			angle = deg_to_rad(-11) * wobble * strength
			stretch += Vector2.ONE * pulse * 0.14 * strength
			offset.y = -2.0 * pulse * strength
		"level", "home":
			offset.y = -3.0 * pulse * strength
			stretch += Vector2(0.07, -0.02) * pulse * strength
		"dialogue":
			angle = deg_to_rad(10) * wobble * strength
			stretch += Vector2.ONE * 0.09 * pulse * strength
		"npc":
			offset.y = -2.5 * pulse * strength
			angle = deg_to_rad(7) * wobble * strength
		"sky":
			offset.x = 2.5 * pulse * strength
			angle = deg_to_rad(12) * pulse * strength
		_:
			angle = deg_to_rad(9) * wobble * strength
			stretch += Vector2(0.12, -0.08) * pulse * strength
	position = _origin + offset
	rotation = angle
	scale = stretch

func _rest() -> void:
	position = _origin
	rotation = 0.0
	scale = Vector2.ONE

func reset() -> void:
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null
	_rest()

func _visibility() -> void:
	if not is_visible_in_tree() or not get_window().visible: reset()

func _exit_tree() -> void:
	reset()
