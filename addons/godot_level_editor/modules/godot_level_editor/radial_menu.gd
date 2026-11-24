@tool
extends Control
const CATALOG := preload("res://addons/godot_level_editor/modules/godot_level_editor/asset_catalog.gd")
const THUMBNAIL := preload("res://addons/godot_level_editor/modules/godot_level_editor/radial_thumbnail.gd")
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")
const CARD := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_card.gd")
const UI_REVISION := 9
const PAGE_SIZE := 8
const INNER_RATIO := 0.48
const LABELS := ["玩家\n出生点", "白盒\n体块", "触发\n区域", "机关", "NPC", "载具", "最近\n使用", "地形"]
const ICONS := ["Marker3D", "CSGBox3D", "Area3D", "Tools", "CharacterBody3D", "VehicleBody3D", "History", "MeshInstance3D"]
var tool: RefCounted
var categories: Array = CATALOG.CATEGORIES + [CATALOG.RECENT, "地形"]
var category := 1
var hovered := -1
var page := "main"
var page_index := 0
var lifetime_index := 0
var entries: Array[Dictionary] = []
var indices := {}
var wheel_center := Vector2.ZERO
var radius := 180.0
var closing := false
var interaction_enabled := true
var counter: Label
var chooser: PanelContainer
var search: LineEdit
var grid: HFlowContainer
var chooser_title: Label
var ui_scale := 1.0
var sector_thumbnails: Array[Control] = []
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
	counter = Label.new(); counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; counter.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(counter)
	_build_chooser()
	resized.connect(_layout)
	hide()

func is_open() -> bool:
	return visible and not closing

func open_at(point: Vector2) -> void:
	closing = false; interaction_enabled = true; mouse_filter = Control.MOUSE_FILTER_STOP
	chooser.hide(); wheel_center = point
	show(); grab_focus(); select_category(category)
	_animate_root(0.0, 0.94, 0.16)

func close_menu(animated := true) -> void:
	if not visible or (animated and closing): return
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
	radius = maxf(90, minf(180.0 * ui_scale, minf(size.x * 0.46, (size.y - 28 * ui_scale) * 0.46)))
	var margin := Vector2(radius + 8, radius + 8)
	wheel_center = wheel_center.clamp(margin, Vector2(maxf(margin.x, size.x - margin.x), maxf(margin.y, size.y - radius - 28 * ui_scale)))
	pivot_offset = wheel_center
	counter.position = wheel_center + Vector2(-65 * ui_scale, radius + 4 * ui_scale); counter.size = Vector2(130, 24) * ui_scale
	chooser.size = Vector2(minf(660 * ui_scale, size.x - 24), minf(490 * ui_scale, size.y - 24))
	chooser.position = (size - chooser.size) * 0.5; chooser.pivot_offset = chooser.size * 0.5
	_layout_thumbnails(); queue_redraw()

func select_category(index: int) -> void:
	page = "main"; category = posmod(index, categories.size()); hovered = -1; page_index = 0
	entries = CATALOG.recent_assets(tool.recent) if categories[category] == CATALOG.RECENT else CATALOG.assets(categories[category])
	_reset_weights(categories.size(), category); _refresh_page()

func sector_count() -> int:
	return (2 if CATALOG.entity_kind(categories[category]) == "room" else 3) if page == "scope" else PAGE_SIZE if page == "assets" else categories.size()

func page_count() -> int:
	return maxi(1, ceili(float(entries.size()) / PAGE_SIZE))

func current_asset() -> Dictionary:
	if page == "scope": return {} if hovered == 2 else CATALOG.template(categories[category], "level" if lifetime_index == 0 else "task")
	if page == "main" and not CATALOG.entity_kind(categories[category]).is_empty(): return CATALOG.template(categories[category], "level")
	var index := int(indices.get(category, 0))
	return entries[index] if index >= 0 and index < entries.size() else {}

func cycle(direction: int) -> void:
	if page != "assets" or page_count() <= 1: return
	page_index = posmod(page_index + direction, page_count())
	indices[category] = page_index * PAGE_SIZE + maxi(hovered, 0)
	_reset_weights(PAGE_SIZE, hovered if not current_asset().is_empty() else -1)
	_refresh_page(); _animate_root(0.7, 0.98, 0.13)

func hover_at(point: Vector2) -> void:
	tool.last_mouse = point
	var delta := point - wheel_center
	if delta.length() > radius + 4 * ui_scale: return
	var count := sector_count()
	var next := -1 if delta.length() < radius * INNER_RATIO else posmod(int(floor((delta.angle() + PI * 0.5 + PI / count) / (TAU / count))), count)
	if next == hovered: return
	hovered = next
	if hovered >= 0:
		if page == "scope" and hovered < 2: lifetime_index = hovered
		elif page == "assets": indices[category] = page_index * PAGE_SIZE + hovered
		elif page == "main" and hovered != category:
			category = hovered
			entries = CATALOG.recent_assets(tool.recent) if categories[category] == CATALOG.RECENT else CATALOG.assets(categories[category])
	_animate_hover(hovered if page != "assets" or not current_asset().is_empty() else -1)

