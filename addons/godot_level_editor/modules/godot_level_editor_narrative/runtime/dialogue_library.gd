@tool
extends Resource
## Shared dialogue model: group -> comments -> lines. Current authoring/runtime use XLSX.
## CSV readers and fields remain for migration of historical dialogue resources.
const VERSION := 2
const TYPES := ["引导", "对白", "提示"]
const MODE_FREE := "free"
const MODE_STATIONARY := "stationary"
const DIALOGUE_MODES := {MODE_FREE: "自由对话", MODE_STATIONARY: "站桩对话"}
const CSV_COLUMNS := ["version", "group_id", "group_name", "group_order", "comment_id", "comment_name", "comment_order", "line_id", "line_order", "speaker", "color", "text", "type", "duration"]
@export var schema_version := VERSION
@export var speakers: Dictionary = {}
@export var groups: Array[Dictionary] = []
@export var next_line_id := 1
@export_file("*.csv") var csv_path := ""

func match_speaker(speaker: String) -> Color:
	if not speakers.has(speaker): speakers[speaker] = Color.from_hsv(float(absi(speaker.hash()) % 360) / 360.0, 0.42, 0.95)
	return speakers[speaker]

func allocate_line_id() -> String:
	var used := all_ids()
	while used.has("%05d" % next_line_id): next_line_id += 1
	var id := "%05d" % next_line_id
	next_line_id += 1
	return id

static func fresh_id(prefix: String) -> String:
	return prefix + "_" + Crypto.new().generate_random_bytes(8).hex_encode()

func migrate_legacy() -> bool:
	var legacy_shape := false
	for group in groups:
		if group.has("lines") and not group.has("comments"): legacy_shape = true
	if schema_version != 1 and not (schema_version == VERSION and legacy_shape): return false
	for group in groups:
		var old_id := str(group.id)
		var lines: Array = group.get("lines", []).duplicate(true)
		for line in lines: line["duration"] = float(line.get("duration", 0.0))
		group["id"] = fresh_id("group")
		group["comments"] = [{"id": old_id, "name": "进入对话", "lines": lines}]
		group.erase("lines")
	schema_version = VERSION
	return true

func comment_by_id(id: String) -> Dictionary:
	for group in groups:
		for comment in group.get("comments", []):
			if comment.get("id") == id: return comment
	return {}

func all_ids() -> Dictionary:
	var ids := {}
	for group in groups:
		ids[str(group.get("id", ""))] = true
		for comment in group.get("comments", []):
			ids[str(comment.get("id", ""))] = true
			for line in comment.get("lines", []): ids[str(line.get("id", ""))] = true
	return ids

func playback_duration(line: Dictionary) -> float:
	var seconds := float(line.get("duration", 0.0))
	return seconds if seconds > 0.0 else estimate_reading_seconds(str(line.get("text", "")))

static func estimate_reading_seconds(text: String) -> float:
	var glyphs := 0
	var words := 0
	var in_word := false
	var pauses := 0.0
	for i in text.length():
		var code := text.unicode_at(i)
		var ch := text.substr(i, 1)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			if not in_word: words += 1
			in_word = true
			continue
		if in_word and ch in ["'", "’", "-"]: continue
		in_word = false
		if ch in ["。", "！", "？", ".", "!", "?", "…", "\n"]: pauses += 0.35
		elif ch in ["，", "、", "；", "：", ",", ";", ":"]: pauses += 0.18
		elif not ch.strip_edges().is_empty() and ch not in ["\"", "'", "“", "”", "‘", "’", "（", "）", "(", ")"]: glyphs += 1
	# Reading heuristic: 5 non-Latin glyphs/s, 3 Latin words/s, plus punctuation pauses.
	return clampf(0.8 + glyphs / 5.0 + words / 3.0 + pauses, 2.5, 3600.0)

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != VERSION:
		errors.append("不支持的台本版本；旧版需先在编辑器中迁移")
		return errors
	var ids := {}
	for group in groups:
		_check_id(str(group.get("id", "")), ids, errors)
		if not group.get("comments") is Array:
			errors.append("对话组缺少 comments")
			continue
		for comment in group.comments:
			if not comment is Dictionary:
				errors.append("comment 格式无效")
				continue
			_check_id(str(comment.get("id", "")), ids, errors)
			if not comment.get("lines") is Array:
				errors.append("comment 缺少对白列表")
				continue
			for line in comment.lines:
				if not line is Dictionary:
					errors.append("对白格式无效")
					continue
				_check_id(str(line.get("id", "")), ids, errors)
				if str(line.get("text", "")).strip_edges().is_empty(): errors.append("对白内容为空：" + str(line.get("id")))
				if not TYPES.has(line.get("type")): errors.append("台本类型无效")
				if not DIALOGUE_MODES.has(line.get("dialogue_mode", MODE_FREE)): errors.append("对话类型无效：" + str(line.get("id", "")))
				if not speakers.get(str(line.get("speaker", ""))) is Color: errors.append("说话人缺少颜色")
				var duration: Variant = line.get("duration", 0.0)
				if not (duration is float or duration is int) or not is_finite(float(duration)) or float(duration) < 0.0 or float(duration) > 3600.0: errors.append("显示秒数应在 0～3600；0 为自动")
	return errors

