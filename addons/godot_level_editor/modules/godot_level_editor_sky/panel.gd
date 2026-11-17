@tool
extends HSplitContainer
const PRESET := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/preset.gd")
const LIBRARY := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/library.gd")
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")
const NUMBER_EDIT := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/number_edit.gd")
const COLOR_EDIT := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/color_edit.gd")
const TIME_EDIT := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/time_edit.gd")
var suite: EditorPlugin
var draft: Resource
var selected_path := ""
var dirty := false
var undo := UndoRedo.new()
var fields: Dictionary = {}
var items: ItemList
var search: LineEdit
var references: Label
var status: Label
var target: Label
var solar: Label
var form: VBoxContainer
var save_dialog: FileDialog
var import_dialog: FileDialog
var preview_button: Button
var check_button: Button
var compare_button: Button
var preview_active := false
var _preview_world: Node
var _scene_root: Node
var _syncing := false
var _paths := PackedStringArray()
var _level_catalog: Resource
var _importing := false
var _import_request := 0
var _import_target: Resource
var _draft_actions: Array[Button] = []
var _import_button: Button
var category_tabs: TabContainer
var category_buttons: Dictionary = {}
var field_rows: Dictionary = {}
var _selected_category := "天空背景"
var _sections: Dictionary = {}
var _name_input: LineEdit
var _draft_status: Label
var _hdri_name: Label
var _ambient_hint: Label
var _solar_hint: Label
var _fog_hint: Label
var _preview_hint: Label
var _end_preview: Button
var _bind_button: Button
const HDRI_IMPORT_TIMEOUT_MS := 120000

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var library := VBoxContainer.new(); library.custom_minimum_size.x = 245; add_child(library)
	var title := Label.new(); title.text = "天空预设"; title.add_theme_font_size_override("font_size", 20); library.add_child(title)
	search = LineEdit.new(); search.placeholder_text = "搜索预设"; search.text_changed.connect(func(_value: String): reload_library()); library.add_child(search)
	items = ItemList.new(); items.size_flags_vertical = Control.SIZE_EXPAND_FILL; items.fixed_icon_size = Vector2i(72, 40); items.item_selected.connect(func(index: int): open_preset(str(items.get_item_metadata(index)))); library.add_child(items)
	var library_actions := HBoxContainer.new(); library.add_child(library_actions)
	_draft_actions.append(button(library_actions, "新建", new_preset)); _draft_actions.append(button(library_actions, "复制", duplicate_preset))
	references = Label.new(); references.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; references.add_theme_color_override("font_color", Color("526177")); references.add_theme_font_size_override("font_size", 14); library.add_child(references)
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right.add_theme_constant_override("separation", 12); add_child(right)
	var heading := HBoxContainer.new(); right.add_child(heading)
	var name_label := Label.new(); name_label.text = "预设名称"; heading.add_child(name_label)
	_name_input = LineEdit.new(); _name_input.custom_minimum_size.x = 360; _name_input.text_changed.connect(func(value: String): change("display_name", value)); heading.add_child(_name_input)
	_draft_status = Label.new(); _draft_status.add_theme_font_size_override("font_size", 14); _draft_status.add_theme_color_override("font_color", Color("526177")); heading.add_child(_draft_status)
	var actions := HFlowContainer.new(); right.add_child(actions)
	var save_button := button(actions, "保存预设", save); save_button.theme_type_variation = "PrimaryButton"; _draft_actions.append(save_button)
	_draft_actions.append(button(actions, "另存为", save_as)); _draft_actions.append(button(actions, "还原", discard))
	_draft_actions.back().tooltip_text = "放弃当前修改，恢复到上次保存的预设。"
	button(actions, "撤销", func(): if undo.has_undo(): undo.undo())
	button(actions, "重做", func(): if undo.has_redo(): undo.redo())
	form = VBoxContainer.new(); form.size_flags_vertical = Control.SIZE_EXPAND_FILL; form.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; form.custom_minimum_size.x = 700; form.add_theme_constant_override("separation", 12); right.add_child(form)
	var footer := PanelContainer.new(); footer.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; footer.custom_minimum_size.x = 700; footer.add_theme_stylebox_override("panel", STYLE.bordered(STYLE.PAPER, STYLE.BORDER, 8, 12)); right.add_child(footer)
	var footer_body := VBoxContainer.new(); footer_body.add_theme_constant_override("separation", 8); footer.add_child(footer_body)
	target = Label.new(); target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; target.add_theme_font_size_override("font_size", 14); footer_body.add_child(target)
	var preview_row := HFlowContainer.new(); footer_body.add_child(preview_row)
	preview_button = button(preview_row, "临时预览", start_preview); preview_button.tooltip_text = "在原生三维视口临时查看当前设置；预览中调参会实时更新。"
	_end_preview = button(preview_row, "结束预览", stop_preview)
	check_button = button(preview_row, "中性检查", func(): _preview_variant("neutral")); check_button.tooltip_text = "临时查看无雾、均匀补光的白盒环境。"
	compare_button = button(preview_row, "对比已绑定", func(): _preview_variant("bound")); compare_button.tooltip_text = "临时查看关卡已经保存的环境。"
	_bind_button = button(preview_row, "绑定到当前关卡", bind_current)
	_preview_hint = Label.new(); _preview_hint.add_theme_font_size_override("font_size", 14); _preview_hint.add_theme_color_override("font_color", STYLE.BLUE); footer_body.add_child(_preview_hint)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.add_theme_font_size_override("font_size", 14); status.add_theme_color_override("font_color", STYLE.BLUE); right.add_child(status)
	save_dialog = FileDialog.new(); save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE; save_dialog.access = FileDialog.ACCESS_RESOURCES; save_dialog.filters = PackedStringArray(["*.tres ; 天空预设"]); save_dialog.title = "保存天空预设"; save_dialog.file_selected.connect(_save_to); add_child(save_dialog)
	import_dialog = FileDialog.new(); import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; import_dialog.access = FileDialog.ACCESS_FILESYSTEM; import_dialog.filters = PackedStringArray(["*.hdr, *.exr ; HDRI 全景"]); import_dialog.title = "导入 HDRI"; import_dialog.file_selected.connect(import_hdri); add_child(import_dialog)
	reload_library(); open_preset(LIBRARY.DEFAULT)
	suite.scene_changed.connect(scene_changed)
	scene_changed(EditorInterface.get_edited_scene_root())

