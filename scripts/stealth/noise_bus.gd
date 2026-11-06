extends Node
## 噪音总线（Autoload: NoiseBus —— 不能叫 Noise，那是 Godot 内置类名）
##
## 设计依据：docs/GDD.md §6.1 —— 跑动 8 m、落地 5 m、开门 6 m 的噪音脉冲，
## 蹲行完全无声。凡是在 "hearing" 组里、且实现了 heard_noise(pos, radius, source) 的节点
## 都会收到脉冲；返回 true 表示确实听到了。
##
## 分身同样会发出噪音——这就是"拿分身当诱饵"的机制基础。

signal pulse(position: Vector3, radius: float, source: Object)

## 最近一次脉冲（供 HUD / 测试查看）
var last_position := Vector3.ZERO
var last_radius := 0.0
var last_source: Object = null
var pulse_count := 0
## 统计：某次脉冲被几个监听者听到
var last_heard_count := 0


func emit_pulse(position: Vector3, radius: float, source: Object = null) -> int:
	pulse_count += 1
	last_position = position
	last_radius = radius
	last_source = source
	pulse.emit(position, radius, source)
	var heard := 0
	for node in get_tree().get_nodes_in_group("hearing"):
		if node.has_method("heard_noise") and node.heard_noise(position, radius, source):
			heard += 1
	last_heard_count = heard
	return heard


func clear() -> void:
	pulse_count = 0
	last_heard_count = 0
	last_source = null
