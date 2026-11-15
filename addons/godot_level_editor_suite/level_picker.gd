@tool
extends VBoxContainer
signal selection_changed(id: String)
const LEVELS := preload("res://addons/godot_level_editor_suite/runtime/level_catalog.gd")
var search: LineEdit
var options: OptionButton
var catalog: Resource
var selected_id := ""
func _ready() -> void:
	search = LineEdit.new()
	search.placeholder_text = "搜索关卡 ID / 名称 / 中文名"
	search.clear_button_enabled = true
	add_child(search)
	options = OptionButton.new()
	options.custom_minimum_size.x = 360
	options.fit_to_longest_item = false
	add_child(options)
	options.item_selected.connect(func(i: int): selected_id = str(options.get_item_metadata(i)); selection_changed.emit(selected_id))
	search.text_changed.connect(func(_value: String): refresh())
	reload()
func reload() -> void:
	var result := LEVELS.load_book()
	catalog = result.catalog
	refresh()
func select_id(id: String) -> void:
	selected_id = id
	if search != null: search.clear(); refresh()
	selection_changed.emit(id)
func refresh() -> void:
	if options == null: return
	options.clear()
	options.add_item("请选择关卡")
	options.set_item_metadata(0, "")
	if catalog == null: return
	for row in catalog.levels:
		if not search.text.is_empty() and not (str(row.level_id) + " " + str(row.name) + " " + str(row.display_name)).to_lower().contains(search.text.to_lower()): continue
		options.add_item(str(row.display_name) + "  (" + str(row.level_id) + " · " + str(row.name) + ")")
		options.set_item_metadata(options.item_count - 1, str(row.level_id))
		if str(row.level_id) == selected_id: options.select(options.item_count - 1)
func value() -> String:
	return str(options.get_item_metadata(options.selected)) if options.selected >= 0 else ""
