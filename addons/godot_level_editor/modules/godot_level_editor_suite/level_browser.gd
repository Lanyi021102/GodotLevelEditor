@tool
extends VBoxContainer
## A read-only view of native scene files and their existing task index metadata.
signal open_requested(path: String)
signal logic_requested(path: String)
signal new_requested
signal refresh_requested
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")
const CARD := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_card.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const SKY := preload("res://addons/godot_level_editor/modules/godot_level_editor_sky/library.gd")
var entries: Dictionary = {}
var cards: Dictionary = {}
var selected_path := ""
var search: LineEdit
var count: Label
var grid: GridContainer
var details: Label
var cover: TextureRect
var open_button: Button
var logic_button: Button
var locate_button: Button
var empty: Label
var _scroll: ScrollContainer
var _scene_cache: Dictionary = {}
var _signature := ""

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation", 14); add_child(header)
	var heading := VBoxContainer.new(); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(heading)
	var title := Label.new(); title.text = "我的关卡"; title.add_theme_font_size_override("font_size", 24); heading.add_child(title)
	count = Label.new(); count.add_theme_color_override("font_color", STYLE.MUTED); heading.add_child(count)
	search = LineEdit.new(); search.placeholder_text = "搜索关卡名称、ID 或路径"; search.custom_minimum_size.x = 240; search.size_flags_vertical = Control.SIZE_SHRINK_CENTER; search.text_changed.connect(func(_text): _filter()); header.add_child(search)
	var refresh := Button.new(); refresh.text = "刷新"; refresh.size_flags_vertical = Control.SIZE_SHRINK_CENTER; refresh.pressed.connect(func(): refresh_requested.emit()); header.add_child(refresh)
	var create := Button.new(); create.text = "新建关卡"; create.theme_type_variation = "PrimaryButton"; create.size_flags_vertical = Control.SIZE_SHRINK_CENTER; create.pressed.connect(func(): new_requested.emit()); header.add_child(create)
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 22); add_child(body)
	var catalog := VBoxContainer.new(); catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(catalog)
	empty = Label.new(); empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; catalog.add_child(empty)
	_scroll = ScrollContainer.new(); _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; _scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER; catalog.add_child(_scroll)
	grid = GridContainer.new(); grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; grid.add_theme_constant_override("h_separation", 18); grid.add_theme_constant_override("v_separation", 18); _scroll.add_child(grid)
	_scroll.resized.connect(_layout)
	var side := PanelContainer.new(); side.custom_minimum_size.x = 290; side.add_theme_stylebox_override("panel", STYLE.bordered(STYLE.PAPER, STYLE.BORDER, 12, 18)); body.add_child(side)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 14); side.add_child(box)
	var detail_scroll := ScrollContainer.new(); detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER; box.add_child(detail_scroll)
	var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; info.add_theme_constant_override("separation", 14); detail_scroll.add_child(info)
	cover = TextureRect.new(); cover.custom_minimum_size = Vector2(250, 158); cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; info.add_child(cover)
	details = Label.new(); details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.add_child(details)
	open_button = Button.new(); open_button.text = "打开场景"; open_button.theme_type_variation = "PrimaryButton"; open_button.pressed.connect(func(): _open(selected_path)); box.add_child(open_button)
	logic_button = Button.new(); logic_button.text = "编辑常驻逻辑"; logic_button.pressed.connect(func(): logic_requested.emit(selected_path)); box.add_child(logic_button)
	locate_button = Button.new(); locate_button.text = "定位场景文件"; locate_button.pressed.connect(func():
		if entries.has(selected_path): EditorInterface.select_file(selected_path)); box.add_child(locate_button)
	_layout(); _detail()

func load_files(catalog: Resource, current_path := "") -> void:
	var metadata := {}
	if catalog != null:
		for row in catalog.levels: metadata[str(row.scene_path)] = row
	var paths: Array[String] = []
	_scan("res://", paths)
	for path in metadata:
		if FileAccess.file_exists(path) and not paths.has(path): paths.append(path)
	paths.sort()
	var fresh := {}
	# Keep registered maps in their established index order, then unsaved-index files.
	var ordered: Array = metadata.keys()
	for path in paths:
		if not ordered.has(path): ordered.append(path)
	for value in ordered:
		var path := str(value)
		if not FileAccess.file_exists(path) or not _is_level(path): continue
		var row: Dictionary = metadata.get(path, {}).duplicate(true)
		row.scene_path = path
		if not row.has("display_name"): row.display_name = path.get_file().get_basename()
		row.name = path.get_file().get_basename()
		row.level_id = str(row.get("level_id", ""))
		row.notes = str(row.get("notes", ""))
		row.preview_path = str(row.get("preview_path", ""))
		fresh[path] = row
	var signature := JSON.stringify(fresh)
	for path in fresh:
		signature += FileAccess.get_md5(path)
		var preview := str(fresh[path].preview_path)
		if FileAccess.file_exists(preview): signature += FileAccess.get_md5(preview)
	entries = fresh
	if not entries.has(selected_path): selected_path = current_path if entries.has(current_path) else str(entries.keys()[0]) if not entries.is_empty() else ""
	if signature != _signature:
		_signature = signature
		for child in grid.get_children(): grid.remove_child(child); child.queue_free()
		cards.clear()
		for path in entries:
			var data: Dictionary = entries[path].duplicate(true)
			data.native_preview = false # Saved bird's-eye previews have their own capture service.
			data.metadata = "ID " + str(data.level_id) if not str(data.level_id).is_empty() else "保存后登记关卡 ID"
			data.level_id = path # Card selection keys are paths, including unregistered files.
			var card := CARD.new(); card.data = data; card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.selected.connect(select_file); card.activated.connect(_open); grid.add_child(card); cards[path] = card
	_filter(); _layout()

