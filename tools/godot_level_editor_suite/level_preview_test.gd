@tool
extends RefCounted
const PREVIEW := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_preview.gd")
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const WORLD := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/world.gd")
const BLOCK := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/whitebox_block.gd")
const SCENE := "res://content/scenes/levels/900001_preview_qa.tscn"
const BOOK := "user://preview_levels.xlsx"
var checks := 0
var failures := 0
var updates: Array[String] = []
var errors: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func frames(tree: SceneTree, count := 5) -> void:
	for i in count: await tree.process_frame
func settle(tree: SceneTree, service: Node) -> void:
	await frames(tree, 2)
	if service.is_busy(): await service.idle
func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	tree.create_timer(75, true).timeout.connect(func(): tree.quit(2))
	await tree.create_timer(0.7, true).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await tree.create_timer(0.1, true).timeout
	await tree.create_timer(0.5, true).timeout
	var output := "user://preview_evidence"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="): output = arg.trim_prefix("--qa-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var world := WORLD.new(); world.name = "PreviewQA"; world.level_id = "900001"
	var floor := BLOCK.new(); floor.name = "Floor"; floor.object_id = "floor"; floor.size = Vector3(20, 2, 16); world.add_child(floor); floor.owner = world
	var tower := MeshInstance3D.new(); tower.name = "FarTower"; tower.mesh = BoxMesh.new(); tower.mesh.size = Vector3(4, 30, 6); tower.position = Vector3(28, 15, -14); world.add_child(tower); tower.owner = world
	var packed := PackedScene.new(); packed.pack(world)
	check(ResourceSaver.save(packed, SCENE) == OK, "private fixture saves")
	world.free()
	var catalog := LEVELS.new()
	catalog.levels.append({"level_id":"900001", "name":"preview_qa", "display_name":"缩略图测试", "scene_path":SCENE, "notes":"original", "preview_path":""})
	catalog.next_id = 900002
	check(catalog.save_book(BOOK).is_empty(), "isolated workbook saves")
	var service: Node = suite.level_preview; service.workbook_path = BOOK
	service.preview_updated.connect(func(id, _scene, _path, _texture): updates.append(id); print("[PREVIEW] ", id))
	service.preview_failed.connect(func(_scene, reason): errors.append(reason))
	var panel: Control = suite.level_panel; panel.workbook_path = BOOK; panel.reload_catalog(); panel.select_level("900001")
	EditorInterface.get_resource_filesystem().update_file(SCENE)
	await frames(tree, 5)
	EditorInterface.open_scene_from_path(SCENE)
	for attempt in 120:
		var edited := EditorInterface.get_edited_scene_root()
		if edited != null and edited.scene_file_path == SCENE: break
		await tree.create_timer(0.03, true).timeout
	var root: Node3D = EditorInterface.get_edited_scene_root()
	check(root != null and root.scene_file_path == SCENE, "native editor opens private level")
	if root == null or root.scene_file_path != SCENE: tree.quit(1); return
	var camera := Camera3D.new(); root.add_child(camera)
	var box := AABB(Vector3(-16, -2, -25), Vector3(50, 42, 40))
	PREVIEW.frame_camera(camera, box)
	var fit := true
	for i in 8:
		var p: Vector3 = camera.global_transform.affine_inverse() * box.get_endpoint(i)
		fit = fit and absf(p.y) <= camera.size / 2 and absf(p.x) <= camera.size * 16.0 / 9 / 2 and -p.z > camera.near and -p.z < camera.far
	check(fit, "fixed bird's-eye camera fits all eight corners including tall / distant geometry")
	camera.free()
	var geometry: AABB = PREVIEW.geometry_bounds(root)
	check(geometry.end.x >= 30 and geometry.end.y >= 30 and geometry.position.x <= -10, "bounds include generated whiteboxes and ordinary meshes")
	var editor_camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var editor_view := editor_camera.global_transform
	if DisplayServer.get_name() == "headless":
		var saved: Array[String] = []
		suite.scene_saved.connect(func(path): saved.append(path))
		EditorInterface.save_scene_as(SCENE, false)
		check(saved.has(SCENE), "native save emits scene_saved without dummy-renderer readback")
	else: check(EditorInterface.save_scene() == OK, "native save succeeds and emits scene_saved")
	var source_hash := FileAccess.get_sha256(SCENE)
	await settle(tree, service)
	if DisplayServer.get_name() == "headless":
		check(updates.is_empty() and not service.is_busy(), "headless save skips thumbnail rendering")
		check(LEVELS.load_book(BOOK).catalog.by_id("900001").preview_path == "", "headless save keeps thumbnail metadata")
	else:
		check(updates.size() == 1, "native scene_saved automatically generates one thumbnail")
		var row: Dictionary = LEVELS.load_book(BOOK).catalog.by_id("900001")
		var target := str(row.preview_path)
		check(target == "res://content/resources/level_previews/900001.png" and FileAccess.file_exists(target), "generated path is persisted in the latest workbook")
		var image := Image.load_from_file(target)
		check(image != null and image.get_size() == PREVIEW.IMAGE_SIZE, "real renderer writes 1024x576 PNG")
		if image != null: image.save_png(output.path_join("birdseye_before.png"))
		check(FileAccess.get_sha256(SCENE) == source_hash and editor_camera.global_transform == editor_view, "capture preserves scene bytes and native editor camera")
		var card: Control = panel._cards["900001"]
		check(card.cover.texture != null and card.cover.texture == panel.detail_cover.texture, "card and selected details update together")
		var fresh: Texture2D = card.cover.texture
		card._preview(SCENE, card.placeholder_texture(), null, null)
		panel._detail_preview(SCENE, card.placeholder_texture(), null, "900001")
		check(card.cover.texture == fresh and panel.detail_cover.texture == fresh, "late built-in preview callbacks cannot replace the bird's-eye image")
		var before := FileAccess.get_md5(target)
		var baseline := updates.size()
		root.get_node("Floor").tint = Color("f09c52")
		EditorInterface.mark_scene_as_unsaved(); EditorInterface.save_scene()
		await frames(tree, 2)
		root.get_node("FarTower").position = Vector3(-24, 20, 12)
		EditorInterface.mark_scene_as_unsaved(); EditorInterface.save_scene()
		# A concurrent metadata edit must survive asynchronous rendering.
		var latest: Resource = LEVELS.load_book(BOOK).catalog
		latest.by_id("900001").notes = "metadata edited during capture"
		latest.save_book(BOOK)
		await settle(tree, service)
		check(updates.size() == baseline + 1 and FileAccess.get_md5(target) != before, "rapid saves merge and publish the latest changed geometry")
		check(LEVELS.load_book(BOOK).catalog.by_id("900001").notes == "metadata edited during capture", "concurrent unrelated workbook metadata survives")
		Image.load_from_file(target).save_png(output.path_join("birdseye_after.png"))
		baseline = updates.size()
		service.request("res://content/scenes/main.tscn"); await settle(tree, service)
		check(updates.size() == baseline and errors.is_empty(), "scenes outside the level catalog are ignored")
		var keep_hash := FileAccess.get_md5(target)
		service.output_directory = "res://project.godot/invalid"
		service.request(SCENE); await settle(tree, service)
		check(errors.size() == 1 and FileAccess.get_md5(target) == keep_hash and LEVELS.load_book(BOOK).catalog.by_id("900001").preview_path == target, "failed thumbnail write preserves the previous image and metadata")
		service.output_directory = "res://content/resources/level_previews"
		panel.reload_catalog()
		var created: Dictionary = panel.create_level("preview_new", "新关卡测试", "", null)
		await settle(tree, service)
		check(created.errors.is_empty() and updates.has("900002") and not LEVELS.load_book(BOOK).catalog.by_id("900002").preview_path.is_empty(), "new level creation also generates a thumbnail")
		var cancel_service := PREVIEW.new(); cancel_service.workbook_path = BOOK; suite.add_child(cancel_service)
		cancel_service.request(SCENE); await frames(tree, 2); cancel_service.dispose()
		await frames(tree, 8)
		check(not cancel_service.is_busy() and cancel_service._pending.is_empty(), "closing during capture cancels queued work cleanly")
		cancel_service.queue_free()
	# Visual evidence from actual authored scene copies, without editing sources.
	if DisplayServer.get_name() != "headless":
		service.workbook_path = LEVELS.PATH
		for actual in LEVELS.load_book().catalog.levels: service.request(str(actual.scene_path))
		await settle(tree, service)
		for actual in LEVELS.load_book().catalog.levels:
			if FileAccess.file_exists(str(actual.preview_path)):
				Image.load_from_file(ProjectSettings.globalize_path(str(actual.preview_path))).save_png(output.path_join("level_" + str(actual.level_id) + ".png"))
		panel.workbook_path = LEVELS.PATH; panel.reload_catalog(); panel.select_level("6")
		suite.show_window(); suite.open_tab("关卡"); panel.set_mode(0)
		await frames(tree, 10)
		await RenderingServer.frame_post_draw
		suite.window.get_texture().get_image().save_png(output.path_join("library.png"))
	print("LEVEL PREVIEW TEST: ", checks, " checks, ", failures, " failures")
	tree.quit(0 if failures == 0 else 1)
