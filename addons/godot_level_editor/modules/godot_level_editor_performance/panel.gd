@tool
extends VBoxContainer

const DATA := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/sequence.gd")
const TIMELINE := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/timeline.gd")
const PREVIEW := preload("res://addons/godot_level_editor/modules/godot_level_editor_performance/preview.gd")
const DROP := preload("res://addons/godot_level_editor/modules/godot_level_editor/reference_drop.gd")
const GRAPH := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/level_graph.gd")

var suite: EditorPlugin
var module: EditorPlugin
var world: Node3D
var _sequence_id := ""
var _clip_id := ""
var _actor_id := ""
var _time := 0.0
var _playing := false
var _select: OptionButton
var _actor_select: OptionButton
var _actor_drop: Control
var _clip_menu: MenuButton
var _remove_sequence: Button
var _lock: OptionButton
var _play: Button
var _stop: Button
var _seek_label: Label
var _status: Label
var _details: VBoxContainer
var _body: VBoxContainer
var _timeline: Control
var _preview: SubViewportContainer
var _pick := {}

func _ready() -> void:
	name = "PerformancePanel"
	size_flags_vertical = SIZE_EXPAND_FILL
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_body)
	var toolbar := HBoxContainer.new()
	_body.add_child(toolbar)
	_select = _option(toolbar, [], _select_sequence)
	_select.size_flags_horizontal = SIZE_EXPAND_FILL
	_button(toolbar, "新建演出", _create)
	_remove_sequence = _button(toolbar, "删除演出", _delete_sequence)
	_button(toolbar, "保存关卡", _save)
	_button(toolbar, "撤销", _history.bind(false))
	_button(toolbar, "重做", _history.bind(true))
	var controls := HBoxContainer.new()
	_body.add_child(controls)
	_button(controls, "从视口取景", _capture_camera.bind(false))
	_actor_select = _option(controls, [], _select_actor)
	_actor_select.size_flags_horizontal = SIZE_EXPAND_FILL
	_actor_drop = DROP.new()
	_actor_drop.setup("NPC", "", _dropped_actor, _add_dropped_actor)
	_actor_drop.custom_minimum_size.x = 124
	controls.add_child(_actor_drop)
	_clip_menu = MenuButton.new()
	_clip_menu.text = "添加 NPC 片段"
	for kind in ["place", "move", "turn", "action"]: _clip_menu.get_popup().add_item(DATA.LABELS[kind])
	_clip_menu.get_popup().index_pressed.connect(_add_actor_clip)
	controls.add_child(_clip_menu)
	var playback := HBoxContainer.new()
	_body.add_child(playback)
	_play = _button(playback, "播放", _toggle_play)
	_stop = _button(playback, "停止预览", stop_preview)
	_button(playback, "回到开头", _seek.bind(0.0))
	_seek_label = Label.new()
	_seek_label.custom_minimum_size.x = 90
	playback.add_child(_seek_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	playback.add_child(spacer)
	_lock = _option(playback, ["自动切换操作权", "保留玩家操作", "锁定玩家操作"], _change_lock)
	_lock.custom_minimum_size.x = 132
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 140
	_body.add_child(scroll)
	_timeline = TIMELINE.new()
	_timeline.size_flags_horizontal = SIZE_EXPAND_FILL
	_timeline.size_flags_vertical = SIZE_EXPAND_FILL
	_timeline.seek_requested.connect(_seek)
	_timeline.selected.connect(_select_clip)
	_timeline.clip_changed.connect(_change_clip_time)
	scroll.add_child(_timeline)
	var middle := HSplitContainer.new()
	middle.custom_minimum_size.y = 110
	middle.size_flags_vertical = SIZE_EXPAND_FILL
	middle.size_flags_stretch_ratio = 2.0
	_body.add_child(middle)
	var preview_card := PanelContainer.new()
	preview_card.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_card.size_flags_stretch_ratio = 2.0
	var preview_stack := VBoxContainer.new()
	preview_card.add_child(preview_stack)
	var tip := Label.new()
	tip.text = "点击时间尺预览镜头和走位"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.size_flags_vertical = SIZE_EXPAND_FILL
	preview_stack.add_child(tip)
	_preview = PREVIEW.new()
	preview_stack.add_child(_preview)
	_preview.visibility_changed.connect(func(): tip.visible = not _preview.visible)
	middle.add_child(preview_card)
	var details_scroll := ScrollContainer.new()
	details_scroll.custom_minimum_size.x = 286
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(details_scroll)
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = SIZE_EXPAND_FILL
	details_scroll.add_child(_details)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): stop_preview()
		else: _refresh())
	_refresh()

