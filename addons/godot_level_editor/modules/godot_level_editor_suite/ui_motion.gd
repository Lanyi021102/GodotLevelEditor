@tool
extends RefCounted
## Presentation-only motion. Controls keep their position, scale and input bounds.
const BUTTON_META := "godot_level_editor_button_motion"
const REVEAL_META := "godot_level_editor_reveal_motion"
const LAYER_META := "godot_level_editor_reveal_owner"
const BLUE := Color("2563eb")
const STATES := ["normal", "hover", "pressed", "hover_pressed"]
static var enabled := true

class ButtonMotion extends RefCounted:
	var enabled := true
	var reference: WeakRef
	var original: Dictionary = {}
	var baseline: Dictionary = {}
	var surface: StyleBoxFlat
	var tween: Tween
	var hovering := false
	var holding := false
	var installed := false

	func control() -> Button:
		return reference.get_ref() as Button if reference != null else null

	func attach(button: Button) -> void:
		reference = weakref(button)
		button.mouse_entered.connect(_enter)
		button.mouse_exited.connect(_leave)
		button.focus_entered.connect(_focus)
		button.focus_exited.connect(_focus)
		button.button_down.connect(_down)
		button.button_up.connect(_up)
		button.toggled.connect(_toggle)
		button.visibility_changed.connect(_visibility)
		button.tree_exiting.connect(detach)
		install()

	func install() -> void:
		var button := control()
		if button == null or installed: return
		original.clear()
		baseline.clear()
		for state in STATES:
			var style := button.get_theme_stylebox(state) as StyleBoxFlat
			if style == null: return
			original[state] = style if button.has_theme_stylebox_override(state) else null
			baseline[state] = style.duplicate()
		surface = baseline.normal.duplicate() as StyleBoxFlat
		# Keep border geometry fixed; a hidden underline is a transparent border.
		# This animates secondary navigation without changing container layout.
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var width := 0
			for state in STATES: width = maxi(width, baseline[state].get_border_width(side))
			surface.set_border_width(side, width)
		for state in STATES:
			var style: StyleBoxFlat = baseline[state]
			if style.get_border_width_min() == 0 and style.border_width_left == 0 and style.border_width_top == 0 and style.border_width_right == 0 and style.border_width_bottom == 0:
				style.border_color = Color.TRANSPARENT
			button.add_theme_stylebox_override(state, surface)
		installed = true
		settle()

	func _state() -> String:
		var button := control()
		if button == null: return "normal"
		var pressed := button.button_pressed if button.toggle_mode else holding
		if pressed: return "hover_pressed" if hovering else "pressed"
		return "hover" if hovering else "normal"

	func _shadow() -> Color:
		var button := control()
		if button == null or button.disabled or not button.is_visible_in_tree(): return Color.TRANSPARENT
		var selected: bool = button.toggle_mode and button.button_pressed
		if holding: return Color(BLUE, 0.07)
		if button.has_focus(): return Color(BLUE, 0.16)
		if hovering: return Color(BLUE, 0.13 if selected else 0.08)
		return Color.TRANSPARENT

	func _stop() -> void:
		if tween != null and tween.is_valid(): tween.kill()
		tween = null

	func settle() -> void:
		_stop()
		var button := control()
		if button == null or not installed: return
		var target: StyleBoxFlat = baseline[_state()]
		surface.bg_color = target.bg_color
		surface.border_color = target.border_color
		surface.shadow_color = Color.TRANSPARENT
		surface.shadow_size = 0
		surface.shadow_offset = Vector2.ZERO

	func animate(seconds := 0.18) -> void:
		if not enabled: settle(); return
		var button := control()
		if button == null or not installed: return
		if not button.is_inside_tree() or not button.is_visible_in_tree(): settle(); return
		_stop()
		var target: StyleBoxFlat = baseline[_state()]
		var shadow := _shadow()
		tween = button.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.tween_property(surface, "bg_color", target.bg_color, seconds)
		tween.tween_property(surface, "border_color", target.border_color, seconds)
		tween.tween_property(surface, "shadow_color", shadow, seconds)
		tween.tween_property(surface, "shadow_size", 7 if shadow.a > 0.0 else 0, seconds)
		tween.tween_property(surface, "shadow_offset", Vector2(0, 1 if holding else 2) if shadow.a > 0.0 else Vector2.ZERO, seconds)

	func _enter() -> void:
		hovering = true
		animate(0.16)

	func _leave() -> void:
		hovering = false
		animate(0.22)

	func _focus() -> void:
		animate(0.18)

	func _down() -> void:
		holding = true
		animate(0.08)

	func _up() -> void:
		holding = false
		animate(0.20)

	func _toggle(_pressed: bool) -> void:
		animate(0.22)

	func _visibility() -> void:
		var button := control()
		if button != null and not button.is_visible_in_tree():
			hovering = false
			holding = false
			settle()

	func detach() -> void:
		_stop()
		var button := control()
		if button != null and installed:
			for state in STATES:
				if original[state] != null: button.add_theme_stylebox_override(state, original[state])
				else: button.remove_theme_stylebox_override(state)
		hovering = false
		holding = false
		installed = false

