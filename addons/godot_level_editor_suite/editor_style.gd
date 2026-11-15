@tool
extends RefCounted
## Editor-only visual primitives. Never change authored resources or graph behavior.
const BLUE := Color("2563eb")
const NAVY := Color("1e40af")
const BACKGROUND := Color("f3f5f9")
const PAPER := Color("ffffff")
const PANEL := Color("f8fafc")
const INK := Color("243247")
const MUTED := Color("738196")
const BORDER := Color("dce3ed")
const TINT := Color("eaf1ff")
const DANGER := Color("b93843")
static func box(color: Color, radius := 6, margin := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style
static func bordered(color: Color, border := BORDER, radius := 6, margin := 8) -> StyleBoxFlat:
	var style := box(color, radius, margin)
	style.border_color = border
	style.set_border_width_all(1)
	return style
static func theme() -> Theme:
	var result := Theme.new()
	result.merge_with(EditorInterface.get_editor_theme())
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"])
	result.default_font = font
	result.default_font_size = 15
	for type in ["Button", "Label", "RichTextLabel", "TooltipLabel", "LineEdit", "OptionButton", "MenuButton", "Tree", "ItemList", "TabBar", "PopupMenu", "TextEdit", "GraphNode", "SpinBox", "CheckBox", "CheckButton"]:
		result.set_font("font", type, font)
		result.set_font_size("font_size", type, 15)
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			result.set_color(state, type, INK)
		result.set_color("font_disabled_color", type, MUTED)
	result.set_font_size("title_font_size", "GraphNode", 16)
	for type in ["VBoxContainer", "HBoxContainer"]: result.set_constant("separation", type, 10)
	for type in ["HFlowContainer", "GridContainer"]:
		result.set_constant("h_separation", type, 10)
		result.set_constant("v_separation", type, 10)
	for type in ["Button", "OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var fill := PAPER
			if state == "hover": fill = PANEL
			if state in ["pressed", "hover_pressed"]: fill = TINT
			if state == "disabled": fill = BACKGROUND
			var surface := bordered(fill, BLUE if state in ["pressed", "hover_pressed"] else BORDER, 6, 8)
			surface.content_margin_left = 12
			surface.content_margin_right = 12
			result.set_stylebox(state, type, surface)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]: result.set_color(state, type, INK)
		result.set_stylebox("focus", type, bordered(Color.TRANSPARENT, BLUE, 6, 0))
	result.set_type_variation("PrimaryButton", "Button")
	result.set_type_variation("DangerButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill := NAVY if state in ["pressed", "hover_pressed"] else BLUE.lightened(0.08) if state == "hover" else BLUE
		if state == "disabled": fill = BORDER
		result.set_stylebox(state, "PrimaryButton", box(fill, 6, 10))
		result.set_stylebox(state, "DangerButton", bordered(Color("fff0f1") if state != "normal" else PAPER, Color("f0d5d8"), 6, 10))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		result.set_color(state, "PrimaryButton", Color.WHITE)
		result.set_color(state, "DangerButton", DANGER)
	for type in ["LineEdit", "TextEdit"]:
		for state in ["normal", "read_only"]: result.set_stylebox(state, type, bordered(PAPER if state == "normal" else PANEL))
		result.set_stylebox("focus", type, bordered(Color.TRANSPARENT, BLUE))
		result.set_color("font_uneditable_color", type, MUTED)
		result.set_color("font_readonly_color", type, MUTED)
		result.set_color("font_placeholder_color", type, MUTED)
		result.set_color("caret_color", type, BLUE)
		result.set_color("selection_color", type, TINT)
		result.set_color("font_selected_color", type, INK)
	for type in ["Tree", "ItemList"]:
		result.set_stylebox("panel", type, bordered(PAPER, BORDER, 8, 8))
		for state in ["selected", "selected_focus", "hovered"]: result.set_stylebox(state, type, box(TINT if state != "hovered" else PANEL, 4, 4))
		result.set_color("font_selected_color", type, NAVY)
		result.set_color("guide_color", type, BORDER)
		result.set_color("children_hl_line_color", type, BORDER)
		result.set_color("relationship_line_color", type, BORDER)
		result.set_constant("v_separation", type, 10)
		result.set_constant("h_separation", type, 10)
	for state in ["title_button_normal", "title_button_hover", "title_button_pressed"]:
		result.set_stylebox(state, "Tree", box(PANEL, 0, 10))
	result.set_color("title_button_color", "Tree", MUTED)
	result.set_color("title_button_hover_color", "Tree", INK)
	result.set_color("title_button_pressed_color", "Tree", BLUE)
	for type in ["PopupMenu", "PopupPanel", "TooltipPanel", "AcceptDialog"]:
		result.set_stylebox("panel", type, bordered(PAPER, BORDER, 8, 12))
	result.set_stylebox("hover", "PopupMenu", box(TINT, 4, 8))
	result.set_color("font_hover_color", "PopupMenu", BLUE)
	result.set_color("font_color", "TooltipLabel", INK)
	for type in ["TabContainer", "TabBar"]:
		result.set_stylebox("panel", type, bordered(PAPER, BORDER, 8, 12))
		for state in ["tab_unselected", "tab_hovered", "tab_selected"]:
			result.set_stylebox(state, type, box(PAPER if state == "tab_selected" else BACKGROUND, 6, 10))
		result.set_color("font_selected_color", type, BLUE)
		result.set_color("font_unselected_color", type, MUTED)
		result.set_color("font_hovered_color", type, INK)
	for type in ["HScrollBar", "VScrollBar"]:
		result.set_stylebox("scroll", type, box(BACKGROUND, 4, 3))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type, box(Color("c3ccda") if state == "grabber" else MUTED, 4, 4))
	for type in ["HSeparator", "VSeparator"]: result.set_stylebox("separator", type, box(BORDER, 0, 0))
	return result
static func navigation(button: Button, height := 42, primary := true) -> void:
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(96 if primary else 100, height)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override("font_size", 16 if primary else 14)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var active: bool = state in ["pressed", "hover_pressed"]
		var surface := box(BLUE if primary and active else PANEL if state == "hover" else Color.TRANSPARENT, 6 if primary else 0, 10)
		if not primary and active:
			surface.border_color = BLUE
			surface.border_width_bottom = 2
		button.add_theme_stylebox_override(state, surface)
		var ink := (Color.WHITE if active else INK) if primary else (BLUE if active else MUTED)
		button.add_theme_color_override("font_" + state + "_color" if state != "normal" else "font_color", ink)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]: button.add_theme_color_override(state, BLUE if state == "icon_pressed_color" else MUTED)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("navigation_primary", primary)
	if primary:
		var regular := SystemFont.new()
		regular.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"])
		var bold := regular.duplicate() as SystemFont
		bold.font_weight = 700
		button.set_meta("navigation_regular_font", regular)
		button.set_meta("navigation_bold_font", bold)
		button.add_theme_font_override("font", regular)
	button.visibility_changed.connect(func():
		if not button.is_visible_in_tree(): _reset_navigation_motion(button))
