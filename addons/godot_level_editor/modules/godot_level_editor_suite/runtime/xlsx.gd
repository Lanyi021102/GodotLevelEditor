@tool
extends RefCounted
## Small OOXML table adapter used by both editor and exported game. No external runtime.
static func _tag(parser: XMLParser) -> String:
	return parser.get_node_name().get_slice(":", parser.get_node_name().get_slice_count(":") - 1)
static func _xml(bytes: PackedByteArray) -> XMLParser:
	var parser := XMLParser.new()
	parser.open_buffer(bytes)
	return parser
static func read_book(path: String, schema: Dictionary = {}, editable := true) -> Dictionary:
	var digest := FileAccess.get_sha256(path) if editable and not schema.is_empty() and FileAccess.file_exists(path) else ""
	var zip := ZIPReader.new()
	if zip.open(path) != OK: return {"sheets": {}, "errors": PackedStringArray(["无法读取 XLSX：" + path])}
	var errors := PackedStringArray()
	var relations := {}
	var parser := _xml(zip.read_file("xl/_rels/workbook.xml.rels"))
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and _tag(parser) == "Relationship":
			var target := parser.get_named_attribute_value_safe("Target")
			relations[parser.get_named_attribute_value_safe("Id")] = target.trim_prefix("/") if target.begins_with("/") else ("xl/" + target).simplify_path()
	var shared: Array[String] = []
	if zip.file_exists("xl/sharedStrings.xml"):
		parser = _xml(zip.read_file("xl/sharedStrings.xml"))
		var text := ""
		var in_text := false
		while parser.read() == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT:
				if _tag(parser) == "si": text = ""
				if _tag(parser) == "t": in_text = true
			elif parser.get_node_type() == XMLParser.NODE_TEXT and in_text: text += parser.get_node_data()
			elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				if _tag(parser) == "t": in_text = false
				if _tag(parser) == "si": shared.append(text)
	var paths := {}
	parser = _xml(zip.read_file("xl/workbook.xml"))
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and _tag(parser) == "sheet":
			paths[parser.get_named_attribute_value_safe("name")] = relations.get(parser.get_named_attribute_value_safe("r:id"), "")
	var sheets := {}
	var numbers := {}
	for name in paths:
		if not schema.is_empty() and not schema.has(name): continue
		numbers[name] = []
		if not zip.file_exists(paths[name]): errors.append("工作表缺失：" + name); continue
		parser = _xml(zip.read_file(paths[name]))
		var rows: Array = []
		var current: Array = []
		var physical_row := 0
		var cell_type := ""
		var value := ""
		var column := 0
		var reading := false
		while parser.read() == OK:
			var node_type := parser.get_node_type()
			if node_type == XMLParser.NODE_ELEMENT:
				match _tag(parser):
					"row":
						current = []
						var ref := parser.get_named_attribute_value_safe("r")
						physical_row = physical_row + 1 if ref.is_empty() else int(ref)
					"c":
						cell_type = parser.get_named_attribute_value_safe("t")
						value = ""
						column = _column_index(parser.get_named_attribute_value_safe("r"))
						if parser.is_empty():
							while current.size() <= column: current.append("")
					"v", "t": reading = true
					"f":
						if schema.is_empty() or rows.is_empty() or (column < rows[0].size() and rows[0][column] in schema[name]):
							errors.append("配表字段不支持公式，请保存为直接数值／文本：" + name)
			elif node_type == XMLParser.NODE_TEXT and reading: value += parser.get_node_data()
			elif node_type == XMLParser.NODE_ELEMENT_END:
				match _tag(parser):
					"v", "t": reading = false
					"c":
						while current.size() <= column: current.append("")
						if cell_type == "s":
							if not value.is_valid_int() or int(value) < 0 or int(value) >= shared.size(): errors.append("共享文本索引无效")
							else: value = shared[int(value)]
						current[column] = value
					"row":
						if not current.is_empty():
							rows.append(current)
							numbers[name].append(physical_row)
			sheets[name] = rows
	var origin := {}
	if editable and not schema.is_empty() and errors.is_empty():
		var parts := {}
		for item in zip.get_files():
			if not item.ends_with("/"): parts[item] = zip.read_file(item)
		origin = {"path": path, "digest": digest, "parts": parts, "paths": paths, "rows": numbers, "sheets": sheets.duplicate(true)}
		if FileAccess.get_sha256(path) != digest: errors.append("配表读取期间已被修改，请重新打开。")
	zip.close()
	if sheets.is_empty(): errors.append("XLSX 没有工作表")
	return {"sheets": sheets if errors.is_empty() else {}, "errors": errors, "origin": origin}