func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new(); control.text = text; control.pressed.connect(action); parent.add_child(control); return control

func reload_library() -> void:
	items.clear(); _paths = LIBRARY.paths()
	for path in _paths:
		var preset: Resource = load(path)
		if preset == null or preset.get_script() != PRESET: continue
		if not search.text.is_empty() and not str(preset.display_name).to_lower().contains(search.text.to_lower()): continue
		var index := items.add_item(preset.display_name, LIBRARY.thumbnail(preset))
		items.set_item_metadata(index, path); items.set_item_tooltip(index, preset.summary())
		if path == selected_path: items.select(index)
	_update_import_controls()

func open_preset(path: String) -> void:
	if _block_draft_action():
		_select_current(); return
	if dirty:
		if path != selected_path: status.text = "当前预设有未保存修改，请先保存或还原。"
		_select_current(); return
	var source: Resource = load(path)
	if source == null or source.get_script() != PRESET: status.text = "无法打开天空预设"; return
	draft = source.copy_preset(); selected_path = path; dirty = false; undo.clear_history()
	_build_fields(); _select_current(); _update_references(); status.text = ""
	if preview_active: start_preview()

func _select_current() -> void:
	items.deselect_all()
	for i in items.item_count:
		if items.get_item_metadata(i) == selected_path: items.select(i)

func new_preset() -> void:
	if _block_draft_action(): return
	if dirty: status.text = "请先保存或还原当前修改。"; return
	draft = PRESET.new(); draft.display_name = "新天空"; selected_path = ""; dirty = true; undo.clear_history(); _build_fields(); _select_current(); _update_references(); _refresh_state()

func duplicate_preset() -> void:
	if _block_draft_action(): return
	if draft == null: return
	draft = draft.copy_preset(); draft.display_name += " 副本"; selected_path = ""; dirty = true; undo.clear_history(); _build_fields(); _select_current(); _update_references(); _refresh_state()

func discard() -> void:
	if _block_draft_action(): return
	if selected_path.is_empty():
		dirty = false; open_preset(LIBRARY.DEFAULT)
	else:
		dirty = false; open_preset(selected_path)

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.name = title; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; category_tabs.add_child(scroll)
	var body := VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 12); scroll.add_child(body)
	return body

func _section(parent: Node, title: String) -> VBoxContainer:
	var card := PanelContainer.new(); card.add_theme_stylebox_override("panel", STYLE.bordered(STYLE.PAPER, STYLE.BORDER, 8, 14)); parent.add_child(card)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation", 12); card.add_child(body)
	var label := Label.new(); label.text = title; label.add_theme_font_size_override("font_size", 17); body.add_child(label)
	var rows := VBoxContainer.new(); rows.add_theme_constant_override("separation", 10); body.add_child(rows)
	return rows

