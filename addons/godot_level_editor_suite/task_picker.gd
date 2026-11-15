@tool
extends VBoxContainer
const CATALOG := preload("res://addons/godot_level_editor_suite/runtime/event_catalog.gd")
var workbook := CATALOG.PATH
var level_id := ""
var catalog: Resource
var search: LineEdit
var options: OptionButton
var selected_id := ""

func _ready() -> void:
	search = LineEdit.new(); search.placeholder_text = "搜索任务 ID / 名称 / 事件"; search.clear_button_enabled = true; add_child(search)
	options = OptionButton.new(); options.fit_to_longest_item = false; options.clip_text = true; options.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(options)
	search.text_changed.connect(func(_text: String): refresh())
	options.item_selected.connect(func(i: int): selected_id = str(options.get_item_metadata(i)))
	catalog = CATALOG.load_book(workbook).catalog
	refresh()

func select_id(id: String) -> void:
	selected_id = id
	if search != null: search.clear(); refresh()

func value() -> String:
	return str(options.get_item_metadata(options.selected)) if options.selected >= 0 else ""

func refresh() -> void:
	options.clear(); options.add_item("请选择要接取的任务"); options.set_item_metadata(0, "")
	if catalog == null: return
	for event in catalog.events:
		var tasks: Array = catalog.event_tasks(str(event.event_id))
		if tasks.is_empty(): continue
		var task: Dictionary = tasks[0]
		if not level_id.is_empty() and str(task.level_id) != level_id: continue
		var caption := str(event.display_name) + " / " + str(task.display_name) + "  (" + str(task.task_id) + ")"
		if not search.text.is_empty() and not (caption + " " + str(task.name)).to_lower().contains(search.text.to_lower()): continue
		options.add_item(caption); options.set_item_metadata(options.item_count - 1, str(task.task_id))
		options.get_popup().set_item_tooltip(options.item_count - 1, caption)
		if selected_id == str(task.task_id): options.select(options.item_count - 1)
