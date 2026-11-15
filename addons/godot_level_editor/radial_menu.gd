@tool
extends Control
const CATALOG := preload("res://addons/godot_level_editor/asset_catalog.gd")
const ITEM := preload("res://addons/godot_level_editor/palette_item.gd")
const STYLE := preload("res://addons/godot_level_editor_suite/editor_style.gd")
const UI_REVISION := 3
const LABELS := ["玩家\n出生点", "Layout\n白盒", "Room", "机关", "NPC", "最近\n使用"]
const ICONS := ["Marker3D", "CSGBox3D", "Area3D", "Tools", "CharacterBody3D", "History"]
var tool: RefCounted
var categories: Array = CATALOG.CATEGORIES + [CATALOG.RECENT]
var category := 1
var hovered := -1
var page := "main"
var lifetime_index := 0
var entries: Array[Dictionary] = []
var indices := {}
var wheel_center := Vector2.ZERO
var radius := 180.0
var closing := false
var interaction_enabled := true
var footer: VBoxContainer
var all_button: Button
var back_button: Button
var preview: Control
var counter: Label
var chooser: PanelContainer
var search: LineEdit
var grid: HFlowContainer
var chooser_title: Label
var ui_scale := 1.0
var _weights: Array[float] = []
var _transition: Tween
var _hover_tween: Tween
var _chooser_tween: Tween

func _ready() -> void:
	name = "QuickAddWheel"
	set_meta("quick_add_ui_revision", UI_REVISION)
	ui_scale = EditorInterface.get_editor_scale()
	theme = STYLE.theme()
	for type in ["Label", "Button", "LineEdit", "PopupMenu"]: theme.set_font_size("font_size", type, roundi(15 * ui_scale))
	mouse_filter = Control.MOUSE_FILTER_STOP; focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	footer = VBoxContainer.new(); add_child(footer)
	all_button = Button.new(); footer.add_child(all_button); all_button.pressed.connect(show_catalog)
	back_button = Button.new(); back_button.text = "返回"; back_button.pressed.connect(go_back); add_child(back_button)
	counter = Label.new(); counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; counter.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(counter)
	_build_chooser()
	resized.connect(_layout)
	hide()

func is_open() -> bool:
	return visible and not closing

func open_at(point: Vector2) -> void:
	closing = false; interaction_enabled = true; mouse_filter = Control.MOUSE_FILTER_STOP
	page = "main"; hovered = -1; chooser.hide(); footer.show(); counter.show()
	wheel_center = point
	show(); grab_focus()
	select_category(category)
	_layout()
	_animate_root(0.0, 0.94, 0.16)

func close_menu(animated := true) -> void:
	if not visible: return
	if animated and closing: return
	if is_instance_valid(_transition): _transition.kill()
	if is_instance_valid(_hover_tween): _hover_tween.kill()
	if not animated:
		hide(); closing = false; scale = Vector2.ONE; modulate.a = 1
		return
	closing = true; mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(self, "modulate:a", 0.0, 0.1)
	_transition.tween_property(self, "scale", Vector2.ONE * 0.96, 0.1)
	_transition.finished.connect(func(): hide(); closing = false; scale = Vector2.ONE)

func _animate_root(alpha: float, start_scale: float, duration: float) -> void:
	if is_instance_valid(_transition): _transition.kill()
	pivot_offset = wheel_center; modulate.a = alpha; scale = Vector2.ONE * start_scale
	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(self, "modulate:a", 1.0, duration)
	_transition.tween_property(self, "scale", Vector2.ONE, duration)