func _field(parent: VBoxContainer, key: String, title: String, kind: String, options: Array = []) -> void:
	var row := HBoxContainer.new(); row.name = key; row.add_theme_constant_override("separation", 14); parent.add_child(row); field_rows[key] = row
	var label := Label.new(); label.text = title; label.custom_minimum_size.x = 118; label.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(label)
	var control: Control
	match kind:
		"enum":
			var choice := OptionButton.new(); choice.custom_minimum_size = Vector2(300, 34)
			for option in options: choice.add_item(str(option))
			choice.select(int(draft.get(key))); choice.item_selected.connect(func(value: int): change(key, value)); control = choice
		"bool":
			var toggle := CheckButton.new(); toggle.button_pressed = bool(draft.get(key)); toggle.text = "开启" if toggle.button_pressed else "关闭"; toggle.toggled.connect(func(value: bool): change(key, value)); control = toggle
		"color":
			var color := COLOR_EDIT.new(); color.set_color_no_signal(draft.get(key)); color.color_changed.connect(func(value: Color): change(key, value)); color.invalid_input.connect(_field_error); control = color
		"time":
			var clock := TIME_EDIT.new(); clock.set_value_no_signal(draft.get(key)); clock.value_changed.connect(func(value: float): change(key, value)); clock.invalid_input.connect(_field_error); control = clock
		_:
			var number := NUMBER_EDIT.new(); number.configure(float(draft.get(key)), options[0], options[1], options[2], str(options[3]) if options.size() > 3 else "", bool(options[4]) if options.size() > 4 else true, float(options[5]) if options.size() > 5 else 1.0); number.value_changed.connect(func(value: float): change(key, value)); control = number
	row.add_child(control); fields[key] = control

func _field_error(message: String) -> void:
	status.add_theme_color_override("font_color", STYLE.DANGER); status.text = message