func bind_world(value: Node3D) -> void:
	if world == value: return
	stop_preview()
	if is_instance_valid(world) and world.performances_changed.is_connected(_on_sequences_changed):
		world.performances_changed.disconnect(_on_sequences_changed)
	world = value
	_sequence_id = ""
	_clip_id = ""
	_actor_id = ""
	_time = 0.0
	_pick = {}
	if is_instance_valid(world): world.performances_changed.connect(_on_sequences_changed)
	if is_node_ready(): _refresh()

func _on_sequences_changed() -> void:
	_refresh_after_edit.call_deferred(_preview.visible)

func _refresh_after_edit(was_previewing: bool) -> void:
	if not is_instance_valid(_preview): return
	stop_preview()
	_refresh()
	if was_previewing and is_visible_in_tree(): _seek(_time)

func _data() -> Resource:
	return DATA.lookup(world, _sequence_id)

func _new_clip(kind: String) -> Dictionary:
	return {"id": GRAPH.fresh_id("clip"), "kind": kind, "label": DATA.LABELS[kind], "actor": _actor_id if kind != "camera" else "", "start": snappedf(_time, TIMELINE.SNAP), "duration": 1.0}

func _create() -> void:
	var item := DATA.new()
	item.id = GRAPH.fresh_id("performance")
	var names := DATA.choices(world).values()
	var attempt := 1
	while "演出 %d" % attempt in names: attempt += 1
	item.display_name = "演出 %d" % attempt
	_sequence_id = item.id
	_clip_id = ""
	_time = 0.0
	var after: Array = world.performances.duplicate()
	after.append(item)
	_commit(after, "新建演出")

func _delete_sequence() -> void:
	var after: Array = world.performances.duplicate()
	after.erase(_data())
	_sequence_id = ""
	_clip_id = ""
	_commit(after, "删除演出")

func _commit(after: Array, caption: String) -> void:
	var history := suite.get_undo_redo()
	history.create_action(caption, UndoRedo.MERGE_DISABLE, world)
	history.add_do_property(world, "performances", after)
	history.add_undo_property(world, "performances", world.performances.duplicate())
	history.commit_action()

func _replace(item: Resource, caption: String) -> void:
	var after: Array = world.performances.duplicate()
	for index in after.size():
		if after[index].id == item.id:
			after[index] = item
			_commit(after, caption)
			return

func _draft() -> Resource:
	var original := _data()
	if original == null: return null
	var item: Resource = original.duplicate()
	item.clips = original.clips.duplicate(true)
	return item

func _clip(item: Resource) -> Dictionary:
	for clip in item.clips:
		if clip.id == _clip_id: return clip
	return {}

func _save() -> void:
	stop_preview()
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path.is_empty() or root.scene_file_path.begins_with("res://addons/"):
		_set_status("请先用 Godot 的「另存为」将关卡保存到作品目录。")
		return
	var error := OK
	if DisplayServer.get_name() == "headless": EditorInterface.save_scene_as(root.scene_file_path, false)
	else: error = EditorInterface.save_scene()
	_set_status("关卡已保存" if error == OK else "请先在 Godot 中另存当前关卡。")

func _history(redo: bool) -> void:
	if not is_instance_valid(world): return
	var manager := suite.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(world))
	if history == null: return
	if redo: history.redo()
	else: history.undo()

func _select_sequence(index: int) -> void:
	stop_preview()
	_sequence_id = str(_select.get_item_metadata(index))
	_clip_id = ""
	_actor_id = ""
	_time = 0.0
	_refresh()

func _select_actor(index: int) -> void:
	var key := str(_actor_select.get_item_metadata(index))
	if key.is_empty(): return
	var item := _draft()
	_actor_id = key
	if not key in item.actors:
		item.actors.append(key)
		_replace(item, "添加 NPC 轨道")
	else:
		_refresh()

