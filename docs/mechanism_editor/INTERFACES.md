# 机关专项接口（v1，2026-10-30）

## 米制网格可选表现 · 2026-11-02

`PowerDoor` 与 `runtime/lever.gd` 新增 `use_metric_grid: bool = false`，3C Playground 显式开启。开启后共用 `scripts/tools/metric_grid.gd` 的 1 / 0.5 / 0.1 m 网格，继续响应颜色参数、开合、供电及无副作用快照恢复；编辑器切换开关会重建表现。没有更改图资源版本、交互、连线、碰撞或快照字段。其余已有机关资源维持原参数。验证见 [材质专项](../whitebox_grid/README.md)。

遵循 [蓝图工具链规范](../tools/BLUEPRINT_TOOLCHAIN.md)。本专项不改玩家、Timeline、SaveSystem 与正式关卡组装。

## 资源与实例

- 插件：`res://addons/branch_mechanisms/plugin.cfg`；主工作区“机关蓝图”。
- `runtime/assembly.gd` 是独立 `.tscn` 根节点；`definition` 引用同名 `.graph.tres`（格式版本 1）。
- `.tscn` 只维护组件参数、变换、对象 ID；`.tres` 维护图节点、具名端口、连线、节点参数及排版。运行状态不写回定义。
- 图节点 `id`、端口名称、组件 `object_id` 为稳定引用；显示名、节点名和画布位置不参与引用。
- 完整对象引用为 `(assembly.instance_id, object_id)`。关卡编辑器复制/摆放独立组合时须分配新的 `instance_id`；局部 object_id 保留，以复用同一图定义。机关画布复制组件节点会同时复制三维对象，分配新的 node ID 与 object_id。
- 同一组合内 object_id 重复会验证失败；Godot 原生复制场景对象后需要重新绑定。推荐从机关图复制。
- `Factory.component(kind, id)` 创建 `lever` / `plate` / `door`；`Factory.sample()` 创建标准 AND 样例。
- `Store.validate(root)`、`Store.save_pair(root, path)`、`Store.load_pair(path)` 用于验证与成对读写。保存使用旧文件备份，写入失败回滚；不支持的版本拒绝保存/载入。

## 玩家与回放（交总控接入）

- 拉杆加入 `branch_interactable` 组；`can_interact(actor: Node3D)` 检查 enabled、一次性状态、可见性与世界距离；`interact(actor)` 返回是否成功。
- `interact(null)` 用于明确的脚本驱动和隔离预览；玩家与回放应传实际角色，不以 null 绕过距离检查。
- 成功主动交互发出 `interacted(object_id, "interact", actor)`。总控在玩家输入日志记录组合实例 ID、对象 ID、动作与物理帧；回放重新解析对象并调用同一接口。
- `is_powered()` 读取布尔状态；拉杆/门提供 `power_changed(bool)`。图执行器轮询状态，不依赖恢复时重发事件。
- 能量、动画与交互按键由宿主负责；本组件不扣能量、不监听全局输入。成功与扣能量的原子顺序由总控协调。

## 图执行与回溯

- `assembly.configure()` 收集局部绑定并验证；`step()` 只推进一个 60 Hz 逻辑帧；默认由 `_physics_process` 调用，优先级 -10。
- 连续数据按拓扑排序求值，同级按稳定 node ID 排序；门在后续自身物理更新推进碰撞和外观。事件相位在数据相位之后，因此事件修改源状态于下一逻辑帧影响门。
- 端口：BOOL / NUMBER / OBJECT / EVENT。上升沿是显式 BOOL→EVENT 转换；延迟是至少下一帧的有状态推进。每帧事件预算 64，待处理上限 256；组合逻辑循环拒绝。
- 图内门每帧先撤销旧目标再求值，断线或配置错误不会遗留开门命令。图内门的旧 `source_paths/power_nodes` 应为空。
- `assembly.tl_capture()/tl_restore(state)` 覆盖帧号、前值、待处理事件、调试状态和各对象状态；包括拉杆计时、一次性状态、压力板延时、门开合比例。恢复不重执行主动交互。
- 总控应只注册组合根的快照，避免又给子组件重复注册；冻结、分身回放及存档策略沿用公共时间线。可用现有委托型回退适配器，但应由总控确认冻结归属后接入。
- 需单独保存永久解锁等世界进度，本版不把房间机关状态写进正式 SaveSystem。

## 兼容与调试

- `runtime/door.gd` 继承既有 `PowerDoor`，保留 `add_power_source`、`source_paths`、`is_open`、`tl_capture/tl_restore` 等接口。新门以地面为固定原点；旧 PowerDoor 仍按原逻辑移动根节点。
- 公共变更仅 `scripts/world/power_door.gd`：支持工具模式、可重复构建几何、编辑器中不运行供电物理更新。压力板运行逻辑直接委托原 `PressurePlate`。
- 调试消息 `branch_mechanism:state/remove` 由独立 EditorDebuggerPlugin 接收。运行实例按编辑器会话与实际场景路径区分，包带 definition_id；UI 按 definition_id 与图资源路径校验其与当前图对应。隔离预览明确使用场景副本。
- 关卡编辑器按 `.tscn` 实例摆放，图的局部绑定不依赖外部 NodePath；跨组合、关卡事件或敌人事件的桥接留给总控协调。

## 后续

草丛（隐蔽状态/检测体）和梯子（接驳点/攀爬能力）尚未实现；待对应运行组件接口明确后注册节点类型，不在图执行器内实现角色能力。

## 总控 3C 接口更新 · 2026-11-02

共享玩家与会话已切换到 WASD/Shift/空格、Q/E 浏览后暂停、T 继续、R 固定录像分身、F 主动交互。允许回到分身生成前，已有录像不被改写。HUD 仅保留暂停按钮，能量玩法移除。组合的 can_interact/interact 与无副作用快照接口不变，玩家/分身实际接入交互记录及回放。具体合同和验证见 [3C Playground](../3cplayground/README.md)。本次未修改编辑器实现或用户关卡与机关资源。