func _build_fields() -> void:
	var restore_category := _selected_category
	_syncing = true
	for child in form.get_children(): child.free()
	fields.clear(); field_rows.clear(); category_buttons.clear(); _sections.clear()
	fields.display_name = _name_input
	_name_input.text = draft.display_name
	var navigation := HFlowContainer.new(); form.add_child(navigation)
	category_tabs = TabContainer.new(); category_tabs.tabs_visible = false; category_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; category_tabs.add_theme_stylebox_override("panel", STYLE.box(Color.TRANSPARENT, 0, 0)); form.add_child(category_tabs)
	for title in ["天空背景", "时间与太阳", "环境光", "云层", "雾"]:
		var category := button(navigation, title, set_category.bind(title)); STYLE.navigation(category, 32, false); category.add_theme_color_override("font_color", STYLE.INK); category.add_theme_color_override("font_hover_color", STYLE.BLUE); category_buttons[title] = category
	category_tabs.tab_changed.connect(func(_index: int):
		_selected_category = category_tabs.get_tab_title(category_tabs.current_tab)
		for key in category_buttons: category_buttons[key].set_pressed_no_signal(key == _selected_category))
	var page := _page("天空背景")
	var rows := _section(page, "天空来源")
	_field(rows, "sky_mode", "背景类型", "enum", ["程序天空", "HDRI 全景", "光照模板"])
	fields.sky_mode.set_item_disabled(2, draft.base_environment == null)
	fields.sky_mode.tooltip_text = "程序天空可直接调色和云层；HDRI 全景使用图片；光照模板沿用已有天空。"
	_field(rows, "weather", "天气组合", "enum", ["晴朗", "多云", "阴天", "薄雾"])
	fields.weather.tooltip_text = "一次应用云量、阳光、补光和雾的基础配置；之后可继续细调。"
	_field(rows, "sky_energy", "天空亮度", "number", [0, 8, 0.05, "倍"])
	rows = _section(page, "天空配色"); _sections.program = rows
	_field(rows, "top_color", "天空顶部", "color")
	_field(rows, "horizon_color", "地平线", "color")
	_field(rows, "ground_color", "地平线下方", "color")
	fields.ground_color.tooltip_text = "地平线下方的背景颜色，不改变关卡地面材质。"
	rows = _section(page, "HDRI 素材"); _sections.hdri = rows
	var image_row := HBoxContainer.new(); image_row.add_theme_constant_override("separation", 12); rows.add_child(image_row)
	_import_button = button(image_row, "导入 HDRI", func(): import_dialog.popup_centered_ratio(0.65))
	_hdri_name = Label.new(); _hdri_name.name = "HdriName"; _hdri_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _hdri_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; image_row.add_child(_hdri_name)
	_field(rows, "hdri_rotation", "水平旋转", "number", [-360, 360, 1, "°"])
	fields.hdri_rotation.tooltip_text = "旋转全景图片；场景中的阳光方向在“时间与太阳”中单独设置。"
	rows = _section(page, "当前光照模板"); _sections.template = rows
	var template := Label.new(); template.text = "保留模板的天空和后期，可在其他分类调整阳光、补光与雾。"; template.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; rows.add_child(template)
	button(rows, "使用程序天空", func(): change("sky_mode", 0))

	page = _page("时间与太阳")
	rows = _section(page, "太阳位置")
	_field(rows, "sun_mode", "位置控制", "enum", ["手动设置角度", "按时刻计算"])
	_field(rows, "hour", "时刻", "time")
	_field(rows, "north_offset", "日轨旋转", "number", [0, 360, 1, "°"])
	fields.north_offset.tooltip_text = "整体旋转一天的太阳路径，不改变当前时刻。"
	_field(rows, "elevation", "太阳高度", "number", [-90, 90, 0.1, "°"])
	fields.elevation.tooltip_text = "0° 位于地平线，正值在上方；负值时太阳直射关闭。"
	_field(rows, "azimuth", "水平朝向", "number", [0, 360, 0.1, "°"])
	var result_box := PanelContainer.new(); result_box.add_theme_stylebox_override("panel", STYLE.box(STYLE.TINT, 6, 10)); rows.add_child(result_box)
	var result_body := VBoxContainer.new(); result_body.add_theme_constant_override("separation", 4); result_box.add_child(result_body)
	solar = Label.new(); solar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; solar.add_theme_color_override("font_color", STYLE.NAVY); result_body.add_child(solar)
	_solar_hint = Label.new(); _solar_hint.add_theme_font_size_override("font_size", 14); _solar_hint.add_theme_color_override("font_color", Color("526177")); result_body.add_child(_solar_hint)
	rows = _section(page, "太阳光")
	_field(rows, "sun_energy", "阳光强度", "number", [0, 10, 0.05, "倍"])
	_field(rows, "sun_color", "阳光颜色", "color")
	_field(rows, "sun_size", "太阳大小", "number", [0.1, 20, 0.1, "°"])
	fields.sun_size.tooltip_text = "太阳的角直径；数值越大，太阳圆盘越大，阴影越柔和。"
	_field(rows, "shadows", "投射阴影", "bool")

	page = _page("环境光")
	rows = _section(page, "环境补光")
	_field(rows, "hdri_lighting", "HDRI 补光", "bool")
	_field(rows, "ambient_color", "补光颜色", "color")
	_ambient_hint = Label.new(); _ambient_hint.text = "补光颜色来自 HDRI 素材。"; _ambient_hint.add_theme_color_override("font_color", Color("526177")); rows.add_child(_ambient_hint)
	_field(rows, "ambient_energy", "补光亮度", "number", [0, 4, 0.05, "倍"])
	fields.ambient_energy.tooltip_text = "补亮背光面和阴影区域，不改变太阳方向。"
	rows = _section(page, "画面亮度")
	_field(rows, "exposure", "固定曝光", "number", [0.05, 5, 0.05, "倍"])
	fields.exposure.tooltip_text = "整体画面的固定亮度倍率，不随镜头转动自动变化。"

	page = _page("云层")
	rows = _section(page, "云层设置"); _sections.clouds = rows
	_field(rows, "clouds_enabled", "显示云层", "bool")
	_field(rows, "cloud_coverage", "云量", "number", [0, 1, 0.01, "%", true, 100])
	_field(rows, "cloud_color", "云层颜色", "color")
	_field(rows, "cloud_height", "云层高度", "number", [1, 20000, 10, "m", false])
	_field(rows, "cloud_scale", "云团大小", "number", [1, 10000, 10, "m", false])
	_field(rows, "cloud_seed", "云形编号", "number", [0, 10000, 1, "", false])
	fields.cloud_height.tooltip_text = "相对世界 Y=0 的天空云层高度，不生成云海。"
	fields.cloud_seed.tooltip_text = "相同编号生成相同云形；改动编号可换一组云。"
	rows = _section(page, "云层来源"); _sections.clouds_unavailable = rows
	var unavailable := Label.new(); unavailable.text = "当前云层来自素材或模板。使用程序天空后可调整云量和高度。"; unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; rows.add_child(unavailable)
	button(rows, "使用程序天空", func(): change("sky_mode", 0))

	page = _page("雾")
	rows = _section(page, "距离雾")
	_field(rows, "fog_enabled", "显示雾", "bool")
	_field(rows, "fog_color", "雾颜色", "color")
	_field(rows, "fog_begin", "起始距离", "number", [0, 10000, 1, "m", false])
	fields.fog_begin.tooltip_text = "从相机前方这个距离开始出现雾。"
	_field(rows, "fog_end", "结束距离", "number", [1, 20000, 1, "m", false])
	fields.fog_end.tooltip_text = "雾在这个距离达到所设浓度，应大于起始距离。"
	_field(rows, "fog_density", "雾浓度", "number", [0, 1, 0.01, "%", true, 100])
	_fog_hint = Label.new(); _fog_hint.text = "结束距离需要大于起始距离。"; _fog_hint.add_theme_color_override("font_color", STYLE.DANGER); rows.add_child(_fog_hint)
	set_category(restore_category)
	_sync_fields(); _refresh_state(); _update_import_controls()