func select_file(path: String) -> void:
	if not entries.has(path): return
	selected_path = path; _detail()

func _open(path: String) -> void:
	if not entries.has(path): return
	select_file(path)
	open_requested.emit(path)

func _detail() -> void:
	if details == null: return
	for path in cards: cards[path].is_selected = path == selected_path
	var row: Dictionary = entries.get(selected_path, {})
	open_button.disabled = row.is_empty(); locate_button.disabled = row.is_empty()
	logic_button.disabled = row.is_empty()
	cover.texture = CARD.preview_texture(str(row.get("preview_path", "")))
	if cover.texture == null: cover.texture = CARD.placeholder_texture()
	if row.is_empty(): details.text = "选择一个关卡查看详情。\n\n地图保存为原生 .tscn 文件后会出现在这里。"; return
	var sky: Resource = SKY.bound_preset(selected_path)
	details.text = str(row.display_name) + "\n\n" + ("ID " + str(row.level_id) if not str(row.level_id).is_empty() else "尚未登记 ID，请打开后原生保存。") + "\n\n" + selected_path + "\n\n天空：" + (str(sky.display_name) if sky != null else "现有光照")
	if not str(row.notes).is_empty(): details.text += "\n\n" + str(row.notes)

func _filter() -> void:
	var shown := 0
	var first_visible := ""
	for path in cards:
		var row: Dictionary = entries[path]
		var matches: bool = search.text.is_empty() or (str(row.display_name) + " " + str(row.level_id) + " " + str(path)).containsn(search.text)
		cards[path].visible = matches
		if matches:
			if shown == 0: first_visible = path
			shown += 1
	if not cards.has(selected_path) or not cards[selected_path].visible: selected_path = first_visible
	_detail()
	count.text = "%d 个关卡" % entries.size() if search.text.is_empty() else "%d / %d 个关卡" % [shown, entries.size()]
	empty.visible = shown == 0
	empty.text = "还没有关卡，点击“新建关卡”从空白模板开始。" if entries.is_empty() else "没有匹配的关卡。"

func _layout() -> void:
	if _scroll != null and grid != null: grid.columns = clampi(int((_scroll.size.x + 18) / 248), 1, 8)

func update_preview(path: String, preview: String, texture: Texture2D) -> void:
	if not entries.has(path): return
	entries[path].preview_path = preview
	if cards.has(path): cards[path].set_preview(preview, texture)
	if selected_path == path: cover.texture = texture

func _is_level(path: String) -> bool:
	if path.begins_with("res://addons/") or not path.ends_with(".tscn"): return false
	var digest := FileAccess.get_md5(path)
	if _scene_cache.has(path) and _scene_cache[path].digest == digest: return _scene_cache[path].level
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var state: SceneState = packed.get_state() if packed != null else null
	var level := false
	for depth in 32:
		if state == null or state.get_node_count() == 0: break
		var script: Script
		for i in state.get_node_property_count(0):
			if str(state.get_node_property_name(0, i)) == "script": script = state.get_node_property_value(0, i); break
		if script != null: level = script == WORLD; break
		var base := state.get_base_scene_state()
		if base != null: state = base
		else:
			var instance := state.get_node_instance(0)
			state = instance.get_state() if instance != null else null
	_scene_cache[path] = {"digest": digest, "level": level}
	return level

static func _scan(directory: String, paths: Array[String]) -> void:
	var folder := DirAccess.open(directory)
	if folder == null: return
	for name in folder.get_files():
		if name.ends_with(".tscn"): paths.append(directory.path_join(name))
	for name in folder.get_directories():
		if name.begins_with(".") or (directory == "res://" and name in ["addons", "tools", "docs", "exports", "dist", "build", "builds", "site", "node_modules"]): continue
		var child := directory.path_join(name)
		if FileAccess.file_exists(child.path_join(".gdignore")) or folder.is_link(name): continue
		_scan(child, paths)
