@tool
extends VBoxContainer

const PRESET := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/preset.gd")
const BINDING := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/scene_binding.gd")
const INPUT_BINDINGS := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/player_input.gd")
const ANIMATIONS := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/animations.gd")
const CLIMB_ZONE := preload("res://addons/godot_level_editor/modules/godot_level_editor_player/climb_zone.tscn")
const STYLE := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/editor_style.gd")

var suite: EditorPlugin
var draft: Resource
var selected_path := ""
var _selected_hash := ""
var dirty := false
var _list: ItemList
var _body: VBoxContainer
var _status: Label
var _target: Label
var _tabs: TabContainer
var _save: Button
var _apply: Button
var _copy: Button
var _discard: Button
var _reset_dialog: ConfirmationDialog
var _capture: Button
var _capture_id := ""
var _capturing_joy := false
var _world: Node3D
var _root: Node
var _animation_fields: VBoxContainer
var _animation_preview: VBoxContainer
var _binding_warning: Label
var _preview: SubViewport
var _preview_model: Node3D
var _preview_player: AnimationPlayer
var _settings_page := 0

func _ready() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	_button(bar, "新建预设", new_preset)
	_copy = _button(bar, "复制预设", duplicate_preset)
	_save = _button(bar, "保存预设", save_external)
	_save.theme_type_variation = &"PrimaryButton"
	_discard = _button(bar, "还原草稿", _confirm_discard)
	_apply = _button(bar, "应用到当前关卡", apply_current)
	_button(bar, "添加攀爬区", _add_climb_zone)

	_target = Label.new()
	_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_target)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 210
	_list.item_selected.connect(_select_item)
	split.add_child(_list)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_body)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "还原草稿"
	_reset_dialog.dialog_text = "放弃尚未保存的修改？"
	_reset_dialog.confirmed.connect(_discard_changes)
	add_child(_reset_dialog)
	set_process_input(false)
	suite.modules.level.scene_changed.connect(_scene_changed)
	visibility_changed.connect(_visible_changed)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_reload_list)
	_scene_changed(EditorInterface.get_edited_scene_root())
	_reload_list()
	_build_form()

