@tool
extends VBoxContainer
## Catalog first; the original module still owns editing, saving and undo history.
const STYLE := preload("res://addons/godot_level_editor_suite/editor_style.gd")
const CARD := preload("res://addons/godot_level_editor_suite/level_card.gd")
const ASSEMBLY := preload("res://addons/godot_level_editor_mechanisms/runtime/assembly.gd")
const ENEMY := preload("res://addons/enemy_editor/runtime/enemy_definition.gd")
var kind := "机关"
var module: EditorPlugin
var editor: Control
var mode_bar: HBoxContainer
var mode_buttons: Array[Button] = []
var mode_stack: TabContainer
var editor_host: VBoxContainer
var catalog_grid: GridContainer
var search: LineEdit
var detail: VBoxContainer
var detail_title: Label
var detail_info: Label
var detail_cover: TextureRect
var enter_button: Button
var heading: Label
var status: Label
var empty_label: Label
var create_dialog: EditorFileDialog
var entries: Dictionary = {}
var cards: Dictionary = {}
var selected_path := ""
var editing_path := ""
var _pending_path := ""
var _opening := false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if mode_bar == null:
		mode_bar = HBoxContainer.new(); add_child(mode_bar)
	for index in 2:
		var button := Button.new(); button.text = "我的" + kind if index == 0 else kind + "编辑"
		STYLE.navigation(button, 34, false); button.custom_minimum_size.x = 110
		button.pressed.connect(func(): set_mode(index))
		mode_bar.add_child(button); mode_buttons.append(button)
	mode_stack = TabContainer.new(); mode_stack.tabs_visible = false; mode_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mode_stack.add_theme_stylebox_override("panel", STYLE.box(STYLE.BACKGROUND, 0, 0)); add_child(mode_stack)
	_build_catalog()
	editor_host = VBoxContainer.new(); mode_stack.add_child(editor_host)
	heading = Label.new(); heading.add_theme_color_override("font_color", STYLE.NAVY); editor_host.add_child(heading)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status)
	create_dialog = EditorFileDialog.new(); create_dialog.title = "新建" + kind
	create_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE; create_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	create_dialog.add_filter("*.tscn" if kind == "机关" else "*.tres", kind + "资源")
	create_dialog.current_path = "res://scenes/mechanisms/new_mechanism.tscn" if kind == "机关" else "res://resources/enemies/new_npc.tres"
	create_dialog.file_selected.connect(create_asset); add_child(create_dialog)
	if kind == "机关":
		module.scene_changed.connect(_scene_changed)
	else:
		editor.definition_opened.connect(_definition_opened)
		editor.definition_saved.connect(_definition_saved)
		editor.discard_dialog.canceled.connect(func(): _pending_path = "")
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(reload_catalog)
	reload_catalog(); set_mode(0)

func _build_catalog() -> void:
	var page := VBoxContainer.new(); mode_stack.add_child(page)
	var bar := HBoxContainer.new(); page.add_child(bar)
	search = LineEdit.new(); search.placeholder_text = "搜索我的" + kind; search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_text: String): _filter()); bar.add_child(search)
	_button(bar, "刷新", reload_catalog)
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 20); page.add_child(body)
	var scroll := ScrollContainer.new(); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER; body.add_child(scroll)
	var content := VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(content)
	empty_label = Label.new(); empty_label.add_theme_color_override("font_color", STYLE.MUTED); content.add_child(empty_label)
	catalog_grid = GridContainer.new(); catalog_grid.columns = 4; catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_grid.add_theme_constant_override("h_separation", 16); catalog_grid.add_theme_constant_override("v_separation", 16); content.add_child(catalog_grid)
	scroll.resized.connect(func(): catalog_grid.columns = clampi(int((scroll.size.x + 16) / 246), 1, 4))
	var side := PanelContainer.new(); side.custom_minimum_size.x = 280; side.add_theme_stylebox_override("panel", STYLE.bordered(STYLE.PAPER, STYLE.BORDER, 10, 16)); body.add_child(side)
	detail = VBoxContainer.new(); detail.add_theme_constant_override("separation", 14); side.add_child(detail)
	var caption := Label.new(); caption.text = kind + "详情"; caption.add_theme_color_override("font_color", STYLE.MUTED); detail.add_child(caption)
	detail_cover = TextureRect.new(); detail_cover.custom_minimum_size.y = 158; detail_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; detail.add_child(detail_cover)
	detail_title = Label.new(); detail_title.add_theme_font_size_override("font_size", 20); detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; detail.add_child(detail_title)
	detail_info = Label.new(); detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail_info.add_theme_color_override("font_color", STYLE.MUTED); detail.add_child(detail_info)
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; detail.add_child(spacer)
	enter_button = _button(detail, "进入编辑", enter_edit); enter_button.theme_type_variation = "PrimaryButton"

