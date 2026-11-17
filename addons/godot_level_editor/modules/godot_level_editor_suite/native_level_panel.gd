@tool
extends "res://addons/godot_level_editor/modules/godot_level_editor_suite/level_warehouse.gd"
## The scene tree, filesystem, saving and play commands belong to Godot.
## Keep the old helper's creation API for existing development checks only.
func _ready() -> void:
	level_heading = Label.new()
	level_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(level_heading)
	var bar := HBoxContainer.new()
	add_child(bar)
	_button(bar, "定位当前场景", func():
		var root := EditorInterface.get_edited_scene_root()
		if root != null and not root.scene_file_path.is_empty(): EditorInterface.select_file(root.scene_file_path))
	_button(bar, "打开空白模板位置", func(): EditorInterface.select_file("res://addons/godot_level_editor/templates/empty_level.tscn"))
	logic_panel = preload("res://addons/godot_level_editor/modules/godot_level_editor/level_logic_panel.gd").new()
	logic_panel.plugin = module
	logic_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(logic_panel)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	module.scene_changed.connect(_native_scene_changed)
	reload_catalog()
	_native_scene_changed(EditorInterface.get_edited_scene_root())

func _native_scene_changed(root: Node) -> void:
	_world = root if root != null and root.get_script() == WORLD else null
	if _world == null and root != null: _world = root.get_node_or_null("World")
	if _world != null and _world.get_script() != WORLD: _world = null
	logic_panel.bind_world(_world, false)
	logic_panel.visible = _world != null
	_detail(false)

func _detail(_animated: bool) -> void:
	level_heading.text = "当前关卡：" + (_world.scene_file_path.get_file().get_basename() if _world != null else "未打开关卡场景")
	status.text = "" if _world != null else "从 Godot 文件系统打开关卡，或右键空白模板选择“新建继承场景”，保存到自己的作品目录。"

func reload_catalog() -> void:
	var result := LEVELS.load_book(workbook_path)
	catalog = result.catalog if result.catalog != null else LEVELS.new()
	if status != null and not result.errors.is_empty(): status.text = "; ".join(result.errors)
	levels_changed.emit()

func set_mode(_index: int) -> void:
	_native_scene_changed(EditorInterface.get_edited_scene_root())

func apply_level_preview(_id: String, _scene_path: String, _path: String, _texture: Texture2D) -> void:
	pass
