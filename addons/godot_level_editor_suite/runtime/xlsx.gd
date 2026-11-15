@tool
extends RefCounted
## Small OOXML table adapter used by both editor and exported game. No external runtime.
static func _tag(parser: XMLParser) -> String:
	return parser.get_node_name().get_slice(":", parser.get_node_name().get_slice_count(":") - 1)
static func _xml(bytes: PackedByteArray) -> XMLParser:
	var parser := XMLParser.new()
	parser.open_buffer(bytes)
	return parser
static func read_book(path: String) -> Dictionary:
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
	for name in paths:
		if not zip.file_exists(paths[name]): errors.append("工作表缺失：" + name); continue
		parser = _xml(zip.read_file(paths[name]))
		var rows: Array = []
		var current: Array = []
		var cell_type := ""
		var value := ""
		var column := 0
		var reading := false
		while parser.read() == OK:
			var node_type := parser.get_node_type()
			if node_type == XMLParser.NODE_ELEMENT:
				match _tag(parser):
					"row": current = []
					"c":
						cell_type = parser.get_named_attribute_value_safe("t")
						value = ""
						column = _column_index(parser.get_named_attribute_value_safe("r"))
						if parser.is_empty():
							while current.size() <= column: current.append("")
					"v", "t": reading = true
					"f": errors.append("配表不支持公式单元格，请保存为直接数值／文本：" + name)
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
						if not current.is_empty(): rows.append(current)
			sheets[name] = rows
	zip.close()
	if sheets.is_empty(): errors.append("XLSX 没有工作表")
	return {"sheets": sheets if errors.is_empty() else {}, "errors": errors}
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
				meaningful = meaningful or not value.is_empty()
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
	var temporary := path + ".tmp"
	var zip := ZIPPacker.new()
	var error := zip.open(temporary)
	if error != OK: return PackedStringArray(["无法写入 XLSX：" + error_string(error)])
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
	for filename in files:
		zip.start_file(filename)
		zip.write_file(str(files[filename]).to_utf8_buffer())
		zip.close_file()
	zip.close()
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	return PackedStringArray() if error == OK else PackedStringArray(["替换 XLSX 失败：" + error_string(error)])
