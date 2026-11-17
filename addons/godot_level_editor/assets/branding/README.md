# GodotLevelEditor 标志 · Open Room

等轴房间、门洞和两点连线分别对应白盒空间、关卡通行与节点逻辑。主色沿用套件的 `#2563eb`，顶面为 `#60a5fa`，暗面为 `#1742a6`。

- `res://icon.svg`：128 × 128 应用图标，浅色圆角底；保持原资源路径与 UID。
- `res://assets/branding/mark.svg`：16 × 16 透明紧凑标志，顶部 GodotLevelEditor 入口使用；`_get_plugin_icon()` 按编辑器缩放倍率从 SVG 栅格化，2 倍界面输出 32 × 32 纹理，不随主题替换品牌颜色。
- `docs/wiki/assets/logo.svg`：与根 `icon.svg` 内容一致，供 Wiki 页头和 favicon 使用。修改应用版后同步此文件。

图形全部由 SVG 路径组成，无字体、外链或位图依赖。应用版与紧凑版保留相同的房间和连线几何；紧凑版去掉底板并收紧留白。既有编辑器会话的主屏按钮可能缓存旧拼图图标，重新加载套件插件或重开工程后读取新标志。

实际验证见 [Logo 验证记录](../../docs/godot_level_editor_suite/logo_2026-11-16/validation.md)。