static func _column_index(reference: String) -> int:
	var value := 0
	for char_code in reference.length():
		var ch := reference.to_upper().unicode_at(char_code)
		if ch < 65 or ch > 90: break
		value = value * 26 + ch - 64
	return maxi(value - 1, 0)
static func records(sheets: Dictionary, name: String, required: Array) -> Dictionary:
	var errors := PackedStringArray()
	var rows: Array = sheets.get(name, [])
	if rows.is_empty(): return {"rows": [], "errors": PackedStringArray(["工作表不存在或缺少表头：" + name])}
	var headers: Array = rows[0]
	for key in required:
		if not headers.has(key): errors.append(name + " 缺少列：" + str(key))
	var output: Array[Dictionary] = []
	if errors.is_empty():
		for i in range(1, rows.size()):
			var record := {}
			var meaningful := false
			for c in headers.size():
				var value := str(rows[i][c]) if c < rows[i].size() else ""
				record[str(headers[c])] = value
				meaningful = meaningful or (str(headers[c]) in required and not value.is_empty())
			if meaningful: output.append(record)
	return {"rows": output, "errors": errors}
static func _escape(value: Variant) -> String:
	return str(value).xml_escape()
static func _letters(index: int) -> String:
	var result := ""
	index += 1
	while index > 0:
		index -= 1
		result = String.chr(65 + index % 26) + result
		index /= 26
	return result
static func write_book(path: String, sheets: Dictionary) -> PackedStringArray:
	var expected := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	return _write_archive(path, _new_archive(sheets), expected, {}, {})

static func _new_archive(sheets: Dictionary) -> Dictionary:
	var files := {}
	var types := '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
	var workbook := '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
	var relations := '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
	var index := 0
	for name in sheets:
		index += 1
		types += '<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % index
		workbook += '<sheet name="%s" sheetId="%d" r:id="rId%d"/>' % [_escape(name), index, index]
		relations += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>' % [index, index]
		var rows: Array = sheets[name]
		var columns: int = rows[0].size() if not rows.is_empty() else 1
		var sheet := '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" state="frozen"/></sheetView></sheetViews><cols>'
		for c in columns:
			var header := str(rows[0][c]) if not rows.is_empty() else ""
			var width := 60 if header in ["text", "notes", "graph_path"] else 30 if header.ends_with("name") else 22
			sheet += '<col min="%d" max="%d" width="%d" customWidth="1"/>' % [c + 1, c + 1, width]
		sheet += '</cols><sheetData>'
		for r in rows.size():
			sheet += '<row r="%d" ht="%d" customHeight="1">' % [r + 1, 30 if r == 0 else 34]
			for c in rows[r].size():
				sheet += '<c r="%s%d" t="inlineStr" s="%d"><is><t xml:space="preserve">%s</t></is></c>' % [_letters(c), r + 1, 1 if r == 0 else 0, _escape(rows[r][c])]
			sheet += '</row>'
		sheet += '</sheetData><autoFilter ref="A1:%s%d"/></worksheet>' % [_letters(columns - 1), maxi(rows.size(), 1)]
		files["xl/worksheets/sheet%d.xml" % index] = sheet
	files["[Content_Types].xml"] = types + '</Types>'
	files["_rels/.rels"] = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
	files["xl/workbook.xml"] = workbook + '</sheets></workbook>'
	files["xl/_rels/workbook.xml.rels"] = relations + '<Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
	files["xl/styles.xml"] = '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF243950"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="49" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center"/></xf></cellXfs></styleSheet>'
	for filename in files: files[filename] = str(files[filename]).to_utf8_buffer()
	return files

