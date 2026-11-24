@tool
extends EditorInspectorPlugin

const VEHICLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_vehicle/vehicle.gd")
const PRESET_DIRECTORY := "res://content/scenes/vehicles"
var editor: EditorPlugin

func _can_handle(object: Object) -> bool:
	return object is VEHICLE

func _parse_begin(object: Object) -> void:
	var button := Button.new()
	button.name = "SaveVehiclePreset"
	button.text = "保存为载具预设"
	button.tooltip_text = "保存当前位置之外的载具设置，可在其他关卡的轮盘中重复放置。"
	button.pressed.connect(_choose_file.bind(object))
	add_custom_control(button)

func _choose_file(source: VEHICLE) -> void:
	var status := DirAccess.make_dir_recursive_absolute(PRESET_DIRECTORY)
	if status != OK:
		editor.show_message("无法创建载具预设目录。")
		return
	var dialog := EditorFileDialog.new()
	dialog.title = "保存载具预设"
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tscn", "Godot 场景")
	EditorInterface.get_base_control().add_child(dialog)
	dialog.current_dir = PRESET_DIRECTORY
	dialog.current_file = str(source.name).to_snake_case().validate_filename() + ".tscn"
	dialog.file_selected.connect(func(path: String):
		if not is_instance_valid(source): return
		if not path.begins_with(PRESET_DIRECTORY + "/") or not path.ends_with(".tscn"):
			editor.show_message("请将载具预设保存为载具目录内的 .tscn 场景。")
			return
		var result := save_preset(source, path)
		if result == OK: EditorInterface.get_resource_filesystem().update_file(path)
		editor.show_message("已保存载具预设" if result == OK else "载具预设保存失败：" + error_string(result)))
	dialog.close_requested.connect(dialog.queue_free)
	dialog.visibility_changed.connect(func():
		if not dialog.visible: dialog.queue_free())
	dialog.popup_centered(Vector2i(720, 480))

static func save_preset(source: VEHICLE, path: String) -> Error:
	var copy := VEHICLE.new()
	copy.name = path.get_file().get_basename().validate_node_name()
	const MASK := PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR
	for property in source.get_property_list():
		if (int(property.usage) & MASK) == MASK:
			copy.set(property.name, source.get(property.name))
	var packed := PackedScene.new()
	var result := packed.pack(copy)
	copy.free()
	if result != OK: return result
	return ResourceSaver.save(packed, path)