func _dropped_actor(data: Variant) -> String:
	if not is_instance_valid(world) or _data() == null or not data is Dictionary or data.get("type") != "nodes": return ""
	var paths: Array = data.get("nodes", [])
	var root := EditorInterface.get_edited_scene_root()
	if paths.size() != 1 or root == null: return ""
	var node := root.get_node_or_null(paths[0])
	var candidates := DATA.npc_choices(world)
	while node != null and node != world:
		var reference: Variant = candidates.find_key(node)
		if reference is String: return reference
		node = node.get_parent()
	return ""

func _add_dropped_actor(data: Variant) -> void:
	var key := _dropped_actor(data)
	if key.is_empty(): return
	for index in _actor_select.item_count:
		if _actor_select.get_item_metadata(index) == key:
			_select_actor(index)
			return
	# Native scene-tree changes can arrive before the editor panel refreshes.
	_refresh()
	for index in _actor_select.item_count:
		if _actor_select.get_item_metadata(index) == key:
			_select_actor(index)
			return

func _change_lock(index: int) -> void:
	var item := _draft()
	if item == null: return
	item.input_mode = index
	_replace(item, "设置演出操作权")

func _select_clip(id: String) -> void:
	_clip_id = id
	var clip := _clip(_data())
	if clip.kind != "camera": _actor_id = clip.actor
	_refresh()

func _add_to(item: Resource, clip: Dictionary, caption: String) -> void:
	var track := DATA.track_of(clip)
	for other in item.ordered_clips():
		if DATA.track_of(other) == track and clip.start < DATA.end_of(other) and DATA.end_of(clip) > other.start:
			clip.start = DATA.end_of(other)
	if DATA.end_of(clip) > DATA.MAX_TIME:
		_set_status("演出最长可编辑到 300 秒。")
		return
	item.clips.append(clip)
	_clip_id = clip.id
	_replace(item, caption)

func _add_actor_clip(index: int) -> void:
	var item := _draft()
	var actor: Node3D = DATA.npc_choices(world).get(_actor_id)
	if item == null or actor == null: return
	var kind: String = ["place", "move", "turn", "action"][index]
	var clip := _new_clip(kind)
	if kind == "action":
		var names := DATA.motion_names(actor)
		if names.is_empty(): return
		clip.motion = names[0]
		_add_to(item, clip, "添加播放动作片段")
		return
	if kind == "move":
		clip.via = PackedVector3Array()
		clip.duration = 2.0
	else: clip.duration = DATA.MIN_LENGTH
	_open_picker({"sequence": _sequence_id, "new_clip": clip})

func _editor_camera() -> Camera3D:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	return viewport.get_camera_3d() if viewport != null else null

func _capture_camera(replace_existing: bool) -> void:
	var item := _draft()
	var camera := _editor_camera()
	if item == null or camera == null: return
	var clip := _clip(item) if replace_existing else _new_clip("camera")
	if clip.is_empty(): return
	clip.pose = world.global_transform.affine_inverse() * camera.global_transform.orthonormalized()
	clip.fov = camera.fov
	clip.projection = camera.projection
	clip.size = camera.size
	clip.keep_aspect = camera.keep_aspect
	if replace_existing: _replace(item, "更新镜头构图")
	else: _add_to(item, clip, "添加镜头")

func _begin_pick(field: String) -> void:
	if not is_instance_valid(world) or _clip(_data()).is_empty(): return
	_open_picker({"sequence": _sequence_id, "clip": _clip_id, "field": field})

func _open_picker(request: Dictionary) -> void:
	_pick = request
	module.performance_point_pick = _receive_pick
	stop_preview()
	suite.focus_native_3d()
	module.show_message("在视口左键选点，按 Esc 取消。")

func _receive_pick(point: Variant) -> void:
	var target := _pick
	_pick = {}
	if target.is_empty() or target.sequence != _sequence_id: return
	var item := _draft()
	if item == null: return
	if point is Vector3:
		var local := world.to_local(point)
		if target.has("new_clip"):
			var clip: Dictionary = target.new_clip
			clip.point = local
			_add_to(item, clip, "添加" + DATA.LABELS[clip.kind] + "片段")
		elif target.clip == _clip_id:
			var clip := _clip(item)
			if not clip.is_empty():
				if target.field == "via": clip.via.append(local)
				else: clip.point = local
				_replace(item, "设置演出选点")
	suite.show_window()