func _check_id(id: String, ids: Dictionary, errors: PackedStringArray) -> void:
	if (not id.is_valid_identifier() and not id.is_valid_int()) or ids.has(id): errors.append("ID 无效或重复：" + id)
	ids[id] = true

func write_csv(path: String) -> PackedStringArray:
	var errors := validate()
	if not errors.is_empty(): return errors
	var temporary := path + ".tmp_" + Crypto.new().generate_random_bytes(4).hex_encode()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return PackedStringArray(["无法写入 CSV：" + error_string(FileAccess.get_open_error())])
	file.store_csv_line(PackedStringArray(CSV_COLUMNS))
	for g in groups.size():
		var group: Dictionary = groups[g]
		if group.comments.is_empty(): file.store_csv_line(_csv_row(group, g, {}, -1, {}, -1))
		for c in group.comments.size():
			var comment: Dictionary = group.comments[c]
			if comment.lines.is_empty(): file.store_csv_line(_csv_row(group, g, comment, c, {}, -1))
			for l in comment.lines.size(): file.store_csv_line(_csv_row(group, g, comment, c, comment.lines[l], l))
	file.flush()
	var err := file.get_error()
	file.close()
	if err == OK: err = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		errors.append("CSV 写入失败：" + error_string(err))
	elif path.begins_with("res://"):
		# CSV is raw game data, not a Godot translation spreadsheet.
		var import_path := path + ".import"
		if not FileAccess.file_exists(import_path):
			var settings := FileAccess.open(import_path, FileAccess.WRITE)
			if settings != null: settings.store_string('[remap]\n\nimporter="keep"\n')
	return errors

func export_signature() -> String:
	var rows: Array = []
	for g in groups.size():
		var group: Dictionary = groups[g]
		if group.comments.is_empty(): rows.append(_csv_row(group, g, {}, -1, {}, -1))
		for c in group.comments.size():
			var comment: Dictionary = group.comments[c]
			if comment.lines.is_empty(): rows.append(_csv_row(group, g, comment, c, {}, -1))
			for l in comment.lines.size():
				var row := Array(_csv_row(group, g, comment, c, comment.lines[l], l))
				row.append(str(comment.lines[l].get("dialogue_mode", MODE_FREE)))
				rows.append(row)
	return JSON.stringify(rows).sha256_text()

func _csv_row(group: Dictionary, g: int, comment: Dictionary, c: int, line: Dictionary, l: int) -> PackedStringArray:
	return PackedStringArray([str(VERSION), str(group.id), str(group.get("name", "")), str(g), str(comment.get("id", "")), str(comment.get("name", "")), str(c) if c >= 0 else "", str(line.get("id", "")), str(l) if l >= 0 else "", str(line.get("speaker", "")), "#" + speakers.get(line.get("speaker", ""), Color.WHITE).to_html() if not line.is_empty() else "", str(line.get("text", "")), str(line.get("type", "")), str(line.get("duration", 0.0)) if not line.is_empty() else ""])

