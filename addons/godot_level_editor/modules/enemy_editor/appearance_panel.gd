@tool
extends HSplitContainer
signal appearance_changed(value: Resource)
signal operation_error(message: String)
const DATA := preload("res://addons/godot_level_editor/modules/enemy_editor/appearance_data.gd")
const VISUAL := preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd")
const IMPORT := preload("res://addons/godot_level_editor/modules/enemy_editor/model_import.gd")
const SLOTS := {"idle": "待机", "walk": "走路", "run": "跑步"}
var data: Resource
var fields: VBoxContainer
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var visual: CharacterModel
var pose_label: Label
var rest_button: Button
var file_dialog: EditorFileDialog
var import_kind := "model"
var importing := false
var options: Array[Dictionary] = []
var yaw := 0.25
var pitch := -0.12
var distance := 3.8
var dragging := false
var bone_mesh: MeshInstance3D
var show_bones := false
var bones_toggle: CheckBox
var _bound_signature := ""
var _binding_context := ""

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_box := VBoxContainer.new(); preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(preview_box)
	var bar := HFlowContainer.new(); preview_box.add_child(bar)
	rest_button = _button(bar, "T Pose", func():
		if visual != null: visual.reset_pose(); pose_label.text = visual.pose_status)
	for slot in SLOTS:
		_button(bar, "预览" + SLOTS[slot], func():
			if visual != null:
				visual.play(slot)
				pose_label.text = SLOTS[slot] if data != null and data.motions.has(slot) else visual.pose_status)
	bones_toggle = CheckBox.new(); bones_toggle.text = "显示骨骼"; bones_toggle.toggled.connect(func(value: bool): show_bones = value); bar.add_child(bones_toggle)
	var container := SubViewportContainer.new(); container.stretch = true; container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(340, 300); container.mouse_filter = Control.MOUSE_FILTER_STOP; preview_box.add_child(container)
	container.tooltip_text = "拖动旋转，滚轮缩放"
	container.gui_input.connect(_preview_input)
	viewport = SubViewport.new(); viewport.own_world_3d = true; viewport.size = Vector2i(640, 640)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE; container.add_child(viewport)
	stage = Node3D.new(); viewport.add_child(stage)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color("e6ebf1")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.4
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45, -35, 0); light.light_energy = 1.0; stage.add_child(light)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(20, 20); ground.mesh = plane
	var material := StandardMaterial3D.new(); material.albedo_color = Color("ced6df"); material.roughness = 1.0; ground.material_override = material; stage.add_child(ground)
	camera = Camera3D.new(); camera.fov = 35; stage.add_child(camera); camera.current = true
	bone_mesh = MeshInstance3D.new(); stage.add_child(bone_mesh)
	pose_label = Label.new(); preview_box.add_child(pose_label)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.x = 320; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	fields = VBoxContainer.new(); fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL; fields.add_theme_constant_override("separation", 10); scroll.add_child(fields)
	file_dialog = EditorFileDialog.new(); file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM; file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.glb, *.gltf, *.fbx, *.tscn, *.scn ; 三维模型、骨骼或动画"])
	file_dialog.file_selected.connect(import_file); add_child(file_dialog)
	_render_fields(); _camera()

func bind(value: Resource, context := "") -> void:
	var signature: String = value.signature() if value != null else "<none>"
	if signature == _bound_signature and context == _binding_context: return
	_binding_context = context
	_bound_signature = signature
	data = value
	if fields != null: _render_fields(); _rebuild_preview()

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = title; button.pressed.connect(callback); parent.add_child(button); return button

func _label(title: String) -> Label:
	var label := Label.new(); label.text = title; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; fields.add_child(label); return label

func _source_label(scene: PackedScene) -> String:
	return scene.resource_path.get_file() if scene != null else "未导入"

func _choose(kind: String) -> void:
	if importing: return
	import_kind = kind
	file_dialog.title = {"model": "导入 NPC 模型", "skeleton": "导入匹配骨骼", "animation": "添加动画来源"}[kind]
	file_dialog.popup_centered_ratio(0.7)

