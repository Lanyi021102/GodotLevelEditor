@tool
extends RefCounted
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func run(suite: EditorPlugin) -> void:
	var tree := suite.get_tree()
	suite.open_tab("敌人")
	var panel: Control = suite.modules.enemies.panel
	panel._load("res://addons/godot_level_editor/resources/enemies/samples_v1/human_medium_male.tres")
	for i in 15: await tree.process_frame
	var signature: String = panel._signature()
	var value: float = panel.definition.parameters.expose_penalty
	panel._render_parameters()
	var labels: Array[String] = []
	for label in panel.params.find_children("*", "Label", true, false): labels.append(label.text)
	check(not labels.any(func(text: String): return text.contains("能量") or text.contains("expose_penalty")), "NPC perception page hides the removed energy setting")
	for text in ["警觉累积 /s", "警觉衰减 /s", "噪音初始警觉", "求援半径 m", "巡逻点停留 s"]:
		check(labels.has(text), "current perception parameter remains editable: " + text)
	check(panel.definition.parameters.expose_penalty == value and panel._signature() == signature and not panel.dirty, "redrawing parameters preserves legacy data and draft state")
	var actor := preload("res://addons/godot_level_editor/scripts/stealth/guard_ai.gd").new()
	actor.name = "LegacyActorProbe"
	var property := {}
	for row in actor.get_property_list():
		if row.name == &"expose_penalty": property = row
	check(not property.is_empty() and (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0 and (int(property.usage) & PROPERTY_USAGE_EDITOR) == 0, "legacy actor property is serialized without appearing in the inspector")
	actor.expose_penalty = 47.5
	var packed := PackedScene.new()
	var error := packed.pack(actor)
	var restored := packed.instantiate() if error == OK else null
	check(restored != null and is_equal_approx(restored.expose_penalty, 47.5), "legacy actor value survives a packed-scene round trip")
	if restored != null: restored.free()
	check(actor.has_method("tl_capture") and actor.has_method("tl_restore"), "state-save and reset interfaces remain available")
	actor.free()
	var placement := preload("res://addons/godot_level_editor/modules/godot_level_editor/runtime/placement.gd").new()
	check(placement.placeholder_contract.contains("godot_level_editor_player") and not placement.placeholder_contract.contains("is_clone"), "new placeholder instructions require the current player group only")
	placement.free()
	if "--capture" in OS.get_cmdline_user_args():
		suite.display_adapter.set_user_scale(1.0); suite.window.size = Vector2i(1504, 1000)
		suite.asset_panels["敌人"].set_mode(1)
		panel.workspaces.current_tab = 1
		for i in panel.tabs.get_tab_count():
			if panel.tabs.get_tab_title(i) == "感知": panel.tabs.current_tab = i
		for i in 20: await tree.process_frame
		RenderingServer.force_draw(false)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--hygiene-capture="):
				suite.window.get_texture().get_image().save_png(arg.trim_prefix("--hygiene-capture="))
	print("PROJECT HYGIENE EDITOR: %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures else 0)
