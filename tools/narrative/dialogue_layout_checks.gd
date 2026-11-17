@tool
extends RefCounted
## Isolated in-memory layout checks. Called by the suite's dedicated UI QA run.
const LIBRARY := preload("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd")

static func run(panel: Control, check: Callable) -> void:
	var original: Resource = panel.library
	var original_signature: String = original.export_signature()
	var original_selection := Vector3i(panel.gi, panel.ci, panel.li)
	var original_dirty: bool = panel.dirty
	var original_export_dirty: bool = panel.export_dirty
	var source := LIBRARY.new()
	source.xlsx_path = ""
	source.speakers = {"山居接待员": Color("597b9f")}
	var full_text := "第一段完整对白，包含需要在较窄窗口中自动换行的长句。\n第二段保留作者输入的换行。"
	source.groups = [{"id": "layout_group", "name": "排版检查", "comments": [{"id": "layout_comment", "name": "长段落", "lines": [
		{"id": "reception_001", "speaker": "山居接待员", "text": full_text, "type": "对白", "duration": 0.0},
		{"id": "reception_002", "speaker": "山居接待员", "text": "用于搜索的独特对白。", "type": "提示", "duration": 1.5}
	]}]}]
	panel.dirty = false
	panel.open_library(source)
	for i in 4: await panel.get_tree().process_frame
	panel._fit_table_columns()
	var font: Font = panel.table.get_theme_font("font")
	var font_size: int = panel.table.get_theme_font_size("font_size")
	var required: float = font.get_string_size("reception_001", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + panel.table.get_theme_constant("h_separation") * 2 + panel.table.get_theme_constant("item_margin") + 16
	check.call(panel.table.get_column_width(0) >= required - 1, "dialogue ID column includes actual font width and Tree padding")
	check.call(panel.preview_content.text == full_text and panel.preview_content.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "selected dialogue preview preserves full text and authored line breaks")
	check.call(panel.group_count.text == "1" and panel.comment_count.text == "1" and panel.selection_count.text.contains("2"), "dialogue section counts match the opened in-memory library")
	var snapshot: String = panel.library.export_signature()
	panel._queue_table_layout()
	panel._refresh_preview()
	check.call(panel.library.export_signature() == snapshot and not panel.dirty, "layout and preview never mutate dialogue content or dirty state")
	panel.search.text = "独特"
	panel._refresh_table()
	check.call(panel.table.get_root().get_child_count() == 1 and panel.table.get_root().get_first_child().get_text(0) == "reception_002", "dialogue search keeps stable IDs and original row metadata")
	panel.search.text = "没有匹配的对白内容"
	panel._refresh_table()
	check.call(panel.table.get_root().get_child_count() == 0 and panel.preview_edit.disabled, "no-match search cannot edit an invisible stale selection")
	panel.search.clear()
	panel._refresh_table()
	panel.li = 0
	panel._refresh_table()
	panel.edit_line()
	panel.detail_content.text = full_text + "\n追加对白。"
	panel._apply_details()
	panel.detail_dialog.hide()
	check.call(panel.preview_content.text.ends_with("追加对白。") and panel.library.groups[0].comments[0].lines[0].id == "reception_001", "detail editing updates the reading preview without changing stable ID")
	panel.undo.undo()
	check.call(panel.preview_content.text == full_text, "undo restores the complete multiline reading preview")
	panel.undo.redo()
	check.call(panel.preview_content.text.ends_with("追加对白。"), "redo updates the selected-line preview")
	panel.dirty = false
	panel.open_library(original)
	panel.gi = original_selection.x; panel.ci = original_selection.y; panel.li = original_selection.z
	panel.dirty = original_dirty; panel.export_dirty = original_export_dirty
	panel._refresh()
	check.call(original.export_signature() == original_signature, "dialogue layout checks leave the original authoring resource untouched")