func set_category(title: String) -> void:
	for i in category_tabs.get_tab_count():
		if category_tabs.get_tab_title(i) == title:
			category_tabs.current_tab = i; _selected_category = title
	for key in category_buttons: category_buttons[key].set_pressed_no_signal(key == _selected_category)

func _show_section(key: String, visible: bool) -> void:
	_sections[key].get_parent().get_parent().visible = visible

func change(key: String, value: Variant) -> void:
	if _syncing or draft == null or draft.get(key) == value: return
	var before := {key: draft.get(key)}; var after := {key: value}
	if key == "sun_mode" and int(value) == 0 and draft.sun_mode == 1:
		var angles: Vector2 = draft.solar_angles()
		before.merge({"elevation": draft.elevation, "azimuth": draft.azimuth})
		after.merge({"elevation": angles.x, "azimuth": angles.y})
	if key == "weather":
		var settings: Array = [
			{"cloud_coverage": 0.2, "sun_energy": 2.65, "ambient_energy": 0.32, "fog_enabled": false},
			{"cloud_coverage": 0.6, "sun_energy": 1.5, "ambient_energy": 0.45, "fog_enabled": false},
			{"cloud_coverage": 1.0, "sun_energy": 0.4, "ambient_energy": 0.65, "fog_enabled": false},
			{"cloud_coverage": 0.35, "sun_energy": 1.8, "ambient_energy": 0.45, "fog_enabled": true}]
		after.merge(settings[int(value)])
		after["clouds_enabled"] = true
		for field in after: before[field] = draft.get(field)
	undo.create_action("修改天空 " + key, UndoRedo.MERGE_ENDS)
	undo.add_do_method(_apply_values.bind(after)); undo.add_undo_method(_apply_values.bind(before)); undo.commit_action()

func _apply_values(values: Dictionary) -> void:
	for key in values: draft.set(key, values[key])
	dirty = true; _sync_fields(); _refresh_state()
	if preview_active: start_preview()

func _sync_fields() -> void:
	_syncing = true
	for key in fields:
		var control: Control = fields[key]; var value: Variant = draft.get(key)
		if control is LineEdit:
			if control.text != str(value): control.text = str(value)
		elif control is OptionButton: control.select(int(value))
		elif control is CheckButton:
			control.set_pressed_no_signal(bool(value)); control.text = "开启" if value else "关闭"
		elif control.has_method("set_color_no_signal"): control.set_color_no_signal(value)
		elif control.has_method("set_value_no_signal"): control.set_value_no_signal(float(value))
	_syncing = false
	_hdri_name.text = draft.hdri.resource_path.get_file() if draft.hdri != null else "未选择素材"
	_hdri_name.tooltip_text = draft.hdri.resource_path if draft.hdri != null else "选择 .hdr 或 .exr 全景素材。"

func _enable(key: String, enabled: bool) -> void:
	var control: Control = fields[key]
	if control.has_method("set_editable"): control.set_editable(enabled)
	elif control is BaseButton: control.disabled = not enabled
	control.modulate.a = 1.0 if enabled else 0.45

