@tool
extends RefCounted
var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("[PASS] " if value else "[FAIL] ", label)

func frames(tree: SceneTree, count := 8) -> void:
	for i in count: await tree.process_frame

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	suite.show_window()
	await frames(tree, 40)
	var results := {}
	print("PERF_NAV_START")
	for title in ["关卡", "机关", "敌人", "任务", "台本", "天空", "工作台"]:
		var samples: Array[float] = []
		var gaps: Array[float] = []
		for i in 12:
			suite.navigation_buttons["其他"].pressed.emit()
			await frames(tree, 3)
			var start := Time.get_ticks_usec()
			suite.navigation_buttons[title].pressed.emit()
			samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
			await tree.process_frame
			gaps.append(float(Time.get_ticks_usec() - start) / 1000.0)
			await frames(tree, 3)
		samples.sort(); gaps.sort()
		results[title] = {"callback_median_ms": samples[6], "callback_max_ms": samples.max(), "next_frame_median_ms": gaps[6], "next_frame_max_ms": gaps.max()}
	print("PERF_NAV_END ", JSON.stringify(results))
	if not OS.get_cmdline_user_args().has("--baseline"):
		await regressions(suite)
	if OS.get_cmdline_user_args().has("--capture"):
		DirAccess.make_dir_recursive_absolute("res://docs/godot_level_editor_suite/navigation_performance_2026-11-16")
		for title in ["关卡", "机关", "敌人"]:
			suite.navigation_buttons[title].pressed.emit()
			await frames(tree, 20)
			RenderingServer.force_draw(false)
			suite.window.get_texture().get_image().save_png("res://docs/godot_level_editor_suite/navigation_performance_2026-11-16/" + title + ".png")
	print("PERF_CHECKS ", checks, " FAILURES ", failures)
	tree.quit(1 if failures else 0)