func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new(); button.text = title; button.pressed.connect(action); parent.add_child(button); return button

func set_mode(index: int) -> void:
	if index == 1 and editing_path.is_empty(): return
	var changed := mode_stack.current_tab != index
	mode_stack.current_tab = index
	mode_buttons[1].disabled = editing_path.is_empty()
	for i in mode_buttons.size(): STYLE.select_navigation(mode_buttons[i], i == index)
	if changed: STYLE.reveal(mode_stack.get_current_tab_control())

func reload_catalog() -> void:
	if catalog_grid == null: return
	entries.clear(); cards.clear()
	for child in catalog_grid.get_children(): catalog_grid.remove_child(child); child.queue_free()
	_scan("res://scenes/mechanisms" if kind == "机关" else "res://resources/enemies")
	for path in entries:
		var card := CARD.new(); card.data = entries[path]; card.tooltip_text = path
		card.selected.connect(select_asset)
		card.activated.connect(func(asset_path: String): select_asset(asset_path); enter_edit())
		catalog_grid.add_child(card); cards[path] = card
	var add := CARD.new(); add.is_new = true; add.new_title = "新建" + kind
	add.activated.connect(func(_path: String): create_dialog.popup_centered_ratio(0.6)); catalog_grid.add_child(add)
	if not entries.has(selected_path): selected_path = "" if entries.is_empty() else str(entries.keys()[0])
	_filter(); _detail()

func _scan(folder: String) -> void:
	for file in DirAccess.get_files_at(folder):
		var path := folder.path_join(file)
		if kind == "机关" and file.ends_with(".tscn"):
			var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
			if scene == null: continue
			var root := scene.instantiate()
			if root is ASSEMBLY and root.definition != null:
				_add_entry(path, str(root.definition.display_name), "%d 个节点" % root.definition.nodes.size(), path)
			root.free()
		elif kind == "NPC" and file.ends_with(".tres"):
			var definition := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ENEMY
			if definition != null:
				_add_entry(path, definition.display_name, "%d 个状态" % definition.states.size(), "res://scenes/guard.tscn")
	for directory in DirAccess.get_directories_at(folder): _scan(folder.path_join(directory))

func _add_entry(path: String, title: String, info: String, preview: String) -> void:
	var icon: Texture2D = preload("res://addons/godot_level_editor_suite/mechanism_thumbnail.svg") if kind == "机关" else preload("res://addons/godot_level_editor_suite/npc_thumbnail.svg")
	entries[path] = {"level_id": path, "name": path.get_file().get_basename(), "display_name": title, "scene_path": preview, "metadata": info, "notes": path.get_file(), "fallback_icon": icon}
	var thumbnail := "res://resources/mechanisms/whitebox_v1/previews/" + path.get_file().get_basename() + ".png"
	if kind == "机关" and path.get_base_dir() == "res://scenes/mechanisms" and FileAccess.file_exists(thumbnail): entries[path].preview_path = thumbnail

func _filter() -> void:
	var count := 0
	for path in cards:
		var row: Dictionary = entries[path]
		cards[path].visible = search.text.is_empty() or (str(row.display_name) + " " + str(path)).containsn(search.text)
		if cards[path].visible: count += 1
	empty_label.visible = count == 0
	empty_label.text = "暂无" + kind + "，点击下方卡片新建。" if entries.is_empty() else "没有匹配的" + kind

