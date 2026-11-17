@tool
extends RefCounted
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor/node_presentation.gd")
const KEYS := ["", "trigger", "action", "condition", "state", "data", "flow"]
const NAMES := ["全部", "触发", "动作", "判断", "状态", "数据", "流程"]
var panel: Control
var category_buttons: Array[Button] = []
var empty: Label
var icons: Dictionary = {}

func build(owner_panel: Control, dialog: ConfirmationDialog) -> void:
	panel = owner_panel
	dialog.title = "添加节点"
	dialog.min_size = Vector2i(760, 540)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	dialog.add_child(body)
	var categories := VBoxContainer.new()
	categories.custom_minimum_size.x = 135
	categories.add_theme_constant_override("separation", 5)
	body.add_child(categories)
	var group := ButtonGroup.new()
	# Preserve the programmatic category selection API without the extra dropdown.
	panel.node_category = OptionButton.new()
	panel.node_category.hide()
	categories.add_child(panel.node_category)
	for i in KEYS.size():
		panel.node_category.add_item(NAMES[i])
		var button := Button.new()
		button.text = NAMES[i]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 40
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, Color.WHITE)
		if i > 0: button.icon = _icon(KEYS[i])
		categories.add_child(button)
		category_buttons.append(button)
		button.pressed.connect(func(): panel.node_category.select(i); panel._filter_choices())
	var results := VBoxContainer.new()
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(results)
	panel.search = LineEdit.new()
	panel.search.placeholder_text = "搜索节点（中文 / English）"
	panel.search.clear_button_enabled = true
	results.add_child(panel.search)
	panel.choices = ItemList.new()
	panel.choices.custom_minimum_size = Vector2(520, 350)
	panel.choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.choices.add_theme_constant_override("v_separation", 8)
	panel.choices.tooltip_text = "双击节点添加，或选择后点击确定"
	results.add_child(panel.choices)
	empty = Label.new()
	empty.text = "没有符合条件的节点"
	empty.hide()
	results.add_child(empty)
	panel.node_category.item_selected.connect(func(_i: int): panel._filter_choices())
	panel.search.text_changed.connect(func(_text: String): panel._filter_choices())
	panel.search.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode == KEY_DOWN and panel.choices.item_count > 0:
			panel.choices.grab_focus()
			panel.get_viewport().set_input_as_handled())
	dialog.confirmed.connect(panel._add_choice)
	panel.choices.item_activated.connect(func(_i: int): panel._add_choice(); dialog.hide())

func _icon(key: String) -> Texture2D:
	if not icons.has(key):
		var gradient := Gradient.new()
		var color: Color = STYLE.CATEGORIES[key].color
		gradient.colors = PackedColorArray([color, color])
		var texture := GradientTexture2D.new()
		texture.width = 10
		texture.height = 10
		texture.gradient = gradient
		icons[key] = texture
	return icons[key]

func filter() -> void:
	if panel.graph == null: return
	panel.choices.clear()
	var groups := {}
	for key in KEYS: groups[key] = []
	var query: String = panel.search.text.strip_edges().to_lower()
	var labels := GRAPH.labels()
	for kind in labels:
		if (panel.graph.graph_kind == "topology") != (kind == "port"): continue
		if GRAPH.TASK_NODES.DEFINITIONS.has(kind) and not panel.graph.has_method("load_dialogue"): continue
		if not panel._can_offer_node(kind): continue
		var searchable := str(labels[kind]) + " " + str(kind) + " " + GRAPH.TASK_NODES.english_name(kind)
		if not query.is_empty() and not searchable.to_lower().contains(query): continue
		groups[STYLE.category_key(kind)].append(kind)
	var total := 0
	for key in KEYS:
		if not str(key).is_empty(): total += groups[key].size()
	var selected: int = panel.node_category.selected
	if selected < 0: selected = 0
	for i in category_buttons.size():
		category_buttons[i].text = NAMES[i] + "  " + str(total if i == 0 else groups[KEYS[i]].size())
		category_buttons[i].button_pressed = i == selected
	var wanted: String = KEYS[selected]
	var first := -1
	for key in KEYS:
		if str(key).is_empty() or (not wanted.is_empty() and wanted != key) or groups[key].is_empty(): continue
		var color: Color = STYLE.CATEGORIES[key].color
		if wanted.is_empty() and query.is_empty():
			panel.choices.add_item(NAMES[KEYS.find(key)] + "  " + str(groups[key].size()))
			var header: int = panel.choices.item_count - 1
			panel.choices.set_item_metadata(header, "")
			panel.choices.set_item_selectable(header, false)
			panel.choices.set_item_custom_fg_color(header, color)
			panel.choices.set_item_custom_bg_color(header, Color.WHITE.lerp(color, 0.1))
		for kind in groups[key]:
			panel.choices.add_item(str(labels[kind]), _icon(key))
			var index: int = panel.choices.item_count - 1
			if first < 0: first = index
			panel.choices.set_item_metadata(index, kind)
			panel.choices.set_item_tooltip(index, str(labels[kind]) + "\n" + GRAPH.TASK_NODES.english_name(kind) + "\n" + str(STYLE.HINTS[key]))
	empty.visible = first < 0
	panel.picker.get_ok_button().disabled = first < 0
	if first >= 0: panel.choices.select(first)
