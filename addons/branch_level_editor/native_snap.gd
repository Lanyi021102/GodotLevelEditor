@tool
extends RefCounted
## Godot 4.7 has read-only snap accessors. Update its actual snap controls
## through the same signals as the built-in settings dialog, then verify.
static func configure() -> bool:
	var base := EditorInterface.get_base_control()
	var editors := base.find_children("*", "Node3DEditor", true, false)
	if editors.is_empty(): return false
	var native: Control = editors[0]
	var translation: Range
	var snap_dialog: ConfirmationDialog
	# Match the three units, not translated labels or generated control names.
	for dialog in native.find_children("*", "ConfirmationDialog", true, false):
		var sliders := dialog.find_children("*", "EditorSpinSlider", true, false)
		if sliders.size() == 3 and sliders[0].get("suffix") == "m" and sliders[2].get("suffix") == "%":
			translation = sliders[0]
			snap_dialog = dialog
			break
	if translation == null: return false
	translation.value = 0.1
	snap_dialog.emit_signal("confirmed")
	for button in native.find_children("*", "Button", true, false):
		if button.toggle_mode and button.icon == base.get_theme_icon("Snap", "EditorIcons"):
			button.button_pressed = true
			break
	return is_equal_approx(EditorInterface.get_node_3d_translate_snap(), 0.1) and EditorInterface.is_node_3d_snap_enabled()
