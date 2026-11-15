@tool
extends HSplitContainer
const PRESET := preload("res://addons/godot_level_editor_sky/preset.gd")
const LIBRARY := preload("res://addons/godot_level_editor_sky/library.gd")
const STYLE := preload("res://addons/godot_level_editor_suite/editor_style.gd")
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
var _importing := false

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var library := VBoxContainer.new(); library.custom_minimum_size.x = 270; add_child(library)
	var title := Label.new(); title.text = "天空预设"; title.add_theme_font_size_override("font_size", 22); library.add_child(title)
	search = LineEdit.new(); search.placeholder_text = "搜索天空"; search.text_changed.connect(func(_value: String): reload_library()); library.add_child(search)
	items = ItemList.new(); items.size_flags_vertical = Control.SIZE_EXPAND_FILL; items.fixed_icon_size = Vector2i(96, 48); items.item_selected.connect(func(index: int): open_preset(str(items.get_item_metadata(index)))); library.add_child(items)
	var library_actions := HBoxContainer.new(); library.add_child(library_actions)
	button(library_actions, "新建", new_preset); button(library_actions, "复制", duplicate_preset)
	references = Label.new(); references.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; references.add_theme_color_override("font_color", STYLE.MUTED); library.add_child(references)
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(right)
	var actions := HFlowContainer.new(); right.add_child(actions)
	button(actions, "保存预设", save); button(actions, "另存为", save_as); button(actions, "还原", discard)
	button(actions, "撤销", func(): if undo.has_undo(): undo.undo())
	button(actions, "重做", func(): if undo.has_redo(): undo.redo())
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; right.add_child(scroll)
	form = VBoxContainer.new(); form.size_flags_horizontal = Control.SIZE_EXPAND_FILL; form.add_theme_constant_override("separation", 10); scroll.add_child(form)
	var footer := HFlowContainer.new(); right.add_child(footer)
	preview_button = button(footer, "临时预览", start_preview)
	button(footer, "结束预览", stop_preview)
	check_button = button(footer, "中性检查", func(): _preview_variant("neutral"))
	compare_button = button(footer, "对比已绑定", func(): _preview_variant("bound"))
	button(footer, "绑定到当前关卡", bind_current)
	target = Label.new(); target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; right.add_child(target)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.add_theme_color_override("font_color", STYLE.BLUE); right.add_child(status)
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

func open_preset(path: String) -> void:
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
	if dirty: status.text = "请先保存或还原当前修改。"; return
	draft = PRESET.new(); draft.display_name = "新天空"; selected_path = ""; dirty = true; undo.clear_history(); _build_fields(); _select_current(); _update_references(); _refresh_state()

func duplicate_preset() -> void:
	if draft == null: return
	draft = draft.copy_preset(); draft.display_name += " 副本"; selected_path = ""; dirty = true; undo.clear_history(); _build_fields(); _select_current(); _update_references(); _refresh_state()

func discard() -> void:
	if selected_path.is_empty():
		dirty = false; open_preset(LIBRARY.DEFAULT)
	else:
		dirty = false; open_preset(selected_path)

func _section(text: String) -> GridContainer:
	var heading := Label.new(); heading.text = text; heading.add_theme_font_size_override("font_size", 17); form.add_child(heading)
	var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 18); grid.add_theme_constant_override("v_separation", 8); form.add_child(grid); return grid

func _field(grid: GridContainer, key: String, title: String, kind: String, options: Array = []) -> void:
	var label := Label.new(); label.text = title; label.custom_minimum_size.x = 135; grid.add_child(label)
	var control: Control
	match kind:
		"text":
			var edit := LineEdit.new(); edit.text = str(draft.get(key)); edit.text_changed.connect(func(value: String): change(key, value)); control = edit
		"enum":
			var choice := OptionButton.new()
			for option in options: choice.add_item(str(option))
			choice.select(int(draft.get(key))); choice.item_selected.connect(func(value: int): change(key, value)); control = choice
		"bool":
			var toggle := CheckButton.new(); toggle.button_pressed = bool(draft.get(key)); toggle.toggled.connect(func(value: bool): change(key, value)); control = toggle
		"color":
			var color := ColorPickerButton.new(); color.color = draft.get(key); color.edit_alpha = false; color.color_changed.connect(func(value: Color): change(key, value)); control = color
		_:
			var number := SpinBox.new(); number.min_value = options[0]; number.max_value = options[1]; number.step = options[2]; number.value = float(draft.get(key)); number.value_changed.connect(func(value: float): change(key, value)); control = number
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; control.custom_minimum_size.x = 220; grid.add_child(control); fields[key] = control

