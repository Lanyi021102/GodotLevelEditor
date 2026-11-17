extends Node
const VISUAL := preload("res://addons/godot_level_editor/modules/enemy_editor/npc_visual.gd")
const CATALOG := "res://addons/godot_level_editor/resources/enemies/samples_v1/catalog.json"
const OUTPUT := "res://docs/enemy_editor/samples_v1_2026-11-16"
const THUMB_SIZE := Vector2i(512, 512)
var images: Dictionary = {}
var font: SystemFont
var failures := 0

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"])
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	for row in catalog.samples: await capture(row)
	var humans: Array[Dictionary] = []
	for gender in ["male", "female"]:
		for size_category in ["small", "medium", "large"]:
			for row in catalog.samples:
				if row.category == "humanoid" and row.gender == gender and row.size_category == size_category: humans.append(row)
	var creatures: Array[Dictionary] = []
	for row in catalog.samples:
		if row.category != "humanoid": creatures.append(row)
	await contact_sheet(humans, 3, Vector2i(1800, 1540), "第一版示例 NPC · 人形", "小 / 中 / 大体型，各有男女 · 同一 2.7 m 视野，保留真实尺寸差异", "humanoids.png")
	await contact_sheet(creatures, 4, Vector2i(2000, 1360), "第一版示例 NPC · 动物与怪物", "四种动物与三种怪物 · 按模型边界适配视野，实际尺寸见卡片标注", "creatures.png")
	print("NPC SAMPLE CAPTURE: %d thumbnails, 2 sheets, %d failures" % [images.size(), failures])
	get_tree().quit(1 if failures else 0)

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func capture(row: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.name = "Capture_" + str(row.id)
	viewport.size = THUMB_SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stage := Node3D.new(); viewport.add_child(stage)
	var world := WorldEnvironment.new(); world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("e9eef5")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("e6edfa")
	world.environment.ambient_light_energy = 0.5
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(world)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-40, -35, 0); key.light_energy = 1.15; key.shadow_enabled = true; stage.add_child(key)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-20, 135, 0); fill.light_energy = 0.35; stage.add_child(fill)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(30, 30); ground.mesh = plane
	var material := StandardMaterial3D.new(); material.albedo_color = Color("dce3ed"); material.roughness = 1; ground.material_override = material; stage.add_child(ground)
	var definition := ResourceLoader.load(str(row.definition), "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyDefinition
	var visual := VISUAL.new(); visual.appearance = definition.appearance; stage.add_child(visual)
	if not visual.errors.is_empty():
		push_error(str(row.id) + ": " + "；".join(visual.errors)); failures += 1; viewport.queue_free(); return
	var meshes := visual.model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty(): push_error(str(row.id) + ": no renderable meshes"); failures += 1
	visual.play("idle", 0)
	visual.anim.advance(0.35)
	visual.anim.pause()
	await frames(3)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT; camera.near = 0.01; camera.far = 100; stage.add_child(camera); camera.current = true
	var combined := posed_bounds(visual.model)
	var center := combined.get_center()
	if row.category == "humanoid":
		center = Vector3(0, 1.14, 0)
		camera.size = 2.7
		camera.position = center + Vector3(0.55, 0.26, 1).normalized() * 8
		camera.look_at(center)
	else:
		camera.position = center + Vector3(0.8, 0.45, 1).normalized() * 8
		camera.look_at(center)
		var projected := Rect2()
		for i in 8:
			var point := camera.global_transform.affine_inverse() * combined.get_endpoint(i)
			if i == 0: projected = Rect2(Vector2(point.x, point.y), Vector2.ZERO)
			else: projected = projected.expand(Vector2(point.x, point.y))
		camera.size = maxf(projected.size.x, projected.size.y) * 1.27
	await frames(20)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := str(row.preview_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := image.save_png(path)
	if error != OK: push_error("Failed to save " + path); failures += 1
	else:
		images[row.id] = image
		print("[CAPTURE] ", row.id, " meshes=", meshes.size(), " pose=idle path=", path)
	viewport.queue_free()
	await frames(1)

func posed_bounds(model: Node3D) -> AABB:
	var combined := AABB(); var first := true
	for part in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := part as MeshInstance3D
		var local := mesh.get_aabb()
		if mesh.skin != null:
			var baked := mesh.bake_mesh_from_current_skeleton_pose()
			if baked != null: local = baked.get_aabb()
		var bounds := mesh.global_transform * local
		if first: combined = bounds; first = false
		else: combined = combined.merge(bounds)
	return combined

func label(parent: Control, text: String, position: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var result := Label.new(); result.text = text; result.position = position; result.size = size
	result.add_theme_font_override("font", font); result.add_theme_font_size_override("font_size", font_size); result.add_theme_color_override("font_color", color)
	parent.add_child(result); return result

func contact_sheet(rows: Array[Dictionary], columns: int, size: Vector2i, title: String, subtitle: String, filename: String) -> void:
	var viewport := SubViewport.new(); viewport.size = size; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(viewport)
	var canvas := Control.new(); canvas.size = size; viewport.add_child(canvas)
	var background := ColorRect.new(); background.color = Color("f1f5fa"); background.size = size; canvas.add_child(background)
	label(canvas, title, Vector2(48, 27), Vector2(size.x - 96, 60), 42, Color("172b45"))
	label(canvas, subtitle, Vector2(50, 94), Vector2(size.x - 100, 40), 25, Color("657891"))
	var margin := 48.0; var gap := 24.0
	var width := (float(size.x) - 2 * margin - gap * (columns - 1)) / columns
	var image_size := width - 30
	var card_height := image_size + 101
	var top := 165.0
	for i in rows.size():
		var row := rows[i]
		var card := Panel.new(); card.position = Vector2(margin + (i % columns) * (width + gap), top + int(i / columns) * (card_height + gap)); card.size = Vector2(width, card_height)
		var style := StyleBoxFlat.new(); style.bg_color = Color.WHITE; style.border_color = Color("d8e1ed")
		style.set_border_width_all(1); style.set_corner_radius_all(18); style.shadow_color = Color(0.08, 0.14, 0.23, 0.08); style.shadow_size = 8; style.shadow_offset = Vector2(0, 4)
		card.add_theme_stylebox_override("panel", style); canvas.add_child(card)
		if images.has(row.id):
			var texture := TextureRect.new(); texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.texture = ImageTexture.create_from_image(images[row.id]); texture.position = Vector2(15, 15); texture.size = Vector2(image_size, image_size)
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; card.add_child(texture)
		label(card, str(row.title).replace("·", " · "), Vector2(22, image_size + 23), Vector2(width - 44, 38), 27 if columns == 3 else 25, Color("223b59"))
		label(card, "%.2f m  ·  %d 根骨骼  ·  %d 段动画" % [float(row.height), int(row.bone_count), int(row.animation_count)], Vector2(22, image_size + 65), Vector2(width - 44, 28), 20, Color("6a7f98"))
	if columns == 4:
		var x := margin + 3 * (width + gap); var y := top + card_height + gap
		label(canvas, "Quaternius · CC0", Vector2(x + 20, y + 40), Vector2(width - 40, 45), 29, Color("34516f"))
		var note := label(canvas, "已接入模型、骨架和待机动画。\n\n奶牛、马另有行走／跑步动作；\n巴哥犬、绵羊原包仅有待机和跳跃。\n\n怪物包含待机、行走等动作。", Vector2(x + 20, y + 105), Vector2(width - 40, 290), 24, Color("657b96"))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label(canvas, "第一版素材库  /  2026.11.16  /  所有图像均为编辑器模型的实际渲染", Vector2(50, size.y - 56), Vector2(size.x - 100, 35), 21, Color("7a8da5"))
	await frames(10)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var error := viewport.get_texture().get_image().save_png(OUTPUT.path_join(filename))
	if error != OK: failures += 1; push_error("Failed to save sheet " + filename)
	else: print("[SHEET] ", OUTPUT.path_join(filename))
	viewport.queue_free()
	await frames(1)