func _layout() -> void:
	radius = maxf(90, minf(180.0 * ui_scale, minf(size.x * 0.46, (size.y - 60 * ui_scale) * 0.46)))
	wheel_center = wheel_center.clamp(Vector2(radius + 8, radius + 8), Vector2(maxf(radius + 8, size.x - radius - 8), maxf(radius + 8, size.y - radius - 58 * ui_scale)))
	pivot_offset = wheel_center
	footer.size.x = minf(240 * ui_scale, size.x - 16)
	footer.position = Vector2(wheel_center.x - footer.size.x * 0.5, wheel_center.y + radius + 8)
	counter.position = wheel_center + Vector2(-65 * ui_scale, radius * 0.35); counter.size = Vector2(130, 24) * ui_scale
	back_button.size = Vector2(78, 30) * ui_scale; back_button.position = wheel_center + Vector2(-39 * ui_scale, radius * 0.31)
	if is_instance_valid(preview):
		preview.size = Vector2(minf(130 * ui_scale, radius * 0.8), minf(100 * ui_scale, radius * 0.63))
		preview.position = wheel_center - preview.size * 0.5 - Vector2(0, 8 * ui_scale)
	chooser.size = Vector2(minf(660 * ui_scale, size.x - 24), minf(490 * ui_scale, size.y - 24))
	chooser.position = (size - chooser.size) * 0.5; chooser.pivot_offset = chooser.size * 0.5
	queue_redraw()

func select_category(index: int) -> void:
	page = "main"; category = posmod(index, categories.size())
	entries = CATALOG.recent_assets(tool.recent) if categories[category] == CATALOG.RECENT else CATALOG.assets(categories[category])
	_reset_weights(6, category)
	_refresh_preview()

func current_asset() -> Dictionary:
	if page == "scope": return CATALOG.template(categories[category], "level" if lifetime_index == 0 else "task")
	if not CATALOG.entity_kind(categories[category]).is_empty(): return CATALOG.template(categories[category], "level")
	return {} if entries.is_empty() else entries[posmod(int(indices.get(category, 0)), entries.size())]

func cycle(direction: int) -> void:
	if page == "scope": lifetime_index = posmod(lifetime_index + direction, 2); _animate_hover(lifetime_index); _refresh_preview(); return
	if entries.is_empty() or not CATALOG.entity_kind(categories[category]).is_empty(): return
	indices[category] = posmod(int(indices.get(category, 0)) + direction, entries.size())
	_refresh_preview()

func hover_at(point: Vector2) -> void:
	tool.last_mouse = point
	var delta := point - wheel_center
	if delta.length() > radius + 4 * ui_scale: return
	var count := 2 if page == "scope" else 6
	var next := -1 if delta.length() < radius * 0.53 else posmod(int(floor((delta.angle() + PI * 0.5 + PI / count) / (TAU / count))), count)
	if next == hovered: return
	hovered = next
	if hovered >= 0:
		if page == "scope": lifetime_index = hovered; _refresh_preview()
		elif hovered != category:
			category = hovered
			entries = CATALOG.recent_assets(tool.recent) if categories[category] == CATALOG.RECENT else CATALOG.assets(categories[category])
			_refresh_preview()
	_animate_hover(hovered)

func open_submenu() -> void:
	if closing or CATALOG.entity_kind(categories[category]).is_empty(): return
	page = "scope"; lifetime_index = 0; hovered = -1
	_reset_weights(2, 0); _refresh_preview(); _animate_root(0.65, 0.97, 0.15)

func confirm_selection(from_mouse := false) -> void:
	if closing: return
	if page == "main" and not CATALOG.entity_kind(categories[category]).is_empty(): open_submenu(); return
	var asset := current_asset()
	if not asset.is_empty(): tool.begin_asset(asset, from_mouse)

func go_back() -> void:
	if closing: return
	if chooser.visible:
		chooser.hide(); footer.show(); preview.show(); _refresh_preview()
	else: select_category(category)
	grab_focus(); _animate_root(0.7, 0.97, 0.13)

func _reset_weights(count: int, selected: int) -> void:
	if is_instance_valid(_hover_tween): _hover_tween.kill()
	_weights.resize(count); _weights.fill(0.0)
	if selected >= 0: _weights[selected] = 1.0

func _animate_hover(index: int) -> void:
	if is_instance_valid(_hover_tween): _hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in _weights.size(): _hover_tween.tween_method(_set_weight.bind(i), _weights[i], 1.0 if i == index else 0.0, 0.11)

func _set_weight(value: float, index: int) -> void:
	if index < _weights.size(): _weights[index] = value; queue_redraw()