static func _stop_motion(control: Control, key: String) -> void:
	var previous: Tween = control.get_meta(key) if control.has_meta(key) else null
	if previous != null and previous.is_valid(): previous.kill()
static func _reset_navigation_motion(button: Button) -> void:
	_stop_motion(button, "navigation_tween")
	var primary: bool = button.get_meta("navigation_primary", true)
	for state in ["pressed", "hover_pressed"]:
		var surface := button.get_theme_stylebox(state) as StyleBoxFlat
		if primary: surface.bg_color = BLUE
		else: surface.border_color = BLUE
		surface.shadow_color = Color.TRANSPARENT
		surface.shadow_size = 0
static func select_navigation(button: Button, selected: bool) -> void:
	var previous: bool = button.get_meta("navigation_selected", false)
	button.set_pressed_no_signal(selected)
	button.set_meta("navigation_selected", selected)
	var primary: bool = button.get_meta("navigation_primary", true)
	if primary: button.add_theme_font_override("font", button.get_meta("navigation_bold_font" if selected else "navigation_regular_font"))
	if previous == selected: return
	_reset_navigation_motion(button)
	if not selected or not button.is_visible_in_tree(): return
	var tween := button.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	button.set_meta("navigation_tween", tween)
	for state in ["pressed", "hover_pressed"]:
		var surface := button.get_theme_stylebox(state) as StyleBoxFlat
		if primary:
			surface.bg_color = Color(BLUE, 0.72)
			surface.shadow_color = Color(BLUE, 0.16)
			surface.shadow_size = 5
			tween.tween_property(surface, "bg_color", BLUE, 0.16)
			tween.tween_property(surface, "shadow_color", Color.TRANSPARENT, 0.22)
			tween.tween_property(surface, "shadow_size", 0, 0.22)
		else:
			surface.border_color = Color(BLUE, 0.15)
			tween.tween_property(surface, "border_color", BLUE, 0.18)
