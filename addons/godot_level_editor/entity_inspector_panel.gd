@tool
extends VBoxContainer
const PROFILE := preload("res://addons/godot_level_editor/runtime/entity_profile.gd")
const EVENTS := preload("res://addons/godot_level_editor_suite/runtime/event_catalog.gd")
const MODELS := ["default", "capsule", "box", "humanoid_base", "custom"]
const MODEL_LABELS := ["默认素材", "capsule · 胶囊体", "box · 方块", "humanoid_base · 标准人形", "自定义模型 ID"]
const ACTIONS := ["idle", "walk", "run", "patrol", "custom"]
const ACTION_LABELS := ["待机", "行走", "奔跑", "巡逻", "自定义动作"]
var entity: Node3D
var plugin: EditorPlugin
var fields := {}
var task_row: Control
var custom_model_row: Control
var model_scene_row: Control
var custom_action_row: Control
var status: Label
var _last: Array = []
var _refreshing := false
var _scale := 1.0

func _ready() -> void:
	name = "LevelEntityInspector"
	_scale = EditorInterface.get_editor_scale()
	add_theme_constant_override("separation", roundi(7 * _scale))
	var config: Resource = entity.get_meta(PROFILE.META)
	var title := Label.new(); title.text = {"npc": "NPC 属性", "mechanism": "机关属性", "room": "Room 属性"}.get(config.kind, "对象属性")
	title.add_theme_color_override("font_color", Color("2563eb")); add_child(title)
	var id := Label.new(); id.text = _identity(); id.clip_text = true; id.tooltip_text = id.text; _row("实例 ID", id)
	var name_field := LineEdit.new(); fields["display_name"] = name_field; _row("名称", name_field)
	name_field.text_submitted.connect(func(_text: String): _name_changed())
	name_field.focus_exited.connect(_name_changed)
	var lifetime := _options("lifetime", ["关卡常驻", "任务对象"], ["level", "task"])
	_row("存在范围", lifetime)
	var task := OptionButton.new(); task.fit_to_longest_item = false; task.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fields["task_id"] = task; task_row = _row("所属任务", task); _populate_tasks(task)
	task.item_selected.connect(func(index: int): _commit("task_id", str(task.get_item_metadata(index))))
	_row("模型 ID", _options("model_id", MODEL_LABELS, MODELS))
	var custom_model := LineEdit.new(); fields["custom_model"] = custom_model; custom_model_row = _row("模型 ID", custom_model)
	custom_model.text_submitted.connect(func(_text: String): _commit("model_id", custom_model.text.strip_edges()))
	custom_model.focus_exited.connect(func():
		if custom_model_row.visible: _commit("model_id", custom_model.text.strip_edges()))
	var model_scene := EditorResourcePicker.new(); model_scene.base_type = "PackedScene"; fields["model_scene"] = model_scene
	model_scene_row = _row("模型场景", model_scene)
	model_scene.tooltip_text = "选择模型场景以替换占位外形；自定义 ID 与场景一起保存在当前实例。"
	model_scene.resource_changed.connect(func(value: Resource): _commit("model_scene", value))
	if config.kind == "npc":
		_row("阵营", _options("faction", ["友善", "敌对"], ["friendly", "hostile"]))
		_row("默认动作", _options("default_action", ACTION_LABELS, ACTIONS))
		var custom_action := LineEdit.new(); fields["custom_action"] = custom_action; custom_action_row = _row("动作 ID", custom_action)
		custom_action.text_submitted.connect(func(_text: String): _commit("default_action", custom_action.text.strip_edges()))
		custom_action.focus_exited.connect(func():
			if custom_action_row.visible: _commit("default_action", custom_action.text.strip_edges()))
		var behavior := EditorResourcePicker.new(); behavior.base_type = "Resource"; fields["behavior_definition"] = behavior; _row("行为定义", behavior)
		behavior.tooltip_text = "保留现有 NPC／状态机定义引用，作为后续行为接入参数。"
		behavior.resource_changed.connect(func(value: Resource): _commit("behavior_definition", value))
		_spin("body_height", "角色高度", 0.2, 10, 0.1)
		_spin("body_radius", "胶囊半径", 0.1, 5, 0.05)
	if config.kind == "room" and entity.get("bounds_size") is Vector3:
		for axis in 3:
			var spin := SpinBox.new(); spin.min_value = 0.1; spin.max_value = 10000; spin.step = 0.1
			fields["bounds_" + str(axis)] = spin; _row(["宽度", "高度", "深度"][axis], spin)
			spin.value_changed.connect(func(value: float):
				var dimensions: Vector3 = entity.bounds_size; dimensions[axis] = value; _commit_property("bounds_size", dimensions))
	if config.kind == "mechanism" and entity.get_script() == preload("res://addons/godot_level_editor/runtime/placement.gd"):
		var component := EditorResourcePicker.new(); component.base_type = "PackedScene"; fields["component_scene"] = component; _row("机关场景", component)
		component.resource_changed.connect(_component_changed)
	var enabled := CheckBox.new(); enabled.text = "启用"; fields["initially_enabled"] = enabled; _row("初始状态", enabled)
	enabled.toggled.connect(func(value: bool): _commit("initially_enabled", value))
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.add_theme_color_override("font_color", Color("b93843")); add_child(status)
	_sync()
	if not _editable():
		for control in fields.values():
			if control is BaseButton: control.disabled = true
			elif control is LineEdit or control is SpinBox or control is EditorResourcePicker: control.editable = false
		status.text = "请打开源场景或启用可编辑子节点"; status.show()

