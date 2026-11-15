# HUD 编辑

更新：2026-11-12，转为个人白盒编辑器。

布局为 `scenes/hud.tscn`，在 2D 视口编辑；样式为 resources/ui/hud_theme.tres，控制器为 scripts/hud.gd。保留 CanvasLayer、Root 和主题，当前不预设 HUD 控件。原时间暂停按钮及其信号已删除。

世界 set_* / flash_message 等调用保留无界面兼容方法。台本字幕由独立对话层显示。验证见 tools/3c/test_3c.tscn 和 [转型记录](../cleanup/WHITEBOX_2026-11-12.md)。