func regressions(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	var mechanism: Control = suite.asset_panels["机关"]
	var npc: Control = suite.asset_panels["敌人"]
	var npc_path := "res://addons/godot_level_editor/resources/enemies/samples_v1/human_medium_male.tres"
	var mechanism_path := "res://addons/godot_level_editor/scenes/mechanisms/single_door.tscn"
	check(mechanism.entries.has(mechanism_path) and not mechanism.entries.has("res://addons/godot_level_editor/scenes/mechanisms/lever.tscn"), "mechanism catalog retains assemblies and excludes component-only scenes")
	for title in ["关卡", "机关", "敌人"]:
		suite.navigation_buttons[title].pressed.emit()
		var workspace: Control = suite.level_panel if title == "关卡" else suite.asset_panels[title]
		var card: Control = workspace._cards.values()[0] if title == "关卡" else workspace.cards.values()[0]
		var instance := card.get_instance_id()
		for i in 5:
			suite.navigation_buttons["工作台"].pressed.emit()
			suite.navigation_buttons[title].pressed.emit()
		check(is_instance_valid(card) and card.get_instance_id() == instance and not card.is_queued_for_deletion(), title + " navigation reuses catalog cards")
	npc.search.text = "guard"; npc._filter(); npc.select_asset(npc_path)
	var retained: Control = npc.cards[npc_path]
	suite.navigation_buttons["工作台"].pressed.emit()
	npc._filesystem_changed(); npc._filesystem_changed()
	check(npc._catalog_dirty and npc.cards[npc_path] == retained, "hidden catalog defers filesystem work")
	suite.navigation_buttons["敌人"].pressed.emit()
	await frames(tree)
	check(npc.cards[npc_path] == retained and npc.search.text == "guard" and npc.selected_path == npc_path, "unrelated filesystem notifications preserve cards, search and selection")
	npc.search.text = ""; npc._filter()
	# All disk mutation stays in a disposable project copy when this test is run.
	var fixture := "res://content/resources/enemies/navigation_performance_%d.tres" % OS.get_process_id()
	var definition: Resource = preload("res://addons/godot_level_editor/modules/enemy_editor/runtime/guard_template.gd").create()
	definition.display_name = "性能检查甲"
	check(ResourceSaver.save(definition, fixture) == OK, "NPC fixture saves")
	npc._filesystem_changed(); npc.ensure_catalog()
	check(npc.entries.has(fixture) and npc.entries[fixture].display_name == "性能检查甲", "new NPC appears after invalidation")
	definition.display_name = "性能检查乙"
	ResourceSaver.save(definition, fixture)
	npc._filesystem_changed(); npc.ensure_catalog()
	check(npc.entries[fixture].display_name == "性能检查乙", "same-size same-second NPC edits bypass stale metadata")
	npc.editing_path = npc_path; npc.set_mode(1)
	definition.display_name = "性能检查丙"; ResourceSaver.save(definition, fixture)
	npc._filesystem_changed()
	check(npc._catalog_dirty, "filesystem changes defer while editing an NPC")
	npc.set_mode(0)
	check(npc.entries[fixture].display_name == "性能检查丙", "returning through My NPCs secondary tab refreshes changed resources")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	npc._filesystem_changed(); npc.ensure_catalog()
	check(not npc.entries.has(fixture), "deleted NPC leaves the catalog")
	# Modify a copy of a paired graph, never a user mechanism.
	var mechanism_fixture := "res://addons/godot_level_editor/scenes/mechanisms/navigation_performance_%d.tscn" % OS.get_process_id()
	var root := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/factory.gd").sample()
	root.definition.display_name = "性能检查门甲"
	var saved := preload("res://addons/godot_level_editor/modules/godot_level_editor_mechanisms/store.gd").save_pair(root, mechanism_fixture)
	root.free()
	check(saved.ok, "mechanism fixture saves")
	mechanism._filesystem_changed(); mechanism.ensure_catalog()
	check(mechanism.entries.has(mechanism_fixture) and mechanism.entries[mechanism_fixture].display_name == "性能检查门甲", "new paired mechanism appears without instantiating its scene")
	var graph_path := mechanism_fixture.get_basename() + ".graph.tres"
	var graph: Resource = ResourceLoader.load(graph_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	graph.display_name = "性能检查门乙"; ResourceSaver.save(graph, graph_path)
	mechanism._filesystem_changed(); mechanism.ensure_catalog()
	check(mechanism.entries[mechanism_fixture].display_name == "性能检查门乙", "external paired graph changes refresh despite cached scene dependencies")
	var inherited := mechanism_fixture.get_basename() + "_inherited.tscn"
	var file := FileAccess.open(inherited, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="' + mechanism_fixture + '" id="1"]\n\n[node name="Inherited" instance=ExtResource("1")]\n')
	file.close()
	mechanism._filesystem_changed(); mechanism.ensure_catalog()
	check(mechanism.entries.has(inherited) and mechanism.entries[inherited].display_name == "性能检查门乙", "inherited mechanism scenes retain catalog compatibility")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(inherited))
	for path in [mechanism_fixture, graph_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	mechanism._filesystem_changed(); mechanism.ensure_catalog()
	check(not mechanism.entries.has(mechanism_fixture), "deleted mechanism leaves the catalog")
	var card_script := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/level_card.gd")
	var preview := "res://content/resources/navigation_performance_%d.png" % OS.get_process_id()
	var image := Image.create(1024, 512, false, Image.FORMAT_RGB8)
	image.fill(Color.RED); image.save_png(preview)
	var first := card_script.preview_texture(preview)
	check(first != null and first == card_script.preview_texture(preview) and first.get_width() == 768, "covers share a bounded-size decoded texture")
	image.fill(Color.BLUE); image.save_png(preview)
	var second := card_script.preview_texture(preview)
	check(second != first and second.get_image().get_pixel(0, 0).b > 0.9, "rewritten PNG invalidates the cover cache immediately")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preview))
	check(card_script.preview_texture(preview) == null, "deleted PNG falls back without a stale cover")
	# Force refresh is still available, and search/selection remain valid.
	npc.reload_catalog()
	check(npc.entries.has(npc_path) and npc.selected_path == npc_path, "manual refresh retains valid catalog selection")
	suite.navigation_buttons["机关"].pressed.emit(); mechanism.select_asset(mechanism_path)
	var thumbnail := str(mechanism.entries[mechanism_path].get("preview_path", ""))
	check(mechanism.cards[mechanism_path].cover.texture == card_script.preview_texture(thumbnail) and mechanism.detail_cover.texture == mechanism.cards[mechanism_path].cover.texture, "card and detail share the same cover texture")
	for i in 24:
		var transient := Button.new(); suite.window.add_child(transient); transient.free()
	var surviving := Button.new(); suite.window.add_child(surviving)
	await frames(tree)
	check(surviving.has_meta("godot_level_editor_button_motion"), "deferred button styling tolerates freed controls and initializes live controls")
	surviving.free()