func _refresh_state() -> void:
	if draft == null or fields.is_empty(): return
	var procedural: bool = draft.sky_mode == 0
	_show_section("program", procedural); _show_section("hdri", draft.sky_mode == 1); _show_section("template", draft.sky_mode == 2)
	_show_section("clouds", procedural); _show_section("clouds_unavailable", not procedural)
	field_rows.weather.visible = procedural
	for key in ["top_color", "horizon_color", "ground_color", "clouds_enabled", "cloud_height", "cloud_scale", "cloud_coverage", "cloud_color", "cloud_seed"]: _enable(key, procedural)
	for key in ["cloud_height", "cloud_scale", "cloud_coverage", "cloud_color", "cloud_seed"]: field_rows[key].visible = draft.clouds_enabled
	for key in ["hdri_rotation", "hdri_lighting"]: _enable(key, draft.sky_mode == 1)
	field_rows.hdri_lighting.visible = draft.sky_mode == 1
	var sky_fill: bool = draft.sky_mode == 1 and draft.hdri_lighting
	field_rows.ambient_color.visible = not sky_fill; _ambient_hint.visible = sky_fill
	_enable("ambient_color", not sky_fill)
	for key in ["elevation", "azimuth"]:
		_enable(key, draft.sun_mode == 0); field_rows[key].visible = draft.sun_mode == 0
	for key in ["hour", "north_offset"]:
		_enable(key, draft.sun_mode == 1); field_rows[key].visible = draft.sun_mode == 1
	var angles: Vector2 = draft.solar_angles()
	solar.text = "当前太阳高度 %.1f°    水平朝向 %.1f°" % [angles.x, angles.y]
	_solar_hint.text = ("根据 %s 自动计算" % fields.hour.clock.text) if draft.sun_mode == 1 else "使用手动设置的角度"
	if angles.x < 0: _solar_hint.text += "，太阳位于地平线下"
	for key in ["fog_color", "fog_begin", "fog_end", "fog_density"]: field_rows[key].visible = draft.fog_enabled
	_fog_hint.visible = draft.fog_enabled and draft.fog_end <= draft.fog_begin
	_draft_status.text = "未保存修改" if dirty else "内置预设" if selected_path.begins_with(LIBRARY.DIRECTORY + "/builtin/") else "已保存" if not selected_path.is_empty() else "新预设"
	_draft_status.tooltip_text = "内置预设的修改会另存为自定义预设。" if selected_path.begins_with(LIBRARY.DIRECTORY + "/builtin/") else selected_path
	var world := current_world()
	var level_name := str(world.name) if world != null else "未打开关卡"
	if world != null:
		var catalog: Resource = suite.level_panel.catalog if suite != null and suite.level_panel != null else _level_catalog
		if catalog == null:
			var book := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
			_level_catalog = book.catalog; catalog = _level_catalog
		var level: Dictionary = catalog.for_world(world) if catalog != null else {}
		if not level.is_empty(): level_name = str(level.display_name)
	target.text = "当前关卡：" + level_name
	if world != null: target.text += "    已绑定：" + (str(world.sky_preset.display_name) if world.sky_preset != null else "现有光照")
	_end_preview.disabled = not preview_active
	_preview_hint.text = "临时查看中，关卡绑定未改变。" if preview_active else ""
	_preview_hint.visible = preview_active
	_bind_button.disabled = world == null or dirty or selected_path.is_empty() or _importing
	_bind_button.tooltip_text = "先保存天空预设，再绑定到当前关卡并保存场景。" if _bind_button.disabled else "把已保存的天空预设绑定到当前关卡。"
	status.add_theme_color_override("font_color", STYLE.BLUE)
	status.text = "正在导入 HDRI…" if _importing else ""

func _update_references() -> void:
	var used := LIBRARY.users(selected_path) if not selected_path.is_empty() else PackedStringArray()
	references.text = "引用关卡：" + ("、".join(used) if not used.is_empty() else "无")

func save() -> void:
	if _block_draft_action(): return
	if selected_path.is_empty() or selected_path.begins_with(LIBRARY.DIRECTORY + "/builtin/"): save_as()
	else: _save_to(selected_path)

func save_external() -> void:
	if _importing: return
	if not dirty: return
	if not selected_path.is_empty() and not selected_path.begins_with(LIBRARY.DIRECTORY + "/builtin/"):
		_save_to(selected_path)
		return
	DirAccess.make_dir_recursive_absolute(LIBRARY.CUSTOM)
	var basename := str(draft.display_name).validate_filename().strip_edges()
	if basename.is_empty(): basename = "sky"
	var path := LIBRARY.CUSTOM + "/" + basename + "_" + str(Time.get_ticks_usec()) + ".tres"
	_save_to(path)