static func read_csv(path: String) -> Dictionary:
	var errors := PackedStringArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"library": null, "errors": PackedStringArray(["无法读取对白 CSV：" + path])}
	var header := file.get_csv_line()
	if not header.is_empty(): header[0] = header[0].trim_prefix("\ufeff")
	if header != PackedStringArray(CSV_COLUMNS): return {"library": null, "errors": PackedStringArray(["CSV 列名／顺序不匹配，请从台本编辑器重新导出"])}
	var library: Resource = load("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd").new()
	library.csv_path = path
	var group_map := {}
	var comment_map := {}
	var row_number := 1
	while not file.eof_reached():
		var row := file.get_csv_line()
		row_number += 1
		if row.size() == 1 and row[0].is_empty(): continue
		if row.size() != CSV_COLUMNS.size():
			errors.append("CSV 第 %d 行列数不符" % row_number)
			continue
		var record := {}
		for i in CSV_COLUMNS.size(): record[CSV_COLUMNS[i]] = row[i]
		if record.version != str(VERSION) or not str(record.group_order).is_valid_int() or int(record.group_order) < 0:
			errors.append("CSV 版本／组顺序无效")
			continue
		var gid := str(record.group_id)
		if not group_map.has(gid):
			var group := {"id": gid, "name": record.group_name, "comments": [], "_order": int(record.group_order)}
			group_map[gid] = group
			library.groups.append(group)
		var group: Dictionary = group_map[gid]
		if group.name != record.group_name or group._order != int(record.group_order): errors.append("同一对话组的名称／顺序不一致")
		if str(record.comment_id).is_empty():
			if not str(record.line_id).is_empty(): errors.append("对白缺少 comment")
			continue
		if not str(record.comment_order).is_valid_int() or int(record.comment_order) < 0:
			errors.append("comment 顺序无效")
			continue
		var cid := str(record.comment_id)
		if not comment_map.has(cid):
			var comment := {"id": cid, "name": record.comment_name, "lines": [], "_order": int(record.comment_order), "_group": gid}
			comment_map[cid] = comment
			group.comments.append(comment)
		var comment: Dictionary = comment_map[cid]
		if comment._group != gid or comment.name != record.comment_name or comment._order != int(record.comment_order): errors.append("同一 comment 的归属／名称／顺序不一致")
		if str(record.line_id).is_empty(): continue
		if not str(record.line_order).is_valid_int() or int(record.line_order) < 0 or not str(record.duration).is_valid_float() or not Color.html_is_valid(str(record.color)):
			errors.append("对白顺序／显示时长／颜色无效")
			continue
		var speaker := str(record.speaker)
		var color := Color(str(record.color))
		if library.speakers.has(speaker) and library.speakers[speaker] != color: errors.append("同名说话人颜色不一致")
		library.speakers[speaker] = color
		comment.lines.append({"id": str(record.line_id), "speaker": speaker, "text": str(record.text), "type": str(record.type), "duration": float(record.duration), "_order": int(record.line_order)})
		if str(record.line_id).is_valid_int(): library.next_line_id = maxi(library.next_line_id, int(record.line_id) + 1)
	library.groups.sort_custom(func(a: Dictionary, b: Dictionary): return a._order < b._order)
	for group in library.groups:
		group.erase("_order")
		group.comments.sort_custom(func(a: Dictionary, b: Dictionary): return a._order < b._order)
		for comment in group.comments:
			comment.erase("_order")
			comment.erase("_group")
			comment.lines.sort_custom(func(a: Dictionary, b: Dictionary): return a._order < b._order)
			for line in comment.lines: line.erase("_order")
	errors.append_array(library.validate())
	return {"library": library if errors.is_empty() else null, "errors": errors}

