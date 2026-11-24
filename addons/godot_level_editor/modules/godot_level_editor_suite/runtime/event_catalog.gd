@tool
extends Resource
const XLSX := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/xlsx.gd")
const PATH := "res://content/tables/events.xlsx"
const LEVELS := preload("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/level_catalog.gd")
const EVENT_FIELDS := ["event_id", "name", "display_name", "notes", "order", "start_type", "start_key"]
const TASK_FIELDS := ["task_id", "event_id", "name", "display_name", "notes", "order", "graph_path", "level_id"]
const START_TYPES := ["manual", "room_enter", "event_received", "game_start"]
var events: Array[Dictionary] = []
var tasks: Array[Dictionary] = []
var next_event_id := 1001
var next_task_ids: Dictionary = {}
func snapshot() -> Dictionary:
	return {"events": events.duplicate(true), "tasks": tasks.duplicate(true)}
func apply_snapshot(data: Dictionary) -> void:
	events.assign(data.events.duplicate(true))
	tasks.assign(data.tasks.duplicate(true))
func event_by_id(id: String) -> Dictionary:
	for event in events:
		if event.event_id == id: return event
	return {}
func task_by_id(id: String) -> Dictionary:
	for task in tasks:
		if task.task_id == id: return task
	return {}
func event_tasks(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task in tasks:
		if task.event_id == id: result.append(task)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.order) < int(b.order))
	return result
func add_event() -> Dictionary:
	while not event_by_id(str(next_event_id)).is_empty(): next_event_id += 1
	var id := str(next_event_id)
	next_event_id += 1
	var event := {"event_id": id, "name": "event_" + id, "display_name": "新事件", "notes": "", "order": events.size(), "start_type": "manual", "start_key": ""}
	events.append(event)
	return event
func next_task_id(event_id: String) -> String:
	var sequence := int(next_task_ids.get(event_id, 1))
	while not task_by_id(event_id + "%03d" % sequence).is_empty(): sequence += 1
	return event_id + "%03d" % sequence
func add_task(event_id: String, level_id: String) -> Dictionary:
	var sequence := int(next_task_ids.get(event_id, 1))
	while not task_by_id(event_id + "%03d" % sequence).is_empty(): sequence += 1
	var id := event_id + "%03d" % sequence
	next_task_ids[event_id] = sequence + 1
	var task := {"task_id": id, "event_id": event_id, "name": "task_" + id, "display_name": "新任务", "notes": "", "order": event_tasks(event_id).size(), "graph_path": "res://content/resources/task_graphs/" + id + ".tres", "level_id": level_id}
	tasks.append(task)
	return task