func _render_fields() -> void:
	for child in fields.get_children(): fields.remove_child(child); child.queue_free()
	_label("角色模型")
	_label(_source_label(data.model) if data != null else "未导入")
	_button(fields, "导入模型…", func(): _choose("model"))
	if data == null: return
	var height := SpinBox.new(); height.min_value = 0.1; height.max_value = 20; height.step = 0.05; height.suffix = " m"; height.value = data.height
	_label("角色身高"); fields.add_child(height)
	height.value_changed.connect(func(value: float):
		var candidate: Resource = data.duplicate(true); candidate.height = value; _commit(candidate, false))
	_label("静止姿态")
	var pose := OptionButton.new(); pose.add_item("T Pose（人形）"); pose.add_item("自然静止（动物／其他）")
	pose.select(1 if data.pose_mode == "rest" else 0); fields.add_child(pose)
	pose.item_selected.connect(func(index: int):
		var candidate: Resource = data.duplicate(true); candidate.pose_mode = "rest" if index == 1 else "humanoid_t"; _commit(candidate))
	_label("骨骼")
	var model := VISUAL.instantiate_model(data.model)
	if model == null: return
	var rigs := VISUAL.skeletons(model)
	var selected := OptionButton.new(); fields.add_child(selected)
	if rigs.is_empty(): selected.add_item("未检测到骨骼"); selected.disabled = true
	for rig in rigs:
		var path := model.get_path_to(rig)
		selected.add_item("%s · %d 根骨骼" % [rig.name, rig.get_bone_count()]); selected.set_item_metadata(selected.item_count - 1, path)
		if path == data.skeleton_path: selected.select(selected.item_count - 1)
	selected.item_selected.connect(func(index: int):
		var candidate: Resource = data.duplicate(true); candidate.skeleton_path = selected.get_item_metadata(index); candidate.skeleton_source = null; candidate.source_skeleton_path = NodePath(); candidate.motions = {}; _commit(candidate))
	var skeleton_bar := HFlowContainer.new(); fields.add_child(skeleton_bar)
	_button(skeleton_bar, "导入骨骼…", func(): _choose("skeleton"))
	if data.skeleton_source != null:
		_label("外部骨骼：" + _source_label(data.skeleton_source))
		_button(skeleton_bar, "使用模型骨骼", func():
			var candidate: Resource = data.duplicate(true); candidate.skeleton_source = null; candidate.source_skeleton_path = NodePath(); _commit(candidate))
	if not rigs.is_empty():
		var rig: Skeleton3D = model.get_node_or_null(data.skeleton_path) as Skeleton3D
		if rig == null: rig = rigs[0]
		var tree := Tree.new(); tree.custom_minimum_size.y = 130; tree.hide_root = true; fields.add_child(tree)
		tree.hide()
		var hierarchy := _button(skeleton_bar, "查看骨骼层级", func(): tree.visible = not tree.visible)
		hierarchy.toggle_mode = true
		var root := tree.create_item(); var items: Dictionary = {}
		for i in rig.get_bone_count():
			var item := tree.create_item(items.get(rig.get_bone_parent(i), root)); item.set_text(0, rig.get_bone_name(i)); items[i] = item
	model.free()
	_label("动画（可选）")
	_button(fields, "添加动画来源…", func(): _choose("animation"))
	options.clear()
	var sources: Array = [data.model]
	for source in data.animation_sources:
		if source != data.model: sources.append(source)
	for source in sources: options.append_array(VISUAL.animation_catalog(source))
	for slot in SLOTS:
		_label(SLOTS[slot])
		var choice := OptionButton.new(); choice.add_item("无（自然静止）" if data.pose_mode == "rest" else "无（T Pose）"); fields.add_child(choice)
		for motion in options:
			choice.add_item(str(motion.clip) + " · " + _source_label(motion.source))
			if _same_motion(data.motions.get(slot, {}), motion): choice.select(choice.item_count - 1)
		choice.item_selected.connect(func(index: int):
			var candidate: Resource = data.duplicate(true)
			if index == 0: candidate.motions.erase(slot)
			else: candidate.motions[slot] = options[index - 1].duplicate()
			_commit(candidate))

func _same_motion(a: Dictionary, b: Dictionary) -> bool:
	return a.get("clip") == b.get("clip") and a.get("player") == b.get("player") and _source_path(a.get("source")) == _source_path(b.get("source"))

func _source_path(scene: PackedScene) -> String:
	return scene.resource_path if scene != null else ""