func select_asset(path: String) -> void:
	if not entries.has(path): return
	selected_path = path; _detail(); STYLE.reveal(detail)

func _detail() -> void:
	for path in cards: cards[path].is_selected = path == selected_path
	var row: Dictionary = entries.get(selected_path, {})
	enter_button.disabled = row.is_empty()
	detail_title.text = str(row.get("display_name", "选择一个" + kind))
	detail_info.text = str(row.get("metadata", "")) + "\n\n" + selected_path
	detail_cover.texture = row.get("fallback_icon")
	var thumbnail := str(row.get("preview_path", ""))
	if not thumbnail.is_empty(): detail_cover.texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(thumbnail)))
	elif not row.is_empty(): EditorInterface.get_resource_previewer().queue_resource_preview(str(row.scene_path), self, "_preview", selected_path)

func _preview(_path: String, texture: Texture2D, _small: Texture2D, path: Variant) -> void:
	if str(path) == selected_path and texture != null: detail_cover.texture = texture

func enter_edit() -> void:
	if _opening or not entries.has(selected_path): return
	var path := selected_path
	status.text = ""
	if kind == "NPC":
		_pending_path = path
		if editor.file_path == path: _activate(path); _pending_path = ""
		else:
			editor.request_open(path)
			if not editor.discard_dialog.visible and editor.file_path != path: status.text = editor.status.text; _pending_path = ""
		return
	_opening = true
	# The mechanism panel is tied to the native active scene. Save its graph before switching.
	if editor.dirty:
		editor.save_before_editor()
		if editor.dirty: status.text = editor.status.text; _opening = false; return
	EditorInterface.open_scene_from_path(path)
	for attempt in 120:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path and editor.assembly == root:
			_activate(path); _opening = false; return
		await get_tree().process_frame
	status.text = "无法打开机关场景：" + path
	_opening = false

func _activate(path: String) -> void:
	editing_path = path
	var row: Dictionary = entries.get(path, {})
	heading.text = str(row.get("display_name", path.get_file())) + "   ·   " + path.get_file()
	heading.tooltip_text = path
	set_mode(1)

func _scene_changed(root: Node) -> void:
	if root is ASSEMBLY and not root.scene_file_path.is_empty():
		editing_path = root.scene_file_path
		heading.text = str(root.definition.display_name) + "   ·   " + editing_path.get_file() if root.definition != null else editing_path.get_file()
	else:
		editing_path = ""; set_mode(0)
	mode_buttons[1].disabled = editing_path.is_empty()

func _definition_opened(path: String) -> void:
	editing_path = path; heading.text = str(editor.definition.display_name) + "   ·   " + path.get_file()
	mode_buttons[1].disabled = path.is_empty()
	if path == _pending_path: _pending_path = ""; _activate(path)

func _definition_saved(path: String) -> void:
	reload_catalog(); _definition_opened(path)

func create_asset(path: String) -> void:
	if FileAccess.file_exists(path) or (kind == "机关" and FileAccess.file_exists(path.get_basename() + ".graph.tres")):
		status.text = "同名资源已存在，请使用新的文件名。"; return
	if kind == "机关":
		var root := preload("res://addons/godot_level_editor_mechanisms/factory.gd").sample()
		root.definition.display_name = path.get_file().get_basename()
		var result := preload("res://addons/godot_level_editor_mechanisms/store.gd").save_pair(root, path)
		root.free()
		if not result.ok: status.text = "；".join(result.errors); return
	else:
		var definition := preload("res://addons/enemy_editor/runtime/guard_template.gd").create()
		definition.display_name = path.get_file().get_basename()
		var result := preload("res://addons/enemy_editor/definition_store.gd").save_definition(definition, path)
		if result != OK: status.text = "创建失败：" + error_string(result); return
	EditorInterface.get_resource_filesystem().scan()
	reload_catalog(); select_asset(path); enter_edit()
