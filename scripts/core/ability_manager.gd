extends Node
## 能力管理（Autoload: Abilities）
##
## 银河城式的元进度：能力是**跨时间线**的——回退时间轴不会把已解锁的能力收回去
## （这也是"回到旧房间用新能力开新路"能成立的前提，docs/GDD.md §7.1）。

signal unlocked(id: String)

const ALL := ["dash", "double_jump", "timeline_plus", "clone_plus"]
const NAMES := {
	"dash": "冲刺",
	"double_jump": "二段跳",
	"timeline_plus": "时间线延长",
	"clone_plus": "分裂强化",
}
## 解锁后分身上限变成多少（传进来的基础值会被覆盖）
const CLONE_LIMIT := {"clone_plus": 5}
var _unlocked: Dictionary = {}


func has(id: String) -> bool:
	return bool(_unlocked.get(id, false))


## 返回是否"这次真的解锁了"（重复拾取返回 false）
func unlock(id: String) -> bool:
	if id == "" or has(id):
		return false
	_unlocked[id] = true
	_apply_effects(id)
	unlocked.emit(id)
	return true


func _apply_effects(_id: String) -> void:
	pass

func clone_limit(base: int) -> int:
	var value := base
	for id in CLONE_LIMIT.keys():
		if has(id):
			value = maxi(value, int(CLONE_LIMIT[id]))
	return value


func list() -> Array:
	var out: Array = []
	for id in ALL:
		if has(id):
			out.append(id)
	return out


func display_names() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ALL:
		if has(id):
			out.append(String(NAMES.get(id, id)))
	return out


func snapshot() -> Array:
	return list()


func restore(ids: Array) -> void:
	_unlocked.clear()
	for id in ids:
		_unlocked[String(id)] = true


func clear() -> void:
	_unlocked.clear()
