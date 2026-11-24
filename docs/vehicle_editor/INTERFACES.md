# 载具预设接口

轮盘通过 `asset_catalog.assets("载具")` 读取插件 `scenes/vehicles/` 和项目 `content/scenes/vehicles/` 中由载具脚本定义的原生场景。显示名读取根节点的 `display_name`。轮盘与已知素材拖放使用关卡新增事务，将实例放在 `Vehicles` 分组并设置原生场景所有权。检查器保存的预设是同一脚本的单根场景，保存可编辑配置及资源引用。每个关卡实例单独保存本地变换，运行时另有速度和乘员状态。

`modules/godot_level_editor_vehicle/vehicle.gd` 复用玩家交互筛选，支持汽车、摩托车、悬停飞行器三种驾驶方式。本地 -Z 为前方，使用米、米/秒和度/秒。模型、盒形碰撞、上下车标记和镜头分别配置。外观节点在运行和编辑预览时生成，由载具根统一管理。飞行器在有驾驶者时可悬停。当前乘员完成切换后发出 `mounted(actor)` 或 `dismounted(actor)`，供 Godot 场景连接。玩家预设旧资源缺少 `drive_vehicles` 时采用默认开启值。

<a id="vehicle-sources"></a>

## 模型与动画来源

- 卡丁车来自 [Kenney Car Kit](https://kenney.nl/assets/car-kit)。
- 摩托车来自 [Kenney Starter Kit Racing](https://github.com/KenneyNL/Starter-Kit-Racing#readme)。
- 悬停飞行器来自 [Kenney Space Kit](https://kenney.nl/assets/space-kit)。
- 坐下、坐姿和起身来自 [Quaternius Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html)。Godot 中的片段名为 `vehicle/Sitting_Enter`、`vehicle/Sitting_Idle` 和 `vehicle/Sitting_Exit`。

素材采用 CC0，插件内 `assets/vehicles/PROVENANCE.md` 记录了模型文件版本及调整。日常操作见 [载具预设](../wiki/guides/vehicles.md)。