func import_file(path: String) -> void:
	if importing: return
	importing = true
	var original_data := data
	var original_context := _binding_context
	operation_error.emit("正在导入…")
	await get_tree().process_frame
	var result := IMPORT.prepare(path)
	if result.has("error"):
		operation_error.emit(result.error); importing = false; return
	result = IMPORT.scene_snapshot(result.path, result.get("copied", false), path)
	if result.has("error"):
		operation_error.emit(result.error); importing = false; return
	if original_context != _binding_context or data != original_data:
		operation_error.emit("导入期间已切换 NPC 或修改外观，请重新选择文件。"); importing = false; return
	var source := ResourceLoader.load(result.path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if source == null: operation_error.emit("无法读取三维文件，请检查导入错误及贴图依赖。")
	else: apply_source(source, import_kind)
	var filesystem := EditorInterface.get_resource_filesystem()
	if not filesystem.is_scanning() and not filesystem.is_importing(): filesystem.scan()
	importing = false

func apply_source(source: PackedScene, kind: String) -> bool:
	var node := VISUAL.instantiate_model(source)
	if node == null: operation_error.emit("请选择三维模型场景。"); return false
	var rigs := VISUAL.skeletons(node)
	var candidate: Resource = data.duplicate(true) if data != null else DATA.new()
	if kind == "model":
		candidate.model = source; candidate.skeleton_path = node.get_path_to(rigs[0]) if not rigs.is_empty() else NodePath()
		candidate.skeleton_source = null; candidate.source_skeleton_path = NodePath(); candidate.motions = {}; candidate.animation_sources.clear()
	elif data == null:
		node.free(); operation_error.emit("请先导入角色模型。"); return false
	elif kind == "skeleton":
		if rigs.is_empty(): node.free(); operation_error.emit("所选文件没有 Skeleton3D 骨架。"); return false
		candidate.skeleton_source = source; candidate.source_skeleton_path = node.get_path_to(rigs[0])
	elif kind == "animation":
		if VISUAL.animation_catalog(source).is_empty(): node.free(); operation_error.emit("所选文件没有动画片段。"); return false
		if not candidate.animation_sources.has(source): candidate.animation_sources.append(source)
	node.free()
	return _commit(candidate)

func _commit(candidate: Resource, render_fields := true) -> bool:
	var probe := VISUAL.new(); probe.appearance = candidate; probe.setup()
	var errors: PackedStringArray = probe.errors; probe.free()
	if not errors.is_empty(): operation_error.emit("；".join(errors)); return false
	data = candidate
	_bound_signature = candidate.signature()
	appearance_changed.emit(candidate)
	_rebuild_preview()
	if render_fields: _render_fields()
	return true

func _rebuild_preview() -> void:
	if visual != null: stage.remove_child(visual); visual.queue_free(); visual = null
	rest_button.text = "自然静止" if data != null and data.pose_mode == "rest" else "T Pose"
	if data == null: pose_label.text = ""; return
	visual = VISUAL.new(); visual.appearance = data; stage.add_child(visual)
	pose_label.text = visual.pose_status
	if not visual.errors.is_empty(): operation_error.emit("；".join(visual.errors))
	distance = maxf(data.height * 2.2, 0.5); _camera()

func _camera() -> void:
	if camera == null: return
	var target := Vector3(0, data.height * 0.5 if data != null else 0.9, 0)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(-pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.3, 40); _camera()
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.01; pitch = clampf(pitch + event.relative.y * 0.01, -1.2, 1.2); _camera()

func _process(_delta: float) -> void:
	if bone_mesh == null: return
	bone_mesh.visible = show_bones and visual != null and visual.skeleton != null
	if not bone_mesh.visible: return
	var rig: Skeleton3D = visual.skeleton
	var mesh := ImmediateMesh.new(); var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color("1976d2"); material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for i in rig.get_bone_count():
		var parent := rig.get_bone_parent(i)
		if parent < 0: continue
		mesh.surface_add_vertex(rig.global_transform * rig.get_bone_global_pose(parent).origin)
		mesh.surface_add_vertex(rig.global_transform * rig.get_bone_global_pose(i).origin)
	mesh.surface_end(); bone_mesh.mesh = mesh