func open_submenu() -> void:
	if closing: return
	if not CATALOG.entity_kind(categories[category]).is_empty():
		page = "scope"; lifetime_index = 0; hovered = -1; _reset_weights(sector_count(), -1)
	else:
		page = "assets"; page_index = 0; hovered = -1; indices[category] = 0; _reset_weights(PAGE_SIZE, -1)
	_refresh_page(); _animate_root(0.65, 0.97, 0.15)

func confirm_selection(from_mouse := false) -> void:
	if closing: return
	if page == "main" and categories[category] == "地形":
		tool.open_terrain(from_mouse)
		return
	if page == "main" and category != 0: open_submenu(); return
	if page == "scope" and hovered == 2: show_catalog(); return
	var asset := current_asset()
	if not asset.is_empty(): tool.begin_asset(asset, from_mouse)

func go_back() -> void:
	if closing: return
	if chooser.visible: chooser.hide(); _refresh_page()
	else: select_category(category)
	grab_focus(); _animate_root(0.7, 0.97, 0.13)

func _reset_weights(count: int, selected: int) -> void:
	if is_instance_valid(_hover_tween): _hover_tween.kill()
	_weights.resize(count); _weights.fill(0.0)
	if selected >= 0 and selected < count: _weights[selected] = 1.0

func _animate_hover(index: int) -> void:
	if is_instance_valid(_hover_tween): _hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in _weights.size(): _hover_tween.tween_method(_set_weight.bind(i), _weights[i], 1.0 if i == index else 0.0, 0.11)

func _set_weight(value: float, index: int) -> void:
	if index < _weights.size(): _weights[index] = value; _layout_thumbnails(); queue_redraw()

func _refresh_page() -> void:
	for thumbnail in sector_thumbnails: thumbnail.free()
	sector_thumbnails.clear()
	if page == "assets":
		for i in mini(PAGE_SIZE, entries.size() - page_index * PAGE_SIZE):
			var asset: Dictionary = entries[page_index * PAGE_SIZE + i]
			var thumbnail: Control
			if not str(asset.kind).is_empty():
				thumbnail = THUMBNAIL.new(); thumbnail.kind = asset.kind; thumbnail.title = str(asset.title)
			else:
				var texture := TextureRect.new(); texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				texture.texture = EditorInterface.get_base_control().get_theme_icon(ICONS[maxi(CATALOG.CATEGORIES.find(asset.category), 0)], "EditorIcons")
				var saved := CARD.preview_texture(CATALOG.preview_path(asset))
				if saved != null: texture.texture = saved
				else: EditorInterface.get_resource_previewer().queue_resource_preview(asset.path, self, "_resource_preview", texture.get_instance_id())
				thumbnail = texture
			add_child(thumbnail); thumbnail.custom_minimum_size = Vector2.ZERO; _ignore_mouse(thumbnail)
			thumbnail.visible = not chooser.visible; sector_thumbnails.append(thumbnail)
	counter.visible = page == "assets" and page_count() > 1 and not chooser.visible
	counter.text = "%d / %d" % [page_index + 1, page_count()]
	_layout()

func _layout_thumbnails() -> void:
	var content_scale := minf(ui_scale, radius / 180.0)
	for i in sector_thumbnails.size():
		var point := _sector_center(i, PAGE_SIZE)
		var thumbnail := sector_thumbnails[i]
		thumbnail.size = Vector2(54, 44) * content_scale
		thumbnail.position = point - thumbnail.size * 0.5 - Vector2(0, 9 * content_scale)

func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE; node.tooltip_text = ""
	for child in node.get_children(): _ignore_mouse(child)

func _resource_preview(_path: String, texture: Texture2D, _small: Texture2D, object_id: Variant) -> void:
	if texture != null and is_instance_id_valid(int(object_id)):
		var target := instance_from_id(int(object_id)) as TextureRect
		if target != null: target.texture = texture

func _sector_center(index: int, count: int) -> Vector2:
	return wheel_center + Vector2.from_angle(-PI * 0.5 + index * TAU / count) * (radius * 0.75 + _weights[index] * 2 * ui_scale)

func _sector_polygon(index: int, count: int, outer: float) -> PackedVector2Array:
	var angle := -PI * 0.5 + index * TAU / count
	var polygon := PackedVector2Array()
	for j in 49: polygon.append(wheel_center + Vector2.from_angle(angle - PI / count + 0.012 + j * (TAU / count - 0.024) / 48) * outer)
	for j in range(48, -1, -1): polygon.append(wheel_center + Vector2.from_angle(angle - PI / count + 0.012 + j * (TAU / count - 0.024) / 48) * radius * INNER_RATIO)
	return polygon

