extends Rewindable
## 角色（玩家 / 分身）的回退适配器：把状态采集与恢复委托给宿主角色脚本。


func tl_capture() -> Dictionary:
	if target != null and target.has_method("tl_capture"):
		return target.tl_capture()
	return super.tl_capture()


func tl_restore(state: Dictionary) -> void:
	if target != null and target.has_method("tl_restore"):
		var locked_clone: bool = target.has_method("is_clone") and target.is_clone()
		target.tl_restore(state)
		if "spawn_frame" in target:
			target.visible = true
			target.set_physics_process(true)
			target.set_collision_layer_value(2, true)
			if locked_clone: target.mode = target.Mode.REPLAY
		return
	super.tl_restore(state)


## 该帧这个角色还不存在（例如尚未分裂出的分身）：隐身并停止处理
func tl_absent() -> void:
	if target is Node3D:
		(target as Node3D).visible = false
		if "spawn_frame" in target:
			target.set_physics_process(false)
			target.set_collision_layer_value(2, false)