func _build_fields() -> void:
	for child in form.get_children(): child.free()
	fields.clear()
	var grid := _section("天空")
	_field(grid, "display_name", "名称", "text")
	_field(grid, "sky_mode", "天空来源", "enum", ["程序天空", "HDRI", "光照模板"])
	fields.sky_mode.set_item_disabled(2, draft.base_environment == null)
	_field(grid, "weather", "天气", "enum", ["晴朗", "多云", "阴天", "薄雾"])
	fields.weather.tooltip_text = "应用云量、主光、补光与雾的基础配置。HDRI 中拍下的云层保持原样。"
	_field(grid, "sky_energy", "天空亮度", "number", [0, 8, 0.05])
	_field(grid, "top_color", "天顶颜色", "color")
	_field(grid, "horizon_color", "地平线颜色", "color")
	_field(grid, "ground_color", "下半球颜色", "color")
	var hdri_row := HBoxContainer.new(); form.add_child(hdri_row)
	button(hdri_row, "导入 HDRI", func(): import_dialog.popup_centered_ratio(0.65))
	var hdri_name := Label.new(); hdri_name.name = "HdriName"; hdri_name.text = draft.hdri.resource_path.get_file() if draft.hdri != null else ""; hdri_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; hdri_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hdri_row.add_child(hdri_name)
	grid = _section("HDRI")
	_field(grid, "hdri_rotation", "水平旋转（°）", "number", [-360, 360, 1])
	_field(grid, "hdri_lighting", "用于环境补光", "bool")
	fields.hdri_rotation.tooltip_text = "旋转全景图；太阳直射方向在太阳参数中独立对齐。"
	grid = _section("太阳")
	_field(grid, "sun_mode", "控制方式", "enum", ["手动角度", "按时刻"])
	_field(grid, "hour", "时刻（小时）", "number", [0, 24, 0.05])
	fields.hour.tooltip_text = "固定时刻。06:00 日出、12:00 正午、18:00 日落；采用美术日轨。"
	_field(grid, "elevation", "高度角（°）", "number", [-90, 90, 1])
	_field(grid, "azimuth", "方位角（°）", "number", [0, 360, 1])
	_field(grid, "north_offset", "日轨朝向（°）", "number", [0, 360, 1])
	_field(grid, "sun_energy", "太阳强度", "number", [0, 10, 0.05])
	_field(grid, "sun_color", "太阳颜色", "color")
	_field(grid, "sun_size", "太阳角直径（°）", "number", [0.1, 20, 0.1])
	_field(grid, "shadows", "投射阴影", "bool")
	solar = Label.new(); solar.add_theme_color_override("font_color", STYLE.MUTED); form.add_child(solar)
	grid = _section("环境光")
	_field(grid, "ambient_color", "补光颜色", "color")
	_field(grid, "ambient_energy", "补光强度", "number", [0, 4, 0.05])
	_field(grid, "exposure", "固定曝光", "number", [0.05, 5, 0.05])
	grid = _section("云层")
	_field(grid, "clouds_enabled", "显示云层", "bool")
	_field(grid, "cloud_coverage", "云量", "number", [0, 1, 0.01])
	_field(grid, "cloud_height", "云层高度（m）", "number", [1, 20000, 10])
	_field(grid, "cloud_scale", "云团尺度（m）", "number", [1, 10000, 10])
	_field(grid, "cloud_color", "云层颜色", "color")
	_field(grid, "cloud_seed", "云形种子", "number", [0, 10000, 1])
	fields.cloud_height.tooltip_text = "相对世界 Y=0 的天空云层高度；不生成云海或体积云。"
	grid = _section("雾")
	_field(grid, "fog_enabled", "启用雾", "bool")
	_field(grid, "fog_color", "雾颜色", "color")
	_field(grid, "fog_begin", "起始距离（m）", "number", [0, 10000, 1])
	_field(grid, "fog_end", "结束距离（m）", "number", [1, 20000, 1])
	_field(grid, "fog_density", "雾浓度", "number", [0, 1, 0.01])
	_refresh_state()

func change(key: String, value: Variant) -> void:
	if _syncing or draft == null or draft.get(key) == value: return
	var before := {key: draft.get(key)}; var after := {key: value}
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
		elif control is CheckButton: control.set_pressed_no_signal(bool(value))
		elif control is ColorPickerButton: control.color = value
		elif control is SpinBox: control.set_value_no_signal(float(value))
	_syncing = false
	var hdri_name := form.find_child("HdriName", true, false) as Label
	if hdri_name != null: hdri_name.text = draft.hdri.resource_path.get_file() if draft.hdri != null else ""

func _enable(key: String, enabled: bool) -> void:
	var control: Control = fields[key]
	if control is SpinBox: control.editable = enabled
	elif control is BaseButton: control.disabled = not enabled
	control.modulate.a = 1.0 if enabled else 0.4