func save_as() -> void:
	if _block_draft_action(): return
	DirAccess.make_dir_recursive_absolute(LIBRARY.CUSTOM)
	save_dialog.current_dir = LIBRARY.CUSTOM; save_dialog.current_file = "sky_" + str(Time.get_unix_time_from_system()).get_slice(".", 0) + ".tres"; save_dialog.popup_centered_ratio(0.6)

func _save_to(path: String) -> void:
	if _block_draft_action(): return
	if path.begins_with(LIBRARY.DIRECTORY + "/builtin/") or not path.begins_with(LIBRARY.CUSTOM + "/"):
		status.text = "请保存到天空预设目录的自定义文件夹。"; return
	var errors: PackedStringArray = draft.validate()
	if not errors.is_empty(): status.text = "; ".join(errors); return
	var saved: Resource = draft.copy_preset()
	if ResourceSaver.save(saved, path) != OK: status.text = "天空预设保存失败"; return
	var profile: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	EditorInterface.get_resource_filesystem().update_file(path)
	selected_path = path; dirty = false; undo.clear_history(); reload_library(); _update_references(); _refresh_state(); status.text = "预设已保存"
	for root_path in EditorInterface.get_open_scenes():
		# Active scene refreshes immediately; other scenes refresh when selected.
		var world := current_world()
		if world != null and world.scene_file_path == root_path and world.sky_preset != null and world.sky_preset.resource_path == path:
			world.sky_preset = profile

func current_world() -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root != null and root.has_method("preview_sky"): return root
	if root != null and root.get_node_or_null("World") != null and root.get_node("World").has_method("preview_sky"): return root.get_node("World")
	return null

func start_preview() -> void:
	var world := current_world()
	if world == null: status.text = "请先打开一个大世界关卡。"; return
	if is_instance_valid(_preview_world) and _preview_world != world: stop_preview()
	var errors: PackedStringArray = world.preview_sky(draft)
	if not errors.is_empty(): status.text = "; ".join(errors); return
	_preview_world = world; preview_active = true; _refresh_state()

func stop_preview() -> void:
	if is_instance_valid(_preview_world): _preview_world.refresh_sky()
	_preview_world = null; preview_active = false
	if is_instance_valid(status): _refresh_state()

func _preview_variant(kind: String) -> void:
	var world := current_world()
	if world == null: status.text = "请先打开一个大世界关卡。"; return
	_preview_world = world; preview_active = true
	if kind == "neutral": world.preview_sky(load(LIBRARY.DIRECTORY + "/builtin/neutral.tres"))
	else: world.refresh_sky()
	_refresh_state(); status.text = "临时预览 · 中性检查" if kind == "neutral" else "临时预览 · 对比关卡已绑定环境"

func bind_current() -> void:
	if _block_draft_action(): return
	var world := current_world()
	if world == null or world.scene_file_path.is_empty(): status.text = "请先打开已保存的大世界关卡。"; return
	if dirty or selected_path.is_empty(): status.text = "请先保存天空预设，再绑定关卡。"; return
	stop_preview()
	var profile: Resource = load(selected_path)
	var history := suite.get_undo_redo()
	history.create_action("绑定天空预设", UndoRedo.MERGE_DISABLE, world)
	history.add_do_property(world, "sky_preset", profile); history.add_undo_property(world, "sky_preset", world.sky_preset); history.commit_action()
	_refresh_state(); _update_references(); status.text = "已绑定 · 保存关卡场景后生效"
	if suite.level_panel != null: suite.level_panel._detail(false)

func scene_changed(root: Node) -> void:
	if is_instance_valid(_scene_root) and root == _scene_root: return
	stop_preview()
	_scene_root = root
	var world := current_world()
	if world != null: world.refresh_sky()
	_refresh_state()

func import_hdri(path: String) -> void:
	if _block_draft_action(): return
	if draft == null: status.text = "请先选择天空预设。"; return
	if not path.get_extension().to_lower() in ["hdr", "exr"]: status.text = "请选择 .hdr 或 .exr 全景素材。"; return
	_import_request += 1
	var request := _import_request
	var owner_draft := draft
	_import_target = owner_draft
	_importing = true; status.text = "正在导入 HDRI…"
	_update_import_controls()
	var result := await _load_hdri_texture(path, request, owner_draft)
	if not _import_is_current(request, owner_draft):
		_finish_hdri_import(request, "目标草稿已变化，HDRI 导入已取消。")
		return
	var texture: Texture2D = result.get("texture")
	if texture == null:
		_finish_hdri_import(request, str(result.get("error", "HDRI 导入失败，请检查图像文件。")))
		return
	var before := {"hdri": owner_draft.hdri, "sky_mode": owner_draft.sky_mode}
	_finish_hdri_import(request)
	undo.create_action("导入 HDRI"); undo.add_do_method(_apply_values.bind({"hdri": texture, "sky_mode": 1})); undo.add_undo_method(_apply_values.bind(before)); undo.commit_action()
	_build_fields(); status.text = "HDRI 已导入 · " + path.get_file()