func _row(label: String, control: Control) -> Control:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", roundi(6 * _scale)); add_child(row)
	var caption := Label.new(); caption.text = label; caption.custom_minimum_size.x = 78 * _scale; row.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(control)
	return row

func _identity() -> String:
	for key in ["object_id", "room_id", "instance_id", "enemy_instance_id"]:
		if entity.get(key) is String: return str(entity.get(key))
	return str(entity.name)

func _options(field: String, labels: Array, values: Array) -> OptionButton:
	var picker := OptionButton.new(); picker.fit_to_longest_item = false; picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for i in labels.size(): picker.add_item(labels[i]); picker.set_item_metadata(i, values[i])
	picker.item_selected.connect(func(index: int): _commit(field, str(picker.get_item_metadata(index))))
	fields[field] = picker
	return picker

func _spin(field: String, label: String, minimum: float, maximum: float, step: float) -> void:
	var spin := SpinBox.new(); spin.min_value = minimum; spin.max_value = maximum; spin.step = step
	fields[field] = spin; _row(label, spin)
	spin.value_changed.connect(func(value: float): _commit(field, value))

func _populate_tasks(picker: OptionButton) -> void:
	picker.add_item("选择任务"); picker.set_item_metadata(0, "")
	var world: Node = EditorInterface.get_edited_scene_root()
	var level_id := str(world.get("level_id")) if world.get("level_id") is String else ""
	var result := EVENTS.load_book()
	if not result.errors.is_empty(): return
	for task in result.catalog.tasks:
		if not level_id.is_empty() and str(task.level_id) != level_id: continue
		picker.add_item(str(task.task_id) + " · " + str(task.display_name)); picker.set_item_metadata(picker.item_count - 1, str(task.task_id))

func _process(_delta: float) -> void:
	if not is_instance_valid(entity): return
	var config: Resource = entity.get_meta(PROFILE.META) if entity.has_meta(PROFILE.META) else null
	if config == null: return
	var snapshot: Array = [config, entity.get("display_name"), entity.name, entity.get("bounds_size"), entity.get("component_scene")]
	if snapshot != _last: _sync()

func _select(picker: OptionButton, value: String, fallback := 0) -> void:
	for i in picker.item_count:
		if picker.get_item_metadata(i) == value: picker.select(i); return
	picker.select(fallback)

