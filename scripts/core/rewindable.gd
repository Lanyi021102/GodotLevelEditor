class_name Rewindable
extends Node
## 组件：挂在需要被时间线回退的实体上。
##
## 默认只回退目标节点的 transform；复杂实体（玩家、分身、守卫、门）在自己的脚本里
## 实现 tl_capture() / tl_restore()，再由本组件委托过去（见 player_rewindable.gd）。

## 留空则使用父节点作为目标
@export var target_path: NodePath
## 世界轨迹线与 HUD 时间线上这条实体的颜色
@export var trail_color := Color(0.98, 0.98, 1.0, 0.55)
## HUD 上的名字（留空用节点名）
@export var display_name := ""
## 是否画世界轨迹线
@export var trail_enabled := true

var target: Node


func _ready() -> void:
	target = get_node_or_null(target_path) if target_path != NodePath() else get_parent()
	Timeline.register(self)


func _exit_tree() -> void:
	Timeline.unregister(self)


func tl_capture() -> Dictionary:
	if target is Node3D:
		return {"transform": (target as Node3D).global_transform}
	return {}


func tl_restore(state: Dictionary) -> void:
	if target is Node3D and state.has("transform"):
		(target as Node3D).global_transform = state["transform"]