const CONFLICT := "配表已在外部修改，草稿已保留。请另存副本，或重新读取磁盘版本。"

## Update only cells owned by the plugin. Keep other OOXML parts, styles, formulae,
## sheet order and physical row numbers, so notes and references stay on the same records.
static func save_tables(path: String, tables: Dictionary, origin: Dictionary) -> PackedStringArray:
	var exists := FileAccess.file_exists(path)
	var destination_hash := FileAccess.get_sha256(path) if exists else ""
	if origin.get("path", "") == path and destination_hash != origin.digest:
		return PackedStringArray([CONFLICT])
	var schema := {}
	for name in tables: schema[name] = tables[name][0]
	var template := origin
	if template.is_empty() and exists:
		var existing := read_book(path, schema)
		if not existing.errors.is_empty(): return existing.errors
		template = existing.origin
	if template.is_empty():
		return _write_archive(path, _new_archive(tables), destination_hash, schema, origin)
	var parts: Dictionary = template.parts.duplicate()
	for name in tables:
		var part := str(template.paths.get(name, ""))
		if not parts.has(part): return PackedStringArray(["工作表缺失：" + name])
		var xml: String = parts[part].get_string_from_utf8()
		var patched := _patch_sheet(xml, name, tables[name], template)
		if patched.is_empty(): return PackedStringArray(["无法保留工作表结构，原文件未修改：" + name])
		parts[part] = patched.to_utf8_buffer()
	return _write_archive(path, parts, destination_hash, schema, origin)

static func _write_archive(path: String, parts: Dictionary, expected_hash: String, schema: Dictionary, origin: Dictionary) -> PackedStringArray:
	var temporary := path + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var zip := ZIPPacker.new()
	var result := zip.open(temporary)
	if result != OK: return PackedStringArray(["无法写入配表：" + error_string(result)])
	for part in parts:
		result = zip.start_file(part)
		if result != OK: break
		result = zip.write_file(parts[part])
		if result != OK: break
		result = zip.close_file()
		if result != OK: break
	var closed := zip.close()
	if result == OK: result = closed
	var errors := PackedStringArray()
	var saved := {}
	if result == OK and not schema.is_empty():
		var check := read_book(temporary, schema)
		errors = check.errors
		if errors.is_empty(): saved = check.origin
	if result == OK and errors.is_empty():
		var latest := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		if latest != expected_hash: errors.append(CONFLICT)
		else: result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if result != OK: errors.append("配表未保存：" + error_string(result))
	if not errors.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	elif not saved.is_empty():
		saved.path = path
		origin.assign(saved)
	return errors

