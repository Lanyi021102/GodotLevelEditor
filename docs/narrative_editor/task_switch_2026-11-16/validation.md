# 任务图连续切换修复验证 · 2026-11-16

原因：套件在当前任务图 dirty 时直接中止打开另一图，仅写入事件页状态文字；同一路径重复打开还会加载另一份 Resource，与共享面板的未保存保护冲突。用户缺少可操作的切换反馈。

修复：未保存图切换显示保存后打开／放弃修改并打开／取消；保存失败保留当前图和错误提示。重复打开同一路径复用当前图，保留编辑内容和撤销。独立文件打开使用相同保护，成功后清除旧任务 ID 绑定。配表、用户任务图和运行语义不变。

Godot 4.7.1，先 headless，再 Metal Forward+ 实际渲染。

| 检查 | 结果 | 日志 |
|---|---|---|
| 连续打开与未保存处理 | 13 项通过，0 失败 | [headless.txt](headless.txt) |
| Metal 实际渲染与同一流程 | 13 项通过，0 失败 | [render.txt](render.txt) |
| 任务节点编辑回归 | 100 项通过，0 失败 | [nodes.txt](nodes.txt) |
| Wiki 构建、当前链接与搜索 | ok=true，0 错误 | [wiki.txt](wiki.txt) |

测试在内存临时事件表中建立 A/B 两项任务，通过实际 Tree 编辑列的 gui_input 调用打开流程，重复 A→B→A；同时覆盖当前图重开、取消、保存成功／失败、放弃后重开、独立文件打开及任务 ID。临时任务图位于 user://，不写用户工作簿。编辑器退出时仍有已有调试插件退场／ObjectDB 提示，测试断言全部通过。

实际检查截图：[任务图页](切换任务图.png)、[未保存选择弹窗](未保存提示.png)。Wiki 仅更新正文与版本记录，未调整页面布局。

复现：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/lanyi/branch --editor -- --godot-level-editor-suite-test --task-switch
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/lanyi/branch --editor -- --godot-level-editor-suite-test --task-switch --capture
python3 tools/wiki/wiki.py check
```