func sheets() -> Dictionary:
	var output := {"事件": [EVENT_FIELDS], "任务": [TASK_FIELDS], "配置": [["key", "value"], ["version", "2"], ["next_event_id", str(next_event_id)]]}
	for event in events:
		var row := []
		for field in EVENT_FIELDS: row.append(str(event.get(field, "")))
		output["事件"].append(row)
	for task in tasks:
		var row := []
		for field in TASK_FIELDS: row.append(str(task.get(field, "")))
		output["任务"].append(row)
	for id in next_task_ids: output["配置"].append(["next_task:" + str(id), str(next_task_ids[id])])
	return output
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	var names := {}
	var orders := {}
	for event in events:
		var id := str(event.get("event_id", ""))
		if not id.is_valid_int() or int(id) < 1001 or ids.has(id): errors.append("事件 ID 无效或重复：" + id)
		ids[id] = true
		if str(event.get("name", "")).is_empty() or names.has(event.get("name")): errors.append("事件程序名为空或重复")
		names[event.get("name")] = true
		if str(event.get("display_name", "")).strip_edges().is_empty(): errors.append("事件显示名为空")
		if not START_TYPES.has(event.get("start_type")): errors.append("事件开始条件无效")
		if event.get("start_type") in ["room_enter", "event_received"] and str(event.get("start_key", "")).strip_edges().is_empty(): errors.append("请填写房间 ID／接收事件名")
		if not str(event.get("order", "")).is_valid_int() or int(event.order) < 0 or orders.has(str(event.order)): errors.append("事件执行排序无效或重复")
		orders[str(event.get("order"))] = true
	var task_names := {}
	var task_orders := {}
	var levels := LEVELS.load_book(LEVELS.PATH, true, false)
	if not tasks.is_empty(): errors.append_array(levels.errors)
	for task in tasks:
		var id := str(task.get("task_id", ""))
		var parent := str(task.get("event_id", ""))
		if not ids.has(parent) or not id.begins_with(parent) or not id.is_valid_int() or id.length() < parent.length() + 3 or ids.has(id): errors.append("任务 ID／所属事件无效：" + id)
		ids[id] = true
		var name_key := parent + ":" + str(task.get("name", ""))
		if str(task.get("name", "")).is_empty() or task_names.has(name_key): errors.append("事件内的任务程序名为空或重复")
		task_names[name_key] = true
		if str(task.get("display_name", "")).strip_edges().is_empty(): errors.append("任务显示名为空")
		var order_key := parent + ":" + str(task.get("order", ""))
		if not str(task.get("order", "")).is_valid_int() or int(task.order) < 0 or task_orders.has(order_key): errors.append("任务顺序无效或重复")
		task_orders[order_key] = true
		var graph := str(task.get("graph_path", ""))
		if not graph.begins_with("res://") or not graph.ends_with(".tres"): errors.append("任务图必须为项目内 .tres 资源")
		var level_id := str(task.get("level_id", ""))
		if level_id.is_empty() or (levels.catalog != null and levels.catalog.by_id(level_id).is_empty()): errors.append("任务必须绑定一个有效关卡：" + id)
	return errors
var workbook_origin: Dictionary = {}

func save_book(path := PATH) -> PackedStringArray:
	var errors := validate()
	return XLSX.save_tables(path, sheets(), workbook_origin) if errors.is_empty() else errors
static func load_book(path := PATH, editable := true) -> Dictionary:
	var book := XLSX.read_book(path, {"事件": EVENT_FIELDS, "任务": TASK_FIELDS, "配置": ["key", "value"]}, editable)
	if not book.errors.is_empty(): return {"catalog": null, "errors": book.errors}
	var script: Script = load("res://addons/godot_level_editor/modules/godot_level_editor_suite/runtime/event_catalog.gd")
	var catalog: Resource = script.new()
	var events_data := XLSX.records(book.sheets, "事件", EVENT_FIELDS)
	var tasks_data := XLSX.records(book.sheets, "任务", TASK_FIELDS)
	var metadata := XLSX.records(book.sheets, "配置", ["key", "value"])
	var errors: PackedStringArray = events_data.errors
	errors.append_array(tasks_data.errors)
	errors.append_array(metadata.errors)
	if not errors.is_empty(): return {"catalog": null, "errors": errors}
	catalog.events.assign(events_data.rows)
	catalog.tasks.assign(tasks_data.rows)
	var version := ""
	for row in metadata.rows:
		if row.key == "version": version = row.value
		elif row.key == "next_event_id": catalog.next_event_id = maxi(1001, int(row.value))
		elif str(row.key).begins_with("next_task:"): catalog.next_task_ids[str(row.key).trim_prefix("next_task:")] = maxi(1, int(row.value))
	if version != "2": errors.append("事件配表需要任务所属关卡，请升级为版本 2")
	for event in catalog.events: catalog.next_event_id = maxi(catalog.next_event_id, int(event.event_id) + 1)
	for task in catalog.tasks:
		var sequence := int(str(task.task_id).trim_prefix(str(task.event_id)))
		catalog.next_task_ids[task.event_id] = maxi(int(catalog.next_task_ids.get(task.event_id, 1)), sequence + 1)
	errors.append_array(catalog.validate())
	catalog.events.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.order) < int(b.order))
	catalog.workbook_origin = book.origin
	return {"catalog": catalog if errors.is_empty() else null, "errors": errors}