func _button(parent: Node, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _row(parent: Node, text: String, field: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, text)
	label.custom_minimum_size.x = 200
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row

func _set_dirty() -> void:
	dirty = true
	_status.text = "有未保存的修改。"
	_refresh_actions()

func _refresh_actions() -> void:
	_save.disabled = draft == null or not dirty
	_copy.disabled = draft == null
	_discard.disabled = not dirty
	_apply.disabled = draft == null or not BINDING.editable_root(_root)
	if _preview != null: _preview.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

func _visible_changed() -> void:
	if is_visible_in_tree():
		_scene_changed(EditorInterface.get_edited_scene_root())
		_reload_list()
	else:
		_finish_capture()

func _scene_changed(root: Node) -> void:
	if is_instance_valid(_world) and _world.player_preset_changed.is_connected(_show_target):
		_world.player_preset_changed.disconnect(_show_target)
	_root = root
	_world = BINDING.world_for(root)
	if is_instance_valid(_world): _world.player_preset_changed.connect(_show_target)
	_show_target()

func _show_target() -> void:
	if is_instance_valid(_world):
		var title := _root.scene_file_path.get_file().get_basename()
		_target.text = "当前关卡：%s    玩家预设：%s" % [title if not title.is_empty() else "未保存的关卡", _world.player_preset.display_name if _world.player_preset != null else "默认第三人称"]
	else:
		_target.text = "打开一个关卡场景后可以应用预设。"
	_refresh_actions()

func _reload_list() -> void:
	if not is_instance_valid(_list): return
	_list.clear()
	for path in PRESET.library_paths():
		var entry := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if entry == null or entry.get_script() != PRESET: continue
		var index := _list.add_item(entry.display_name)
		_list.set_item_metadata(index, path)
		_list.set_item_tooltip(index, path)
		if path == selected_path: _list.select(index)
	if _list.item_count == 0:
		var index := _list.add_item("还没有玩家预设")
		_list.set_item_selectable(index, false)

func _select_item(index: int) -> void:
	var path := str(_list.get_item_metadata(index))
	if path == selected_path: return
	if not _can_switch(): _reload_list(); return
	var entry := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if entry == null or entry.get_script() != PRESET: return
	selected_path = path
	_selected_hash = FileAccess.get_sha256(path)
	draft = entry.duplicate(true)
	dirty = false
	_status.text = ""
	_build_form()

func _can_switch() -> bool:
	if not dirty: return true
	_status.text = "请先保存或还原当前草稿。"
	return false

func new_preset() -> void:
	if not _can_switch(): return
	draft = PRESET.new()
	draft.display_name = "新玩家预设"
	selected_path = ""
	_selected_hash = ""
	_reload_list()
	_build_form()
	_set_dirty()

func duplicate_preset() -> void:
	if draft == null: return
	draft = draft.duplicate(true)
	draft.display_name += " 副本"
	selected_path = ""
	_selected_hash = ""
	_reload_list()
	_build_form()
	_set_dirty()

func _confirm_discard() -> void:
	if dirty: _reset_dialog.popup_centered()

func _discard_changes() -> void:
	dirty = false
	var previous := selected_path
	selected_path = ""
	draft = null
	_reload_list()
	for i in _list.item_count:
		if _list.get_item_metadata(i) == previous:
			_list.select(i)
			_select_item(i)
			return
	_status.text = ""
	_build_form()

func save_external() -> bool:
	if not dirty: return true
	if draft == null: return false
	var title: String = draft.display_name.strip_edges()
	if title.is_empty():
		_status.text = "请输入预设名称。"
		return false
	var path := selected_path
	if not path.is_empty() and FileAccess.get_sha256(path) != _selected_hash:
		_status.text = "预设文件已在其他位置修改或移动。请复制草稿为新预设，或还原后重新打开。"
		return false
	if path.is_empty():
		var create := DirAccess.make_dir_recursive_absolute(PRESET.DIRECTORY)
		if create != OK:
			_status.text = "无法创建玩家预设目录。"
			return false
		path = PRESET.DIRECTORY.path_join("player_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".tres")
		while FileAccess.file_exists(path):
			path = PRESET.DIRECTORY.path_join("player_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".tres")
	draft.display_name = title
	var cached := ResourceLoader.load(path) if ResourceLoader.has_cached(path) else null
	var result := ResourceSaver.save(draft, path)
	if result != OK:
		_status.text = "保存预设失败（%s）。" % error_string(result)
		return false
	if cached != null and cached.get_script() == PRESET: cached.update_from(draft)
	selected_path = path
	_selected_hash = FileAccess.get_sha256(path)
	dirty = false
	_status.text = "已保存「%s」。" % title
	_reload_list()
	_show_target()
	EditorInterface.get_resource_filesystem().update_file(path)
	return true

func apply_current() -> void:
	if draft == null or not BINDING.editable_root(_root) or not save_external(): return
	var committed := load(selected_path)
	if not BINDING.apply(suite.get_undo_redo(), _root, committed): return
	_status.text = "已选择「%s」。保存关卡后按 F6 试玩。" % draft.display_name
	_show_target()

func _add_climb_zone() -> void:
	if not BINDING.editable_root(_root):
		_status.text = "请先打开并保存关卡。"
		return
	var zone := CLIMB_ZONE.instantiate() as Area3D
	var history := suite.get_undo_redo()
	history.create_action("添加攀爬区", UndoRedo.MERGE_DISABLE, _root)
	history.add_do_method(_world, "add_child", zone, true)
	history.add_do_property(zone, "owner", _root)
	history.add_undo_method(_world, "remove_child", zone)
	history.add_do_reference(zone)
	history.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(zone)
	_status.text = "已添加攀爬区。请在 3D 视口把它移到梯子前，调整碰撞盒高度。"

func _build_form() -> void:
	_finish_capture()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_preview = null
	_preview_model = null
	_preview_player = null
	if draft == null:
		_label(_body, "新建预设，或从左侧选择已有的玩家预设。")
		_refresh_actions()
		return
	var title := LineEdit.new()
	title.text = draft.display_name
	title.text_changed.connect(func(value: String): draft.display_name = value; _set_dirty())
	_row(_body, "预设名称", title)
	var picker := EditorResourcePicker.new()
	picker.base_type = "PackedScene"
	picker.edited_resource = draft.model_scene
	picker.tooltip_text = "留空时使用插件内置角色。自定义场景应包含 AnimationPlayer。"
	picker.resource_changed.connect(func(value: Resource):
		draft.model_scene = value
		draft.clip_overrides.clear()
		_set_dirty()
		_build_animations())
	_row(_body, "角色模型（可选）", picker)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_tabs)
	var settings: Dictionary = draft.settings()
	for i in PRESET.TABS.size():
		var section := _scroll_page(PRESET.TABS[i])
		if i == 0:
			_label(section, "能力")
			var switches := GridContainer.new()
			switches.columns = 3
			section.add_child(switches)
			for field in PRESET.FIELDS[i]:
				if field.size() != 3: continue
				var toggle := CheckButton.new()
				toggle.name = field[0]
				toggle.text = field[1]
				toggle.button_pressed = settings[field[0]]
				toggle.toggled.connect(_set_field.bind(field[0]))
				switches.add_child(toggle)
			_label(section, "角色参数")
		for field in PRESET.FIELDS[i]:
			if i != 0 or field.size() != 3: _configure_field(section, field, settings[field[0]])
		if i == 2: _build_bindings(section)
	var action_page := HBoxContainer.new()
	action_page.name = "动作"
	_tabs.add_child(action_page)
	_animation_fields = _scroll_contents(action_page)
	_animation_preview = VBoxContainer.new()
	_animation_preview.custom_minimum_size.x = 275
	action_page.add_child(_animation_preview)
	_build_animations()
	_tabs.current_tab = mini(_settings_page, _tabs.get_tab_count() - 1)
	_tabs.tab_changed.connect(func(index: int): _settings_page = index; _finish_capture())
	_refresh_actions()

func _scroll_page(title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = title
	_tabs.add_child(page)
	return _scroll_contents(page)

func _scroll_contents(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 5)
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	return fields

func _configure_field(parent: Node, field: Array, value: Variant) -> void:
	var id: String = field[0]
	if field.size() == 3:
		var toggle := CheckButton.new()
		toggle.name = id
		toggle.button_pressed = value
		toggle.toggled.connect(_set_field.bind(id))
		_row(parent, field[1], toggle)
	elif field.size() == 4:
		var option := OptionButton.new()
		option.name = id
		for name_text in field[3]: option.add_item(name_text)
		option.select(value)
		option.item_selected.connect(_set_field.bind(id))
		_row(parent, field[1], option)
	else:
		var spin := SpinBox.new()
		spin.name = id
		spin.min_value = field[3]
		spin.max_value = field[4]
		spin.step = field[5]
		spin.value = value
		spin.value_changed.connect(_set_field.bind(id))
		_row(parent, field[1], spin)

func _set_field(value: Variant, id: String) -> void:
	draft.values[id] = value
	_set_dirty()

func _build_bindings(parent: Control) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "动作按键")
	for id: String in PRESET.ACTIONS:
		var row := HBoxContainer.new()
		var buttons := _row(parent, PRESET.ACTIONS[id][0], row)
		buttons.tooltip_text = "点击键鼠或手柄框，再按下要使用的按键。Esc 取消。"
		_make_binding_button(row, id, false)
		if id not in ["forward", "back", "left", "right"]: _make_binding_button(row, id, true)
	_binding_warning = _label(parent, "")
	_warn_bindings()

func _make_binding_button(parent: Node, id: String, joy: bool) -> void:
	var button := Button.new()
	button.name = ("Joy_" if joy else "Key_") + id
	button.text = _binding_text(id, joy)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func():
		_finish_capture()
		_capture = button
		_capture_id = id
		_capturing_joy = joy
		button.text = "按手柄按键…" if joy else "按键盘按键…"
		set_process_input(true))
	parent.add_child(button)

func _binding_text(id: String, joy: bool) -> String:
	var bits := PackedStringArray()
	for event in INPUT_BINDINGS.events_for(draft, id):
		if (joy and event is InputEventJoypadButton) or (not joy and (event is InputEventKey or event is InputEventMouseButton)):
			bits.append(event.as_text().trim_suffix(" (Physical)"))
	return ("手柄 " if joy else "键鼠 ") + " / ".join(bits)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(_capture): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_finish_capture()
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed() or event.is_echo(): return
	if (_capturing_joy and event is InputEventJoypadButton) or (not _capturing_joy and event is InputEventKey):
		var binding: Dictionary = draft.bindings.get(_capture_id, {})
		binding["joy" if _capturing_joy else "key"] = event.button_index if _capturing_joy else event.physical_keycode
		draft.bindings[_capture_id] = binding
		_finish_capture()
		_warn_bindings()
		_set_dirty()
		get_viewport().set_input_as_handled()

func _finish_capture() -> void:
	if is_instance_valid(_capture) and draft != null: _capture.text = _binding_text(_capture_id, _capturing_joy)
	_capture = null
	set_process_input(false)

func _warn_bindings() -> void:
	var seen := {}
	var duplicates := PackedStringArray()
	for id: String in PRESET.ACTIONS:
		for event in INPUT_BINDINGS.events_for(draft, id):
			if not (event is InputEventKey or event is InputEventJoypadButton): continue
			var label := PRESET.ACTIONS[id][0] as String
			var key := event.as_text()
			if seen.has(key): duplicates.append("%s（%s、%s）" % [key, seen[key], label])
			else: seen[key] = label
	_binding_warning.text = "按键冲突：" + "，".join(duplicates) if not duplicates.is_empty() else ""

func _build_animations() -> void:
	if not is_instance_valid(_animation_fields): return
	for child in _animation_fields.get_children():
		_animation_fields.remove_child(child)
		child.queue_free()
	for child in _animation_preview.get_children():
		_animation_preview.remove_child(child)
		child.queue_free()
	_preview = null
	_preview_model = null
	_preview_player = null
	var pack := EditorResourcePicker.new()
	pack.base_type = "PackedScene"
	pack.edited_resource = draft.animation_scene
	pack.tooltip_text = "可选择与当前模型骨骼名称兼容的动画场景，如 Quaternius 的 Godot GLB。"
	pack.resource_changed.connect(func(value: Resource):
		draft.animation_scene = value
		_set_dirty()
		_build_animations.call_deferred())
	_row(_animation_fields, "附加动画包（可选）", pack)
	var clips := _create_preview()
	for slot: String in PRESET.CLIPS:
		var option := OptionButton.new()
		option.add_item("未绑定")
		var key: String = draft.clip(slot)
		for clip in clips: option.add_item(clip)
		var index := clips.find(key)
		if index == -1 and not key.is_empty():
			option.add_item("缺少：" + key)
			option.select(option.item_count - 1)
		else:
			option.select(index + 1)
		option.item_selected.connect(func(i: int):
			if i > clips.size(): return
			draft.clip_overrides[slot] = "" if i == 0 else clips[i - 1]
			_set_dirty()
			_show_animation(slot))
		var row := _row(_animation_fields, PRESET.CLIPS[slot][0], option)
		_button(row, "播放", _show_animation.bind(slot))
	_show_animation("idle")
	if draft.animation_scene != null and not Array(clips).any(func(clip: String): return clip.begins_with("imported/")):
		_label(_animation_fields, "附加动画包没有可用片段。请检查骨骼名称是否匹配，以及是否包含动画。")

func _create_preview() -> PackedStringArray:
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size.y = 260
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.stretch = true
	_animation_preview.add_child(holder)
	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	holder.add_child(_preview)
	var stage := Node3D.new()
	_preview.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(2.05, 1.45, 2.55)
	camera.look_at(Vector3(0.0, 0.9, 0.0))
	camera.fov = 37
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 35, 0)
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24, -125, 0)
	fill.light_energy = 0.65
	stage.add_child(fill)
	var packed: PackedScene = draft.model_scene if draft.model_scene != null else PRESET.DEFAULT_MODEL
	var model := packed.instantiate()
	if not model is Node3D:
		model.free()
		return PackedStringArray()
	_preview_model = model
	_strip_preview_scripts(model)
	_preview_model.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(_preview_model)
	_preview_player = ANIMATIONS.find_player(model)
	if _preview_player == null: return PackedStringArray()
	if draft.model_scene == null: ANIMATIONS.attach(_preview_player)
	if draft.animation_scene != null and not _preview_player.has_animation_library("imported"):
		var library := ANIMATIONS.external_library(_preview_player, draft.animation_scene)
		if library != null: _preview_player.add_animation_library("imported", library)
	_preview_player.process_mode = Node.PROCESS_MODE_ALWAYS
	return _preview_player.get_animation_list()

func _strip_preview_scripts(node: Node) -> void:
	if node.get_script() != null: node.set_script(null)
	for child in node.get_children(): _strip_preview_scripts(child)

func _show_animation(slot: String) -> void:
	if not is_instance_valid(_preview_player): return
	var clip: String = draft.clip(slot)
	if clip.is_empty() or not _preview_player.has_animation(clip): return
	_preview_player.stop()
	_preview_player.play(clip)
	_preview_player.advance(0.0)