const XLSX := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/xlsx.gd")
@export_file("*.xlsx") var xlsx_path := "res://content/tables/dialogues.xlsx"
var workbook_origin: Dictionary = {}
const SHEET_FIELDS := {"对话组": ["group_id", "name", "order"], "Comments": ["comment_id", "group_id", "name", "order"], "对白": ["line_id", "comment_id", "order", "speaker", "dialogue_mode", "text", "type", "duration"], "角色": ["speaker", "color"], "配置": ["key", "value"]}
func workbook_sheets() -> Dictionary:
	var sheets := {}
	for name in SHEET_FIELDS: sheets[name] = [SHEET_FIELDS[name].duplicate()]
	sheets["配置"].append_array([["version", str(VERSION)], ["next_line_id", str(next_line_id)]])
	for g in groups.size():
		var group: Dictionary = groups[g]
		sheets["对话组"].append([group.id, group.name, str(g)])
		for c in group.comments.size():
			var comment: Dictionary = group.comments[c]
			sheets.Comments.append([comment.id, group.id, comment.name, str(c)])
			for l in comment.lines.size():
				var line: Dictionary = comment.lines[l]
				sheets["对白"].append([line.id, comment.id, str(l), line.speaker, line.get("dialogue_mode", MODE_FREE), line.text, line.type, str(line.get("duration", 0.0))])
	for speaker in speakers: sheets["角色"].append([speaker, "#" + speakers[speaker].to_html()])
	return sheets
func write_xlsx(path: String) -> PackedStringArray:
	var errors := validate()
	return XLSX.save_tables(path, workbook_sheets(), workbook_origin) if errors.is_empty() else errors
static func read_xlsx(path: String, editable := true) -> Dictionary:
	var book := XLSX.read_book(path, SHEET_FIELDS, editable)
	if not book.errors.is_empty(): return {"library": null, "errors": book.errors}
	var parsed := {}
	var errors := PackedStringArray()
	var required := {"对话组": ["group_id", "name", "order"], "Comments": ["comment_id", "group_id", "name", "order"], "对白": ["line_id", "comment_id", "order", "speaker", "text", "type", "duration"], "角色": ["speaker", "color"], "配置": ["key", "value"]}
	for name in required:
		var result := XLSX.records(book.sheets, name, required[name])
		errors.append_array(result.errors)
		parsed[name] = result.rows
	if not errors.is_empty(): return {"library": null, "errors": errors}
	var library: Resource = load("res://addons/godot_level_editor/modules/godot_level_editor_narrative/runtime/dialogue_library.gd").new()
	library.xlsx_path = path
	library.workbook_origin = book.origin
	var metadata := {}
	for row in parsed["配置"]: metadata[row.key] = row.value
	if str(metadata.get("version", "")) != str(VERSION): errors.append("台本 XLSX 版本无效")
	library.next_line_id = maxi(1, int(metadata.get("next_line_id", "1")))
	var group_map := {}
	var comment_map := {}
	for row in parsed["角色"]:
		if not Color.html_is_valid(row.color) or library.speakers.has(row.speaker): errors.append("角色颜色无效或姓名重复")
		else: library.speakers[row.speaker] = Color(row.color)
	for name in ["对话组", "Comments", "对白"]:
		var orders := {}
		for row in parsed[name]:
			var scope := str(row.get("group_id", "")) if name == "Comments" else str(row.get("comment_id", "")) if name == "对白" else "$groups"
			var key := scope + ":" + str(row.order)
			if not str(row.order).is_valid_int() or int(row.order) < 0 or orders.has(key): errors.append(name + " 顺序无效或重复")
			orders[key] = true
		parsed[name].sort_custom(func(a: Dictionary, b: Dictionary): return int(a.order) < int(b.order))
	for row in parsed["对话组"]:
		var group := {"id": row.group_id, "name": row.name, "comments": []}
		if group_map.has(row.group_id): errors.append("对话组 ID 重复")
		group_map[row.group_id] = group
		library.groups.append(group)
	for row in parsed.Comments:
		if not group_map.has(row.group_id): errors.append("comment 对话组不存在"); continue
		var comment := {"id": row.comment_id, "name": row.name, "lines": []}
		if comment_map.has(row.comment_id): errors.append("comment ID 重复")
		comment_map[row.comment_id] = comment
		group_map[row.group_id].comments.append(comment)
	for row in parsed["对白"]:
		if not comment_map.has(row.comment_id): errors.append("对白 comment 不存在"); continue
		if not str(row.duration).is_valid_float(): errors.append("对白时长无效"); continue
		comment_map[row.comment_id].lines.append({"id": row.line_id, "speaker": row.speaker, "dialogue_mode": row.get("dialogue_mode", MODE_FREE), "text": row.text, "type": row.type, "duration": float(row.duration)})
	errors.append_array(library.validate())
	return {"library": library if errors.is_empty() else null, "errors": errors}