func _refresh_preview() -> void:
	if is_instance_valid(preview): preview.free()
	var asset := current_asset()
	if not asset.is_empty() and not str(asset.kind).is_empty():
		preview = ITEM.new(); preview.kind = asset.kind; preview.title = asset.title; preview.title_font_size = roundi(14 * ui_scale)
	else:
		var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 4); preview = box
		var texture := TextureRect.new(); texture.custom_minimum_size = Vector2(56, 56) * ui_scale; texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; box.add_child(texture)
		var icon_index := category if asset.is_empty() else CATALOG.CATEGORIES.find(asset.category)
		texture.texture = EditorInterface.get_base_control().get_theme_icon(ICONS[maxi(icon_index, 0)], "EditorIcons")
		if not asset.is_empty() and not asset.get("template", false): EditorInterface.get_resource_previewer().queue_resource_preview(asset.path, self, "_resource_preview", texture.get_instance_id())
		var label := Label.new(); label.text = "暂无记录" if asset.is_empty() else str(asset.title)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; box.add_child(label)
	add_child(preview); _ignore_mouse(preview); preview.visible = not chooser.visible
	var entity_type := not CATALOG.entity_kind(categories[category]).is_empty()
	counter.visible = page == "main" and not entity_type and not chooser.visible
	counter.text = "" if entries.is_empty() else "%d / %d" % [posmod(int(indices.get(category, 0)), entries.size()) + 1, entries.size()]
	back_button.visible = page == "scope" and not chooser.visible
	all_button.disabled = entries.is_empty() and not entity_type
	all_button.text = "选择类型" if page == "main" and entity_type else "已有素材" if page == "scope" else "全部 · " + str(categories[category])
	_layout()

func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)

func _resource_preview(_path: String, texture: Texture2D, _small: Texture2D, object_id: Variant) -> void:
	if texture != null and is_instance_id_valid(int(object_id)):
		var target := instance_from_id(int(object_id)) as TextureRect
		if target != null: target.texture = texture