func _update_clip(key: String, value: Variant) -> void:
	var item := _draft()
	var clip := _clip(item)
	if clip.is_empty() or clip.get(key) == value: return
	clip[key] = value
	_replace(item, "编辑演出片段")

func _change_clip_time(id: String, start: float, length: float) -> void:
	var original := _clip(_data())
	if original.get("id") == id and is_equal_approx(original.start, start) and is_equal_approx(original.duration, length): return
	var item := _draft()
	_clip_id = id
	var clip := _clip(item)
	if clip.is_empty(): return
	clip.start = start
	clip.duration = length
	if DATA.end_of(clip) > DATA.MAX_TIME:
		_set_status("片段结束时间必须在 300 秒以内。")
		_refresh_details(item)
		return
	var track := DATA.track_of(clip)
	for other in item.clips:
		if other.id != id and DATA.track_of(other) == track and start + 0.0001 < DATA.end_of(other) and DATA.end_of(clip) > float(other.start) + 0.0001:
			_set_status("同一轨道的片段不能重叠。")
			_refresh_details(item)
			return
	_replace(item, "调整演出时间")

func _toggle_play() -> void:
	if _playing:
		_playing = false
		_update_transport()
		return
	var item := _data()
	if item == null or item.clips.is_empty(): return
	_seek(0.0 if _time >= item.duration() else _time)
	_playing = true
	_update_transport()

func _seek(value: float) -> void:
	var item := _data()
	if item == null: return
	_time = clampf(value, 0.0, DATA.MAX_TIME)
	if not _preview.visible: _preview.start(world, item, _editor_camera())
	_preview.sample(_time)
	_update_transport()

func stop_preview() -> void:
	_playing = false
	if is_instance_valid(_preview): _preview.stop()
	if is_instance_valid(_play): _update_transport()

func _process(delta: float) -> void:
	if not _playing: return
	var item := _data()
	if item == null: stop_preview(); return
	var end: float = item.duration()
	_seek(minf(_time + delta, end))
	if _time >= end:
		_playing = false
		_update_transport()

func _update_transport() -> void:
	var data := _data()
	_play.disabled = data == null or data.clips.is_empty()
	_play.text = "暂停" if _playing else "播放"
	_stop.disabled = not _preview.visible
	_seek_label.text = "%.1f / %.1f 秒" % [_time, data.duration() if data != null else 0.0]
	_timeline.set_time(_time)

func _refresh() -> void:
	if not is_node_ready(): return
	_body.visible = is_instance_valid(world)
	if not _body.visible:
		_set_status("打开一个关卡场景后编辑演出。")
		return
	var names := DATA.choices(world)
	if not names.has(_sequence_id): _sequence_id = str(names.keys()[0]) if not names.is_empty() else ""
	var item := _data()
	_fill_options(_select, names if not names.is_empty() else {"": "还没有演出"}, _sequence_id)
	_select.disabled = names.is_empty()
	_remove_sequence.disabled = item == null
	_lock.disabled = item == null
	_lock.select(item.input_mode if item != null else 0)
	var actors := DATA.npc_choices(world)
	var labels := {}
	var options := {"": "选择 NPC"}
	for key in actors:
		var node: Node = actors[key]
		labels[key] = str(node.get_meta("editor_display_name", node.name))
		options[key] = labels[key] + ("（添加轨道）" if item != null and not key in item.actors else "")
	if not actors.has(_actor_id): _actor_id = ""
	_fill_options(_actor_select, options, _actor_id)
	_actor_select.disabled = item == null or actors.is_empty()
	_actor_drop.visible = item != null
	_clip_menu.disabled = item == null or _actor_id.is_empty()
	if not _clip_menu.disabled:
		_clip_menu.get_popup().set_item_disabled(3, DATA.motion_names(actors[_actor_id]).is_empty())
	_timeline.update_timeline(item, labels, _clip_id)
	_update_transport()
	_refresh_details(item)
	var errors: PackedStringArray = item.validate(world, "", false) if item != null else PackedStringArray()
	var message := "；".join(errors)
	if item == null: message = "新建一段演出，添加镜头或 NPC。"
	elif item.clips.is_empty(): message = "在 3D 视口摆好构图后点「从视口取景」，或添加 NPC 轨道。"
	_set_status(message)