class RevealMotion extends RefCounted:
	var enabled := true
	var reference: WeakRef
	var layers: Array[Dictionary] = []
	var tween: Tween

	func attach(root: Control) -> void:
		reference = weakref(root)
		root.visibility_changed.connect(_visibility)
		root.tree_exiting.connect(stop)

	func _visibility() -> void:
		var root := reference.get_ref() as Control
		if root != null and not root.is_visible_in_tree(): stop()

	func stop() -> void:
		if tween != null and tween.is_valid(): tween.kill()
		tween = null
		for layer in layers:
			var control := layer.reference.get_ref() as Control
			if control != null and control.has_meta(LAYER_META) and control.get_meta(LAYER_META) == self:
				control.modulate.a = layer.alpha
				control.remove_meta(LAYER_META)
		layers.clear()

	func _add(control: Control, alpha: float, delay: float) -> void:
		var previous: RevealMotion = control.get_meta(LAYER_META) if control.has_meta(LAYER_META) else null
		if previous != null and previous != self: previous.stop()
		var original := control.modulate.a
		control.set_meta(LAYER_META, self)
		layers.append({"reference": weakref(control), "alpha": original})
		control.modulate.a = original * alpha
		tween.tween_property(control, "modulate:a", original, 0.26).set_delay(delay)

	func play(stagger: bool) -> void:
		stop()
		if not enabled: return
		var root := reference.get_ref() as Control
		if root == null or not root.is_inside_tree() or not root.is_visible_in_tree(): return
		# Resolve a parent reveal before owning any nested layer. This prevents
		# two simultaneous reveals from writing the same opacity during tab changes.
		var previous: RevealMotion = root.get_meta(LAYER_META) if root.has_meta(LAYER_META) else null
		if previous != null and previous != self: previous.stop()
		tween = root.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_add(root, 0.92, 0.0)
		if stagger:
			var index := 0
			for child in root.get_children():
				if not child is Control or child is GraphNode or child is GraphEdit or not child.visible: continue
				_add(child, 0.80, minf(index * 0.025, 0.10))
				index += 1
				if index >= 6: break
		tween.finished.connect(stop, CONNECT_ONE_SHOT)

static func button(control: Button) -> void:
	if not is_instance_valid(control): return
	var motion: ButtonMotion = control.get_meta(BUTTON_META) if control.has_meta(BUTTON_META) else null
	if motion == null:
		motion = ButtonMotion.new()
		control.set_meta(BUTTON_META, motion)
		motion.attach(control)
	else: motion.install()
	motion.enabled = enabled

static func selection(control: Button) -> void:
	button(control)
	var motion: ButtonMotion = control.get_meta(BUTTON_META)
	motion.animate(0.22)

static func reveal(control: Control, stagger := true) -> void:
	if not is_instance_valid(control): return
	var motion: RevealMotion = control.get_meta(REVEAL_META) if control.has_meta(REVEAL_META) else null
	if motion == null:
		motion = RevealMotion.new()
		control.set_meta(REVEAL_META, motion)
		motion.attach(control)
	motion.enabled = enabled
	motion.play(stagger)
