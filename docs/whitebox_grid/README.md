# 白盒米制网格 · 2026-11-02

默认白盒与 3C Playground 使用灰底、浅色三级尺度线。Godot 世界单位约定为米：**1 m 粗网格、0.5 m 中线、0.1 m 细网格**。每个大格包含 10×10 个小格，中线将大格分为四块。

## 使用与覆盖

- 白盒编辑器的 16 种形状，包括已有白盒、新建房间地板、原生拖放、面推拉和运行实例，自动使用网格；`tint` 继续控制底色。
- `scenes/3cplayground.tscn` 的地面、跑道标记、高低箱、跳台、窄梁、门框、门板、拉杆均接入；人物和文字标注继续使用自身材质。
- 普通 MeshInstance3D 可将 `resources/materials/whitebox_metric_grid.tres` 拖到 Material Override。该资源与 `assets/shaders/whitebox/metric_grid.gdshader` 提供颜色、间距、线宽参数；脚本生成对象通过 `scripts/tools/metric_grid.gd` 取得独立底色与状态参数。
- 门与拉杆新增可选 `use_metric_grid`，Playground 已开启；打开、通电和回溯恢复继续更新底色及发光。其他场景现有机关参数不自动改变。
- `visual_scene` 指定的自建表现模型继续使用自带材质。没有改写用户关卡、机关资源或光照 V1。

## 尺度与呈现

网格使用世界坐标和每个几何面的单位切向基，不依赖 UV。非等比缩放、旋转、面推拉后，网格仍按米计；斜面沿表面量取，不把水平投影距离误作斜面距离。同一平面的物件共享网格相位，世界原点为网格参考原点，格线不保证从每个物件边缘起算。

圆柱、球、圆锥和弧形预设改用世界坐标三向混合投影，避免逐三角面换向、断裂；格子表示各世界轴的米制投影，不是沿曲面弧长的连续展开标尺。普通平面、墙面和直线斜坡使用表面切向刻度。移动或旋转物件时网格会重新对齐世界参考。

材质继续接受场景日光、阴影和雾；没有启用无光照或覆盖光照 V1。线宽使用米制和像素覆盖抗锯齿，远处先淡出无法辨识的 0.1 m 细线，接近后重新出现。

## 参考

此类材质通常称为 Prototype Grid / Blockout Material / Dev Texture。参考了作者公开的 [Prototype Grid](https://godotshaders.com/shader/prototype-grid/) 的用途和三维网格类别，项目的三级米制着色器独立编写，没有复制第三方代码或纹理。坐标与导数接口依据 [Godot spatial shader 官方文档](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)。

## 验证

Godot 4.7.1，先无界面检查，再用 Metal / Forward+ 实际渲染。

- 网格专项：22 项无界面检查通过；32 项图形检查通过，包含所有 16 种形状、Playground 32 个网格表现、独立底色、替换模型保留与机关状态恢复。
- 图形检查直接读取 GPU 输出：地面、任意方向斜面、旋转墙面在非等比缩放后，正负坐标的格线位置与 1 / 0.5 / 0.1 m 对齐；同时检查三级线强度递增。
- 既有回归：面推拉 20 项、关卡 V2 98 项、原生编辑器 35 项、机关 48 项、3C 33 项，全部通过。
- 日志见 `validation/`；运行图见 [测试场全景](playground_overview.png)、[近景](playground_detail.png)、[16 种形状](shapes.png)、[当前默认世界](current_world.png)。标定图 `calibration_*.png` 为独立中性补光环境中的真实 GPU 输出。测试场截图使用场景当前指定的光照；形状合集单独使用保留的光照 V1。

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch res://tools/whitebox_grid/test_metric_grid.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/lanyi/branch --resolution 1600x1000 res://tools/whitebox_grid/test_metric_grid.tscn -- --grid-render
```