func _draw() -> void:
	if chooser == null or chooser.visible or _weights.is_empty(): return
	var inner := radius * 0.53
	draw_circle(wheel_center + Vector2(0, 3), radius + 3, Color(0.02, 0.05, 0.1, 0.12))
	draw_circle(wheel_center, radius, Color.WHITE)
	var font := get_theme_font("font", "Label")
	var font_size := maxi(12, roundi(14 * ui_scale))
	var count := 2 if page == "scope" else 6
	for i in count:
		var weight := _weights[i]
		var angle := -PI * 0.5 + i * TAU / count
		var outer := radius + weight * 3 * ui_scale
		var polygon := PackedVector2Array()
		for j in 49: polygon.append(wheel_center + Vector2.from_angle(angle - PI / count + 0.012 + j * (TAU / count - 0.024) / 48) * outer)
		for j in range(48, -1, -1): polygon.append(wheel_center + Vector2.from_angle(angle - PI / count + 0.012 + j * (TAU / count - 0.024) / 48) * inner)
		draw_colored_polygon(polygon, Color("edf2f7").lerp(Color("2563eb"), weight))
		var point := wheel_center + Vector2.from_angle(angle) * (radius * 0.76 + weight * 2 * ui_scale)
		var icon_name: String = ICONS[category] if page == "scope" else ICONS[i]
		var icon := EditorInterface.get_base_control().get_theme_icon(icon_name, "EditorIcons")
		draw_texture_rect(icon, Rect2(point + Vector2(-11, -30) * ui_scale, Vector2(22, 22) * ui_scale), false)
		var text: String = LABELS[i]
		if page == "scope": text = ("关卡常驻\n" if i == 0 else "任务\n") + {"npc": "NPC", "mechanism": "机关", "room": "Room"}[CATALOG.entity_kind(categories[category])]
		var lines := text.split("\n")
		for line in lines.size():
			var width := font.get_string_size(lines[line], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, point + Vector2(-width * 0.5, 10 * ui_scale + line * (font_size + 3 * ui_scale)), lines[line], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("263b53").lerp(Color.WHITE, weight))
	draw_circle(wheel_center, inner - 2, Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	if closing or not interaction_enabled: return
	if chooser.visible:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT: go_back()
		return
	if event is InputEventMouseMotion: hover_at(event.position)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: cycle(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			hover_at(event.position)
			if event.position.distance_to(wheel_center) <= radius: confirm_selection(true)
			else: tool.cancel(true)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if page == "scope": go_back()
			else: tool.cancel(true)
	accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and tool._selection_click:
		tool._selection_click = false; get_viewport().set_input_as_handled(); return
	if not visible: return
	if tool.is_trigger(event):
		if event.is_pressed(): tool.toggle_wheel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		tool.cancel(true); get_viewport().set_input_as_handled()
	elif is_open() and interaction_enabled and not chooser.visible and event is InputEventMouse:
		# Native editor overlays and gizmos may receive GUI motion before a plugin
		# Control. Route the ring in window coordinates first, including its tween.
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if back_button.visible and back_button.get_global_rect().has_point(event.position): return
		if point.distance_to(wheel_center) > radius + 4 * ui_scale: return
		if event is InputEventMouseMotion:
			hover_at(point); get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT: hover_at(point); confirm_selection(true)
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: cycle(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if page == "scope": go_back()
				else: tool.cancel(true)
			get_viewport().set_input_as_handled()

func _build_chooser() -> void:
	chooser = PanelContainer.new(); chooser.add_theme_stylebox_override("panel", STYLE.box(Color.WHITE, 8, 12)); add_child(chooser)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10); chooser.add_child(column)
	var row := HBoxContainer.new(); column.add_child(row)
	chooser_title = Label.new(); chooser_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(chooser_title)
	var back := Button.new(); back.text = "返回轮盘"; row.add_child(back); back.pressed.connect(go_back)
	search = LineEdit.new(); search.placeholder_text = "搜索素材"; column.add_child(search)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(scroll)
	grid = HFlowContainer.new(); grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(grid)
	search.text_changed.connect(func(value: String):
		for child in grid.get_children(): child.visible = str(child.get_meta("asset_title", "")).to_lower().contains(value.to_lower()))
	chooser.hide()

func show_catalog() -> void:
	if closing: return
	if page == "main" and not CATALOG.entity_kind(categories[category]).is_empty(): open_submenu(); return
	for child in grid.get_children(): child.free()
	chooser_title.text = str(current_asset().get("title", categories[category])) if page == "scope" else str(categories[category])
	var assets: Array[Dictionary] = CATALOG.assets(categories[category]) if page == "scope" else entries
	for source in assets:
		var asset := source.duplicate()
		if page == "scope": asset.entity_kind = CATALOG.entity_kind(categories[category]); asset.lifetime = "level" if lifetime_index == 0 else "task"
		if not str(asset.kind).is_empty():
			var card := ITEM.new(); card.kind = asset.kind; card.title = asset.title; card.title_font_size = roundi(14 * ui_scale)
			card.custom_minimum_size = Vector2(140, 108) * ui_scale; card.set_meta("asset_title", asset.title); grid.add_child(card)
			card.chosen.connect(func(_kind: String): tool.begin_asset(asset, true))
		else:
			var button := Button.new(); button.text = asset.title; button.tooltip_text = asset.path; button.custom_minimum_size = Vector2(140, 108) * ui_scale
			button.icon = EditorInterface.get_base_control().get_theme_icon(ICONS[maxi(CATALOG.CATEGORIES.find(asset.category), 0)], "EditorIcons")
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP; button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", roundi(60 * ui_scale)); button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.set_meta("asset_title", asset.title); grid.add_child(button)
			EditorInterface.get_resource_previewer().queue_resource_preview(asset.path, self, "_catalog_preview", button.get_instance_id())
			button.pressed.connect(func(): tool.begin_asset(asset))
	search.clear()
	for child in grid.get_children(): child.show()
	footer.hide(); preview.hide(); counter.hide(); back_button.hide(); chooser.show(); search.grab_focus(); _layout()
	if is_instance_valid(_chooser_tween): _chooser_tween.kill()
	chooser.modulate.a = 0; chooser.scale = Vector2.ONE * 0.96
	_chooser_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_chooser_tween.tween_property(chooser, "modulate:a", 1.0, 0.15); _chooser_tween.tween_property(chooser, "scale", Vector2.ONE, 0.15)

func _catalog_preview(_path: String, texture: Texture2D, _small: Texture2D, object_id: Variant) -> void:
	if texture != null and is_instance_id_valid(int(object_id)):
		var button := instance_from_id(int(object_id)) as Button
		if button != null: button.icon = texture