static func tab_motion(tabs: TabContainer) -> void:
	var callback := _reveal_tab.bind(tabs)
	if not tabs.tab_changed.is_connected(callback): tabs.tab_changed.connect(callback)
static func _reveal_tab(index: int, tabs: TabContainer) -> void:
	if index >= 0: reveal(tabs.get_tab_control(index))
static func _graph_selection_motion(node: Node) -> void:
	if not node is GraphNode: return
	selection_glow(node)
static func selection_glow(control: Control) -> void:
	# Animate only a private style copy; never add graph children or alter ports.
	_stop_motion(control, "selection_glow_tween")
	var surface := control.get_theme_stylebox("panel_selected").duplicate() as StyleBoxFlat
	control.add_theme_stylebox_override("panel_selected", surface)
	if not control.is_visible_in_tree(): return
	surface.shadow_color = Color(surface.border_color, 0.22)
	surface.shadow_size = 9
	var tween := control.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(surface, "shadow_color", Color.TRANSPARENT, 0.24)
	tween.tween_property(surface, "shadow_size", 0, 0.24)
	control.set_meta("selection_glow_tween", tween)
static func graph_canvas(graph: GraphEdit) -> void:
	# Grid appearance only: leave snapping, zoom, layout and connections untouched.
	graph.show_grid = true
	graph.grid_pattern = GraphEdit.GRID_PATTERN_LINES
	graph.add_theme_stylebox_override("panel", bordered(PANEL, Color("cdd7e5"), 8, 0))
	graph.add_theme_stylebox_override("menu_panel", bordered(PAPER, BORDER, 6, 6))
	graph.add_theme_color_override("grid_minor", Color("e2e8f1"))
	graph.add_theme_color_override("grid_major", Color("c9d4e4"))
	graph.add_theme_color_override("selection_fill", Color(0.145, 0.388, 0.922, 0.10))
	graph.add_theme_color_override("selection_stroke", BLUE)
	graph.connection_lines_thickness = 2.0
	if not graph.node_selected.is_connected(_graph_selection_motion): graph.node_selected.connect(_graph_selection_motion)
	for control in graph.get_menu_hbox().find_children("*", "Button", true, false):
		var button := control as Button
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 18)
		button.custom_minimum_size = Vector2(28, 28)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			button.add_theme_stylebox_override(state, box(TINT if state in ["pressed", "hover_pressed"] else Color.TRANSPARENT, 4, 5))
static func workspace(root: Control) -> void:
	for child in root.find_children("*", "GraphEdit", true, false): graph_canvas(child)
	# Adopted panels may have built a dark table override before joining this window.
	for child in root.find_children("*", "Tree", true, false): child.add_theme_stylebox_override("panel", bordered(PAPER, BORDER, 8, 8))
	for child in root.find_children("*", "TabContainer", true, false): tab_motion(child)
static func reveal(control: Control) -> void:
	if not control.is_visible_in_tree(): return
	if control.has_meta("reveal_tween"):
		var previous: Tween = control.get_meta("reveal_tween")
		if previous != null and previous.is_valid(): previous.kill()
	control.modulate.a = 0.7
	var tween := control.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, 0.14)
	control.set_meta("reveal_tween", tween)