func _load_hdri_texture(path: String, request: int, owner_draft: Resource) -> Dictionary:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null: return {"error": "无法读取 HDRI 文件"}
	var bytes := source.get_buffer(source.get_length())
	source.close()
	if bytes.is_empty(): return {"error": "无法读取 HDRI 文件"}
	var image := Image.new()
	if image.load(path) != OK or image.is_empty(): return {"error": "HDRI 图像无效，请选择有效的 .hdr 或 .exr 素材。"}
	var filename := path.get_file().get_basename().validate_filename() + "_" + str(hash(bytes)).replace("-", "") + "." + path.get_extension().to_lower()
	var destination := "res://content/assets/sky_hdri/" + filename
	if DirAccess.make_dir_recursive_absolute("res://content/assets/sky_hdri") != OK: return {"error": "无法创建 HDRI 素材目录"}
	if not FileAccess.file_exists(destination):
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null: return {"error": "无法写入素材目录"}
		file.store_buffer(bytes); file.close()
	var config := ConfigFile.new()
	if FileAccess.file_exists(destination + ".import"): config.load(destination + ".import")
	config.set_value("remap", "importer", "texture")
	config.set_value("remap", "type", "CompressedTexture2D")
	config.set_value("params", "compress/mode", 2)
	config.set_value("params", "compress/hdr_compression", 1)
	config.set_value("params", "mipmaps/generate", true)
	config.set_value("params", "detect_3d/compress_to", 0)
	if config.save(destination + ".import") != OK: return {"error": "无法保存 HDRI 导入设置"}
	var filesystem := EditorInterface.get_resource_filesystem()
	var tree := get_tree()
	var deadline := Time.get_ticks_msec() + HDRI_IMPORT_TIMEOUT_MS
	while filesystem.is_scanning() or filesystem.is_importing():
		await tree.process_frame
		if not _import_is_current(request, owner_draft): return {}
		if Time.get_ticks_msec() >= deadline: return {"error": "素材扫描尚未完成，请稍后重试。"}
	filesystem.scan()
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if not _import_is_current(request, owner_draft): return {}
		if _texture_import_complete(destination) and not filesystem.is_scanning() and not filesystem.is_importing(): break
	if not _texture_import_complete(destination):
		return {"error": "HDRI 导入未完成，请检查图像文件后重试。"}
	# Let the filesystem finish its import notification before creating a preview material.
	await tree.create_timer(0.2).timeout
	if not _import_is_current(request, owner_draft): return {}
	var texture := ResourceLoader.load(destination) as Texture2D
	return {"texture": texture, "error": "HDRI 导入失败，请检查图像文件。"}

func _block_draft_action() -> bool:
	if not _importing: return false
	status.text = "正在导入 HDRI，请完成后再切换或保存预设。"
	return true

func _update_import_controls() -> void:
	for action in _draft_actions:
		if is_instance_valid(action):
			action.disabled = _importing
			action.modulate.a = 0.45 if _importing else 1.0
	if is_instance_valid(_import_button):
		_import_button.disabled = _importing
		_import_button.modulate.a = 0.45 if _importing else 1.0
	if is_instance_valid(items):
		for i in items.item_count: items.set_item_disabled(i, _importing)
		items.modulate.a = 0.55 if _importing else 1.0

func _import_is_current(request: int, owner_draft: Resource) -> bool:
	return is_inside_tree() and _importing and request == _import_request and owner_draft == _import_target and owner_draft == draft

func _finish_hdri_import(request: int, message := "") -> void:
	if request != _import_request: return
	_importing = false; _import_target = null
	_update_import_controls()
	if not message.is_empty() and is_instance_valid(status): status.text = message

func _exit_tree() -> void:
	_finish_hdri_import(_import_request)
	_import_request += 1

func _texture_import_complete(path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK: return false
	var files: Variant = config.get_value("deps", "dest_files", PackedStringArray())
	if not (files is PackedStringArray or files is Array): return false
	if files.is_empty(): return false
	for file in files:
		if not file is String or not FileAccess.file_exists(file): return false
	return true