func _refresh_state() -> void:
	if draft == null or fields.is_empty(): return
	for key in ["top_color", "horizon_color", "ground_color", "clouds_enabled", "cloud_height", "cloud_scale", "cloud_coverage", "cloud_color", "cloud_seed"]: _enable(key, draft.sky_mode == 0)
	for key in ["hdri_rotation", "hdri_lighting"]: _enable(key, draft.sky_mode == 1)
	_enable("ambient_color", not (draft.sky_mode == 1 and draft.hdri_lighting))
	for key in ["elevation", "azimuth"]: _enable(key, draft.sun_mode == 0)
	for key in ["hour", "north_offset"]: _enable(key, draft.sun_mode == 1)
	solar.text = draft.summary()
	var world := current_world()
	target.text = "当前关卡：" + (str(world.name) if world != null else "")
	if world != null: target.text += "   天空：" + (str(world.sky_preset.display_name) if world.sky_preset != null else "现有光照")
	preview_button.text = "临时预览中 · 更新" if preview_active else "临时预览"
	status.text = "临时预览 · 未写入关卡" if preview_active else "预设有未保存修改" if dirty else ""

func _update_references() -> void:
	var used := LIBRARY.users(selected_path) if not selected_path.is_empty() else PackedStringArray()
	references.text = "引用关卡：" + ("、".join(used) if not used.is_empty() else "无")

func save() -> void:
	if selected_path.is_empty() or selected_path.begins_with(LIBRARY.DIRECTORY + "/builtin/"): save_as()
	else: _save_to(selected_path)

func save_external() -> void:
	if not dirty: return
	if not selected_path.is_empty() and not selected_path.begins_with(LIBRARY.DIRECTORY + "/builtin/"):
		_save_to(selected_path)
		return
	DirAccess.make_dir_recursive_absolute(LIBRARY.DIRECTORY + "/custom")
	var basename := str(draft.display_name).validate_filename().strip_edges()
	if basename.is_empty(): basename = "sky"
	var path := LIBRARY.DIRECTORY + "/custom/" + basename + "_" + str(Time.get_ticks_usec()) + ".tres"
	_save_to(path)

func save_as() -> void:
	DirAccess.make_dir_recursive_absolute(LIBRARY.DIRECTORY + "/custom")
	save_dialog.current_dir = LIBRARY.DIRECTORY + "/custom"; save_dialog.current_file = "sky_" + str(Time.get_unix_time_from_system()).get_slice(".", 0) + ".tres"; save_dialog.popup_centered_ratio(0.6)

func _save_to(path: String) -> void:
	if path.begins_with(LIBRARY.DIRECTORY + "/builtin/") or not path.begins_with(LIBRARY.DIRECTORY + "/"):
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
	if _importing: return
	if not path.get_extension().to_lower() in ["hdr", "exr"]: status.text = "请选择 .hdr 或 .exr 全景素材。"; return
	_importing = true; status.text = "正在导入 HDRI…"
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty(): status.text = "无法读取 HDRI 文件"; _importing = false; return
	var filename := path.get_file().get_basename().validate_filename() + "_" + str(hash(bytes)).replace("-", "") + "." + path.get_extension().to_lower()
	var destination := "res://assets/sky_hdri/" + filename
	DirAccess.make_dir_recursive_absolute("res://assets/sky_hdri")
	if not FileAccess.file_exists(destination):
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null: status.text = "无法写入素材目录"; _importing = false; return
		file.store_buffer(bytes); file.close()
	var config := ConfigFile.new()
	if FileAccess.file_exists(destination + ".import"): config.load(destination + ".import")
	config.set_value("remap", "importer", "texture")
	config.set_value("remap", "type", "CompressedTexture2D")
	config.set_value("params", "compress/mode", 2)
	config.set_value("params", "compress/hdr_compression", 1)
	config.set_value("params", "mipmaps/generate", true)
	config.set_value("params", "detect_3d/compress_to", 0)
	config.save(destination + ".import")
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning() or filesystem.is_importing(): await get_tree().process_frame
	filesystem.scan()
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if _texture_import_complete(destination) and not filesystem.is_scanning() and not filesystem.is_importing(): break
	if not _texture_import_complete(destination):
		_importing = false; status.text = "HDRI 导入未完成，请检查图像文件后重试。"; return
	# Let the filesystem finish its import notification before creating a preview material.
	await get_tree().create_timer(0.2).timeout
	var texture := ResourceLoader.load(destination) as Texture2D
	_importing = false
	if texture == null: status.text = "HDRI 导入失败，请检查图像文件。"; return
	var before := {"hdri": draft.hdri, "sky_mode": draft.sky_mode}
	undo.create_action("导入 HDRI"); undo.add_do_method(_apply_values.bind({"hdri": texture, "sky_mode": 1})); undo.add_undo_method(_apply_values.bind(before)); undo.commit_action()
	_build_fields(); status.text = "HDRI 已导入 · " + path.get_file()

func _texture_import_complete(path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK: return false
	var files: Variant = config.get_value("deps", "dest_files", PackedStringArray())
	if files.is_empty(): return false
	for file in files:
		if not FileAccess.file_exists(str(file)): return false
	return true
