extends Node
## 明暗分区（Autoload: LightZones）
##
## 设计依据：docs/GDD.md §6.1 —— 暗区里守卫视距 ×0.4，玩家进入暗区 HUD 显示"隐蔽"。
##   - 静态暗区：关卡生成器启动时注册（同时在地面画深色块，方便玩家看出哪里是暗的）
##   - 动态暗区：机关控制（例如拉下电闸把房间的灯关掉）

const LIT := 1.0
const DARK_DEFAULT := 0.32
const DARK_THRESHOLD := 0.75

var _zones: Array[AABB] = []
var _levels: PackedFloat32Array = []
## 动态区域：[{ box: AABB, level: float, enabled: bool }]
var _dynamic: Array = []


func clear() -> void:
	_zones.clear()
	_levels.clear()


func register_box(box: AABB, level := DARK_DEFAULT) -> void:
	_zones.append(box)
	_levels.append(level)


func register_box_center(center: Vector3, size: Vector3, level := DARK_DEFAULT) -> void:
	register_box(AABB(center - size * 0.5, size), level)


## 注册一块可开关的暗区（例如"拉下电闸后房间变黑"），返回 id
func register_dynamic_box_center(center: Vector3, size: Vector3, level := DARK_DEFAULT) -> int:
	_dynamic.append({"box": AABB(center - size * 0.5, size), "level": level, "enabled": false})
	return _dynamic.size() - 1


func set_dynamic_enabled(id: int, enabled: bool) -> void:
	if id >= 0 and id < _dynamic.size():
		_dynamic[id]["enabled"] = enabled


func dynamic_enabled(id: int) -> bool:
	if id >= 0 and id < _dynamic.size():
		return bool(_dynamic[id]["enabled"])
	return false


func dynamic_count() -> int:
	return _dynamic.size()


func clear_dynamic() -> void:
	_dynamic.clear()


## 该点的光照系数（1.0 = 明亮，越小越暗）
func level_at(pos: Vector3) -> float:
	var best := LIT
	for i in _zones.size():
		if _zones[i].has_point(pos):
			best = minf(best, _levels[i])
	for entry in _dynamic:
		if bool(entry["enabled"]) and (entry["box"] as AABB).has_point(pos):
			best = minf(best, float(entry["level"]))
	return best


func is_dark(pos: Vector3) -> bool:
	return level_at(pos) < DARK_THRESHOLD


func zone_count() -> int:
	return _zones.size()


func zones() -> Array[AABB]:
	return _zones


## 移除最近注册的一个静态区域（测试/临时暗区用）
func pop_zone() -> void:
	if _zones.is_empty():
		return
	_zones.remove_at(_zones.size() - 1)
	_levels.remove_at(_levels.size() - 1)
