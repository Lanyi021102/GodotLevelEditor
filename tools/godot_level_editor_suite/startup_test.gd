@tool
extends RefCounted
var checks := 0
var failures := 0

class CacheProbe:
	extends "res://addons/godot_level_editor/modules/godot_level_editor_suite/asset_workspace.gd"
	var scans := 0
	func _scan(folder: String) -> void:
		scans += 1
		super._scan(folder)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func frames(tree: SceneTree, count := 12) -> void:
	for i in count: await tree.process_frame

func probe(suite: EditorPlugin) -> Control:
	var result := CacheProbe.new()
	result.kind = "NPC"; result.module = suite.modules.enemies; result.editor = result.module.panel
	result.hide(); suite.window.add_child(result)
	return result

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	await frames(tree, 20)
	check(not suite._built and not is_instance_valid(suite.window), "normal startup does not construct the independent window")
	check(not is_instance_valid(suite.level_panel) and not is_instance_valid(suite.sky_panel) and suite.asset_panels.is_empty(), "unvisited page widgets and catalogs do not initialize at startup")
	check(is_instance_valid(suite.level_preview) and suite.sky_export != null, "scene preview and export services remain available before opening the window")
	var backends := {}
	for module in tree.get_nodes_in_group("godot_level_editor_suite_modules"):
		backends[str(module.get_meta("godot_level_editor_module"))] = module
	check(backends.size() == 4 and backends.mechanisms.native_guard.enabled, "all four backends and native mechanism save protection register immediately")
	check(backends.level.radial_tool != null and is_instance_valid(backends.level.radial_tool.button), "native 3D placement tools are ready without the independent window")
	check(suite._get_unsaved_status("").is_empty(), "unsaved status query tolerates uninitialized pages")
	suite._save_external_data()
	check(not suite._built, "native save callback does not build hidden UI")
	check(suite._build(), "play build hook accepts the project before any workspace is opened")
	await frames(tree, 2)
	check(not suite._built and not suite._starting_play, "play launch preparation does not build hidden UI")
	var start := Time.get_ticks_usec()
	suite.show_window()
	print("STARTUP_TEST_OPEN_MS ", (Time.get_ticks_usec() - start) / 1000.0)
	await frames(tree)
	check(suite._built and suite.window.visible and suite.tabs.get_tab_count() == 9, "first explicit open creates the window with all navigation targets")
	check(suite._prepared_pages.keys() == ["工作台"] and suite.asset_panels.is_empty() and suite.level_panel == null, "first open builds only the workbench")
	EditorInterface.open_scene_from_path("res://content/scenes/levels/whitebox_world.tscn")
	await frames(tree, 20)
	suite.open_tab("天空")
	var sky: Control = suite.sky_panel
	var book := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd").load_book()
	var level_row: Dictionary = book.catalog.for_world(sky.current_world())
	check(suite.level_panel == null and not level_row.is_empty() and sky.target.text.contains(str(level_row.display_name)), "opening Sky first preserves the Chinese level name without building Levels")
	suite.navigation_buttons["关卡"].pressed.emit()
	check(suite.level_panel != null and suite.level_panel.catalog != null and suite.sky_panel == sky and suite.asset_panels.is_empty(), "opening Levels initializes only the level page")
	var level: Control = suite.level_panel
	suite.navigation_buttons["工作台"].pressed.emit(); suite.navigation_buttons["关卡"].pressed.emit()
	check(suite.level_panel == level, "reopening a page reuses its existing controls")
	suite.navigation_buttons["敌人"].pressed.emit()
	var catalog: Control = suite.asset_panels["敌人"]
	check(not catalog.entries.is_empty() and not suite.asset_panels.has("机关") and suite.event_panel == null, "NPC visit initializes its own catalog without unrelated pages")
	catalog._store_catalog_cache()
	var cached := probe(suite)
	check(cached.scans == 0 and cached.entries.keys() == catalog.entries.keys(), "valid disk metadata cache restores without loading NPC definitions or models")
	cached.free()
	var fixture := "res://content/resources/enemies/startup_test_%d.tres" % OS.get_process_id()
	var definition := preload("res://addons/godot_level_editor/modules/enemy_editor/runtime/guard_template.gd").create()
	definition.display_name = "启动检查甲"; ResourceSaver.save(definition, fixture)
	var changed := probe(suite)
	check(changed.scans > 0 and changed.entries.has(fixture), "new files invalidate the persistent catalog cache")
	var ordered := probe(suite)
	check(ordered.scans == 0 and ordered.entries.keys() == changed.entries.keys(), "cache round-trip preserves root-file and nested-folder ordering")
	ordered.free()
	changed.free()
	definition.display_name = "启动检查乙"; ResourceSaver.save(definition, fixture)
	var rewritten := probe(suite)
	check(rewritten.scans > 0 and rewritten.entries[fixture].display_name == "启动检查乙", "same-size same-second writes invalidate cached metadata")
	rewritten.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	catalog.reload_catalog()
	var file := FileAccess.open(catalog._cache_path(), FileAccess.WRITE)
	file.store_string("{invalid json"); file.close()
	var damaged := probe(suite)
	check(damaged.scans > 0 and not damaged.entries.has(fixture), "damaged cache rebuilds from source without losing real entries")
	damaged.free()
	suite.open_tab("任务图")
	check(suite.task_graph.get_window() == suite.window and suite.event_panel == null, "task graph can open directly without the event table")
	suite.open_tab("台本")
	check(suite.modules.narrative.dialogue_panel.get_window() == suite.window, "dialogue backend is adopted on demand")
	suite.open_tab("机关")
	check(suite.asset_panels["机关"].editor_host.is_ancestor_of(suite.modules.mechanisms.panel), "mechanism editor keeps its original backend")
	suite.open_tab("天空")
	check(suite.sky_panel != null and suite.sky_panel.draft != null, "sky page initializes a valid draft on demand")
	suite.open_tab("事件与任务")
	check(suite.event_panel != null and suite.event_panel.catalog != null, "event table still loads its workbook")
	suite._hide_window(); suite.show_window()
	check(suite.level_panel == level and suite.asset_panels["敌人"] == catalog, "closing and reopening preserves initialized pages")
	if "--capture" in OS.get_cmdline_user_args():
		var output := "res://docs/godot_level_editor_suite/startup_2026-11-16"
		DirAccess.make_dir_recursive_absolute(output)
		for title in ["工作台", "关卡", "机关", "敌人", "天空"]:
			suite.open_tab(title); await frames(tree, 20)
			RenderingServer.force_draw(false)
			suite.window.get_texture().get_image().save_png(output.path_join(title + ".png"))
	print("STARTUP LAZY TEST: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
