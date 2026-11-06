# HUD 编辑

更新：2026-11-02，按新的 3C 操作合同简化。

布局为 `scenes/hud.tscn`，直接在 2D 视口编辑；样式为 `resources/ui/hud_theme.tres`，控制器为 `scripts/hud.gd`。

Root 只保留左上角 PauseButton，发出 pause_requested。按钮显示暂停/继续图标，T 继续。HUD 不再接收旧键盘操作，不显示能量、时间轴、帮助、目标、分身数或结果面板。空格交给跳跃，Q/E/R/F/T 由共享会话和角色处理。

世界 set_* / flash_message 等调用暂保留无界面兼容方法。旧能量条和时间轴 HUD 组件已删除。验证入口 `tools/3c/test_3c.tscn`；`tools/hud/test_hud.tscn` 也运行相同集成检查。规则与验证见 `../3cplayground/README.md`。