func _draw() -> void:
	if chooser == null or chooser.visible or _weights.is_empty(): return
	var font := get_theme_font("font", "Label")
	var content_scale := minf(ui_scale, radius / 180.0)
	var font_size := maxi(10, roundi(14 * content_scale))
	var count := sector_count()
	for i in count:
		var weight := _weights[i]
		var enabled := page != "assets" or page_index * PAGE_SIZE + i < entries.size()
		var polygon := _sector_polygon(i, count, radius + weight * 3 * ui_scale)
		var shadow := polygon.duplicate()
		for j in shadow.size(): shadow[j] += Vector2(0, 3 * ui_scale)
		draw_colored_polygon(shadow, Color(0.02, 0.05, 0.1, 0.12))
		draw_colored_polygon(polygon, Color("edf2f7").lerp(Color("2563eb"), weight) if enabled else Color(0.85, 0.89, 0.93, 0.65))
		if not enabled: continue
		var point := _sector_center(i, count)
		var text: String
		if page == "assets": text = str(entries[page_index * PAGE_SIZE + i].title)
		else:
			var icon_name: String = ("Folder" if i == 2 else ICONS[category]) if page == "scope" else ICONS[i]
			var icon := EditorInterface.get_base_control().get_theme_icon(icon_name, "EditorIcons")
			draw_texture_rect(icon, Rect2(point + Vector2(-11, -30) * content_scale, Vector2(22, 22) * content_scale), false)
			text = LABELS[i]
			if page == "scope": text = "已有素材" if i == 2 else ("关卡常驻\n" if i == 0 else "任务\n") + {"npc": "NPC", "mechanism": "机关", "room": "触发区域"}[CATALOG.entity_kind(categories[category])]
		var lines := text.split("\n")
		for line in lines.size():
			var width := minf(font.get_string_size(lines[line], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, radius * 0.47)
			draw_string(font, point + Vector2(-width * 0.5, (23 if page == "assets" else 10) * content_scale + line * (font_size + 3 * content_scale)), lines[line], HORIZONTAL_ALIGNMENT_LEFT, width, font_size, Color("263b53").lerp(Color.WHITE, weight))

func _click_at(point: Vector2) -> void:
	var distance := point.distance_to(wheel_center)
	if distance > radius + 4 * ui_scale: tool.cancel(true)
	elif distance >= radius * INNER_RATIO:
		hover_at(point); confirm_selection(true)

func _back_or_cancel() -> void:
	if page != "main" or chooser.visible: go_back()
	else: tool.cancel(true)

func _gui_input(event: InputEvent) -> void:
	if closing or not interaction_enabled: return
	if chooser.visible:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT: go_back()
		return
	if event is InputEventMouseMotion: hover_at(event.position)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: cycle(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		elif event.button_index == MOUSE_BUTTON_MIDDLE: cycle(1)
		elif event.button_index == MOUSE_BUTTON_LEFT: _click_at(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT: _back_or_cancel()
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
		# Native overlays may intercept GUI motion; route the ring in window
		# coordinates first, including its animated canvas transform.
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if point.distance_to(wheel_center) > radius + 4 * ui_scale: return
		if event is InputEventMouseMotion:
			hover_at(point); get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT: _click_at(point)
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: cycle(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			elif event.button_index == MOUSE_BUTTON_MIDDLE: cycle(1)
			elif event.button_index == MOUSE_BUTTON_RIGHT: _back_or_cancel()
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
	for child in grid.get_children(): child.free()
	chooser_title.text = "已有素材"
	var assets: Array[Dictionary] = CATALOG.assets(categories[category])
	for source in assets:
		var asset := source.duplicate()
		asset.entity_kind = CATALOG.entity_kind(categories[category]); asset.lifetime = "level"
		var button := Button.new(); button.text = asset.title; button.tooltip_text = asset.path; button.custom_minimum_size = Vector2(140, 108) * ui_scale
		button.icon = EditorInterface.get_base_control().get_theme_icon(ICONS[maxi(CATALOG.CATEGORIES.find(asset.category), 0)], "EditorIcons")
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP; button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", roundi(112 * ui_scale)); button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.set_meta("asset_title", asset.title); grid.add_child(button)
		var preview_path := CATALOG.preview_path(asset)
		var saved := CARD.preview_texture(preview_path)
		button.set_meta("editor_preview_path", preview_path)
		if saved != null: button.icon = saved
		else: EditorInterface.get_resource_previewer().queue_resource_preview(asset.path, self, "_catalog_preview", button.get_instance_id())
		button.pressed.connect(func(): tool.begin_asset(asset, true))
	search.clear()
	for child in grid.get_children(): child.show()
	for thumbnail in sector_thumbnails: thumbnail.hide()
	counter.hide(); chooser.show(); search.grab_focus(); _layout()
	if is_instance_valid(_chooser_tween): _chooser_tween.kill()
	chooser.modulate.a = 0; chooser.scale = Vector2.ONE * 0.96
	_chooser_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_chooser_tween.tween_property(chooser, "modulate:a", 1.0, 0.15); _chooser_tween.tween_property(chooser, "scale", Vector2.ONE, 0.15)

func _catalog_preview(_path: String, texture: Texture2D, _small: Texture2D, object_id: Variant) -> void:
	if texture != null and is_instance_id_valid(int(object_id)):
		var button := instance_from_id(int(object_id)) as Button
		if button != null: button.icon = texture
