# 透明轮盘与白盒分页验证 · 2026-11-16

环境：Godot 4.7.1，macOS，实际渲染使用 Metal Forward+ / Apple M4。测试新建独立临时关卡，不保存覆盖用户制作的关卡。

| 检查 | 结果 |
|---|---|
| 无窗口原生编辑器：轮盘、分页、实例放置与存盘 | [107 项通过，0 失败](headless.txt) |
| 面／线／点与原生操作轴回归 | [47 项通过，0 失败](selection.txt) |
| Metal 实际编辑器、透明圆心及尺寸圆点移除截图 | [109 项通过，0 失败](metal.txt) |
| Wiki 构建与链接检查 | [16 页、985 个本地链接、44 个图片引用，0 错误](wiki.txt)；实际浏览器检查通过 |

本次逐一检查两页中的 16 个体块与对应素材路径；滚轮切换整页并循环，按下滚轮也可切下一页，圆心点击不选择素材。NPC 分类直接打开常驻、任务、已有素材三个扇区；已有素材搜索、原生输入、短按开关、动画、放置防穿透、撤销重做、实例属性和保存重开继续覆盖。所有素材源 `.tscn` 的 SHA-256 在检查前后相同。

橙色白边圆点来自 `block_gizmo.gd` 的自定义尺寸手柄；本次删除注册、绘制及拖动回调，保留范围线框、碰撞拾取和原生 subgizmo 接口。实际选择白盒后的界面见 [whitebox_selection.png](whitebox_selection.png)。

截图：[一级轮盘](wheel.png)、[白盒第一页](whitebox_page_1.png)、[白盒第二页](whitebox_page_2.png)、[NPC 二级轮盘](npc_submenu.png)。截图由真实编辑器渲染生成。

为避免其他编辑器回归窗口抢焦点或实际鼠标移动干扰，测试先显式检查失焦取消，再在当前测试进程中隔离该回调；每次注入窗口运动后固定输入，等待悬停动画结束。产品代码中的失焦取消保持。早期渲染失败定位为其他并行窗口与实际指针输入干扰，未通过修改产品行为绕过。

同步修改当前 Wiki 的关卡指南、快速开始、快捷键及版本记录；旧 V2 文档增加当前入口提示，历史实测结果保留。命名核对：本次使用“已有素材”“关卡常驻”“任务”“Layout 白盒”等既有术语，没有添加装饰性前缀或间隔点名称，没有改动稳定 ID、协议字段及用户资源路径。

复验命令：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path /Users/lanyi/branch -- --quick-add-test
/Applications/Godot.app/Contents/MacOS/Godot --editor --path /Users/lanyi/branch --resolution 1600x1000 -- --quick-add-test --capture-quick-add
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path /Users/lanyi/branch -- --face-gizmo-test
python3 tools/wiki/wiki.py check
```

编辑器退出仍会报告既有 1 个 ObjectDB 泄漏警告，日志保留该信息。
