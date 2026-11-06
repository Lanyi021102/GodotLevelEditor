extends MeshInstance3D
## 世界轨迹线（docs/GDD.md §4.3）：把时间线里记录的位置采样成一条贴地彩带。
##
## 关键点：
##   - 数据来源就是时间线本身（不做第二份记录），所以回退后线会自动变短
##   - 采样从缓冲最旧帧到**游标**为止，永远和 HUD 时间线一致
##   - 冻结时也要更新（拖拽要看到线变短），因此 process_mode = ALWAYS

const HEIGHT_OFFSET := 0.07

## 这条线属于哪个可回退实体
var entity: Object
var trail_color := Color(0.98, 0.98, 1.0, 0.55)
var width := 0.22
## 采样上限（超出自动加大步长）
var max_points := 400
## 重建间隔（秒），避免每帧重建网格
var rebuild_interval := 0.05

var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
var _last_rebuild_ms := -1000
var _last_signature := ""
var _samples := PackedVector3Array()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mesh = _mesh
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = trail_color
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func setup(new_entity: Object, color: Color) -> void:
	entity = new_entity
	trail_color = color
	_material.albedo_color = color


func _process(_delta: float) -> void:
	if entity == null or not is_instance_valid(entity):
		if _mesh.get_surface_count() > 0:
			_samples = PackedVector3Array()
			_mesh.clear_surfaces()
		return
	var now := Time.get_ticks_msec()
	if now - _last_rebuild_ms < int(rebuild_interval * 1000.0):
		return
	# 只在时间线确实变动时重建
	var signature := "%d:%d" % [Timeline.cursor, Timeline.first]
	if signature == _last_signature:
		return
	_last_signature = signature
	_last_rebuild_ms = now
	rebuild()


func rebuild() -> void:
	var index := Timeline.get_entity_index(entity)
	_samples = Timeline.get_positions(index, max_points)
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	# 先把顶点算完再建面：空网格调 surface_end() 会报错
	var vertices := PackedVector3Array()
	for i in range(_samples.size() - 1):
		var a := _samples[i] + Vector3.UP * HEIGHT_OFFSET
		var b := _samples[i + 1] + Vector3.UP * HEIGHT_OFFSET
		var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if flat.length_squared() < 0.000001:
			continue
		var side := flat.normalized().cross(Vector3.UP).normalized() * (width * 0.5)
		vertices.append(a - side)
		vertices.append(a + side)
		vertices.append(b + side)
		vertices.append(a - side)
		vertices.append(b + side)
		vertices.append(b - side)
	if vertices.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for v in vertices:
		_mesh.surface_add_vertex(v)
	_mesh.surface_end()


## 采样点数（测试与调试用）
func sample_count() -> int:
	return _samples.size()


func samples() -> PackedVector3Array:
	return _samples


func set_trail_visible(value: bool) -> void:
	visible = value