func _sync() -> void:
	_refreshing = true
	var config: Resource = entity.get_meta(PROFILE.META)
	_last = [config, entity.get("display_name"), entity.name, entity.get("bounds_size"), entity.get("component_scene")]
	fields.display_name.text = str(entity.get("display_name")) if entity.get("display_name") is String else str(entity.name)
	for key in ["lifetime", "model_id", "faction", "default_action"]:
		if fields.has(key): _select(fields[key], str(config.get(key)), fields[key].item_count - 1)
	var task: OptionButton = fields.task_id
	if not config.task_id.is_empty():
		var found := false
		for i in task.item_count: found = found or task.get_item_metadata(i) == config.task_id
		if not found: task.add_item(str(config.task_id) + " · 未匹配任务"); task.set_item_metadata(task.item_count - 1, config.task_id)
	_select(task, config.task_id)
	task_row.visible = config.lifetime == "task"
	custom_model_row.visible = not MODELS.slice(0, 4).has(config.model_id)
	fields.custom_model.text = config.model_id
	model_scene_row.visible = custom_model_row.visible
	fields.model_scene.edited_resource = config.model_scene
	if fields.has("custom_action"):
		custom_action_row.visible = not ACTIONS.slice(0, 4).has(config.default_action)
		fields.custom_action.text = config.default_action
		fields.behavior_definition.edited_resource = config.behavior_definition
		fields.body_height.set_value_no_signal(config.body_height); fields.body_radius.set_value_no_signal(config.body_radius)
	if fields.has("bounds_0"):
		for axis in 3: fields["bounds_" + str(axis)].set_value_no_signal(entity.bounds_size[axis])
	if fields.has("component_scene"): fields.component_scene.edited_resource = entity.component_scene
	fields.initially_enabled.set_pressed_no_signal(config.initially_enabled)
	var errors: PackedStringArray = config.validate()
	if config.lifetime == "task" and not config.task_id.is_empty() and task.get_item_text(task.selected).ends_with("未匹配任务"): errors.append("所属任务不存在或不属于当前关卡")
	status.text = "；".join(errors); status.visible = not status.text.is_empty()
	_refreshing = false

func _commit(field: String, value: Variant) -> void:
	if _refreshing or not _editable(): return
	var before: Resource = entity.get_meta(PROFILE.META)
	if before.get(field) == value: return
	var after: Resource = before.duplicate(false); after.set(field, value)
	var history := plugin.get_undo_redo()
	history.create_action("修改对象 " + field, UndoRedo.MERGE_ENDS, EditorInterface.get_edited_scene_root())
	history.add_do_method(entity, "set_meta", PROFILE.META, after)
	history.add_undo_method(entity, "set_meta", PROFILE.META, before)
	_refresh_binding(history)
	history.commit_action()
	_sync()

func _name_changed() -> void:
	var value := str(fields.display_name.text).strip_edges()
	if not value.is_empty(): _commit_property("display_name" if entity.get("display_name") is String else "name", value)

func _commit_property(field: String, value: Variant) -> void:
	if _refreshing or not _editable() or entity.get(field) == value: return
	var history := plugin.get_undo_redo()
	history.create_action("修改对象 " + field, UndoRedo.MERGE_ENDS, EditorInterface.get_edited_scene_root())
	history.add_do_property(entity, field, value); history.add_undo_property(entity, field, entity.get(field))
	_refresh_binding(history); history.commit_action()

func _component_changed(value: Resource) -> void:
	if _refreshing or not _editable(): return
	var before: Resource = entity.get_meta(PROFILE.META)
	var after: Resource = before.duplicate(false); after.model_id = "default"
	var history := plugin.get_undo_redo()
	history.create_action("设置机关场景", UndoRedo.MERGE_DISABLE, EditorInterface.get_edited_scene_root())
	history.add_do_property(entity, "component_scene", value); history.add_undo_property(entity, "component_scene", entity.component_scene)
	history.add_do_method(entity, "set_meta", PROFILE.META, after); history.add_undo_method(entity, "set_meta", PROFILE.META, before)
	_refresh_binding(history); history.commit_action(); _sync()

func _refresh_binding(history: EditorUndoRedoManager) -> void:
	history.add_do_method(entity, "update_gizmos"); history.add_undo_method(entity, "update_gizmos")
	var binding := entity.get_node_or_null(NodePath(str(PROFILE.BINDING)))
	if binding != null:
		history.add_do_method(binding, "refresh"); history.add_undo_method(binding, "refresh")

func _editable() -> bool:
	if not is_instance_valid(entity) or not entity.is_inside_tree(): return false
	var root := EditorInterface.get_edited_scene_root()
	return root != null and (entity == root or entity.owner == root or (root.is_ancestor_of(entity) and entity.owner != null and root.is_editable_instance(entity.owner)))