func _set_status(message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()

func _refresh_details(item: Resource) -> void:
	for child in _details.get_children():
		_details.remove_child(child)
		child.queue_free()
	if item == null: return
	_line(_details, "演出名称", item.display_name, func(value: String):
		if value.strip_edges().is_empty(): return
		var draft := _draft()
		if draft == null or draft.display_name == value.strip_edges(): return
		draft.display_name = value.strip_edges()
		_replace(draft, "重命名演出"))
	var clip := _clip(item)
	if clip.is_empty(): return
	_line(_details, "片段名称", str(clip.label), func(value: String):
		if not value.strip_edges().is_empty(): _update_clip("label", value.strip_edges()))
	_number(_details, "开始（秒）", clip.start, 0.0, DATA.MAX_TIME - clip.duration, 0.1, func(value: float): _change_clip_time(str(clip.id), value, float(clip.duration)))
	if clip.kind not in ["place", "turn"]:
		_number(_details, "时长（秒）", clip.duration, DATA.MIN_LENGTH, DATA.MAX_TIME - clip.start, 0.1, func(value: float): _change_clip_time(str(clip.id), float(clip.start), value))
	match str(clip.kind):
		"camera":
			_button(_details, "更新为当前 3D 视角", _capture_camera.bind(true))
			if clip.get("projection", Camera3D.PROJECTION_PERSPECTIVE) == Camera3D.PROJECTION_ORTHOGONAL:
				_number(_details, "正交尺寸", clip.get("size", 6.0), 0.1, 1000.0, 0.1, func(value: float): _update_clip("size", value))
			else:
				_number(_details, "视野角", clip.get("fov", 65.0), 1.0, 179.0, 1.0, func(value: float): _update_clip("fov", value))
		"place", "move", "turn":
			_button(_details, "在视口选点", _begin_pick.bind("point"))
			if clip.kind == "move":
				_button(_details, "添加途经点（%d）" % clip.via.size(), _begin_pick.bind("via"))
				if not clip.via.is_empty(): _button(_details, "清除途经点", _update_clip.bind("via", PackedVector3Array()))
		"action":
			var actor: Node3D = DATA.npc_choices(world).get(str(clip.actor))
			if actor != null:
				var motions := DATA.motion_names(actor)
				var options := {}
				for motion in motions: options[motion] = motion
				var field := _option(_details, [], func(index: int): _update_clip("motion", motions[index]))
				_fill_options(field, options, str(clip.motion))
	_button(_details, "删除片段", _delete_clip)

func _delete_clip() -> void:
	var item := _draft()
	item.clips.erase(_clip(item))
	_clip_id = ""
	_replace(item, "删除演出片段")

func _button(parent: Control, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _option(parent: Control, labels: Array, action: Callable) -> OptionButton:
	var field := OptionButton.new()
	field.fit_to_longest_item = false
	for caption in labels: field.add_item(caption)
	field.item_selected.connect(action)
	parent.add_child(field)
	return field

func _fill_options(field: OptionButton, names: Dictionary, active: String) -> void:
	field.clear()
	for key in names:
		field.add_item(names[key])
		var index := field.item_count - 1
		field.set_item_metadata(index, key)
		if key == active: field.select(index)

func _line(parent: Control, caption: String, value: String, action: Callable) -> void:
	var field := LineEdit.new()
	field.placeholder_text = caption
	field.tooltip_text = caption
	field.text = value
	field.text_submitted.connect(action)
	field.focus_exited.connect(func():
		if field.is_inside_tree(): action.call(field.text))
	parent.add_child(field)

func _number(parent: Control, caption: String, value: float, minimum: float, maximum: float, step: float, action: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.value = value
	field.value_changed.connect(action)
	row.add_child(field)
	parent.add_child(row)