static func _patch_sheet(xml: String, name: String, table: Array, origin: Dictionary) -> String:
	var sheet_data := RegEx.create_from_string("(?s)<sheetData\\b[^>]*>(.*?)</sheetData>").search(xml)
	if sheet_data == null: return ""
	var old: Array = origin.sheets[name]
	var row_numbers: Array = origin.rows[name]
	if old.is_empty(): return ""
	var headers: Array = old[0].duplicate()
	var fields: Array = table[0]
	for field in fields:
		if headers.count(field) > 1: return ""
		if not headers.has(field): headers.append(field)
	var key_column := headers.find(fields[0])
	var new_rows := {}
	for i in range(1, table.size()): new_rows[str(table[i][0])] = table[i]
	var replacements := {}
	var old_rows := {}
	var last_number := 0
	for i in old.size():
		var number := int(row_numbers[i])
		last_number = maxi(last_number, number)
		old_rows[number] = old[i]
		if i == 0:
			replacements[number] = fields
			continue
		var id := str(old[i][key_column]) if key_column < old[i].size() else ""
		if new_rows.has(id):
			replacements[number] = new_rows[id]
			new_rows.erase(id)
		elif not id.is_empty() and name != "配置": replacements[number] = []
	var row_pattern := RegEx.create_from_string("(?s)<row\\b[^>]*?(?:/>|>.*?</row>)")
	var cell_pattern := RegEx.create_from_string("(?s)<c\\b[^>]*?(?:/>|>.*?</c>)")
	var ref_pattern := RegEx.create_from_string("\\br=[\"']([A-Za-z]*[0-9]+)[\"']")
	var original_data := sheet_data.get_string(1)
	var rewritten := ""
	var cursor := 0
	for row in row_pattern.search_all(original_data):
		var raw := row.get_string()
		var head := raw.left(raw.find(">") + 1)
		var row_ref := ref_pattern.search(head)
		if row_ref == null: return ""
		var number := int(row_ref.get_string(1))
		last_number = maxi(last_number, number)
		rewritten += original_data.substr(cursor, row.get_start() - cursor)
		cursor = row.get_end()
		if not replacements.has(number):
			rewritten += raw
			continue
		var values: Array = replacements[number]
		replacements.erase(number)
		if values.is_empty(): continue
		var cells := ""
		var next_column := 0
		var last := head.length()
		for cell in cell_pattern.search_all(raw):
			var ref := ref_pattern.search(cell.get_string().get_slice(">", 0))
			if ref == null: return ""
			var col := _column_index(ref.get_string(1))
			var field := fields.find(headers[col]) if col < headers.size() else -1
			cells += raw.substr(last, cell.get_start() - last)
			last = cell.get_end()
			for missing in range(next_column, col):
				var missing_field := fields.find(headers[missing]) if missing < headers.size() else -1
				if missing_field >= 0: cells += _owned_cell(missing, number, values[missing_field], "")
			next_column = col + 1
			if field < 0 or (col < old_rows[number].size() and str(old_rows[number][col]) == str(values[field])): cells += cell.get_string()
			else:
				cells += _owned_cell(col, number, values[field], cell.get_string())
		for col in range(next_column, headers.size()):
			var field := fields.find(headers[col])
			if field >= 0:
				cells += _owned_cell(col, number, values[field], "")
		rewritten += head.trim_suffix("/>").trim_suffix(">") + ">" + cells + raw.substr(last).trim_suffix("</row>") + "</row>"
	if not replacements.is_empty(): return ""
	rewritten += original_data.substr(cursor)
	for row in new_rows.values():
		last_number += 1
		rewritten += '<row r="%d">' % last_number
		for col in headers.size():
			var field := fields.find(headers[col])
			if field >= 0: rewritten += _owned_cell(col, last_number, row[field], "")
		rewritten += "</row>"
	var result := xml.left(sheet_data.get_start(1)) + rewritten + xml.substr(sheet_data.get_end(1))
	if new_rows.is_empty() and headers.size() == old[0].size(): return result
	# Worksheets with a declared range must include newly inserted cells.
	var range_pattern := RegEx.create_from_string("<(dimension|autoFilter)\\b[^>]*\\bref=\"([A-Z]+[0-9]+)(?::([A-Z]+)([0-9]+))?\"")
	var ranges := range_pattern.search_all(result)
	ranges.reverse()
	for item in ranges:
		var final_col := maxi(headers.size() - 1, _column_index(item.get_string(3)))
		var final_row := maxi(last_number, int(item.get_string(4)))
		var start := item.get_start(2)
		var end := item.get_end(4) if item.get_start(4) >= 0 else item.get_end(2)
		result = result.left(start) + item.get_string(2) + ":" + _letters(final_col) + str(final_row) + result.substr(end)
	return result

static func _owned_cell(col: int, number: int, value: Variant, previous: String) -> String:
	var head := previous.get_slice(">", 0)
	var style := RegEx.create_from_string("\\bs=[\"']([0-9]+)[\"']").search(head)
	var attributes := ' s="%s"' % style.get_string(1) if style != null else ""
	return '<c r="%s%d"%s t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % [_letters(col), number, attributes, _escape(value)]
