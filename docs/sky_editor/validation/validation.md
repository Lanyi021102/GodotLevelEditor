# 天空编辑器 V1 验证 · 2026-11-15

Godot 4.7.1，macOS / Apple M4，Metal Forward+。

| 检查 | 结果 | 记录 |
|---|---|---|
| 天空运行组件（headless） | 32/32 | [runtime_headless.log](runtime_headless.log) |
| 天空编辑器、保存、HDRI 导入与实际渲染 | 28/28 | [editor_metal.log](editor_metal.log) |
| 原有关卡与套件（headless） | 56/56 | [suite_headless.log](suite_headless.log) |
| 独立关卡及主入口试玩 | 15/15 | [standalone.log](standalone.log) |
| 独立导出包读取 HDRI | `true` | [export_hdri.log](export_hdri.log) |
| 五种预设游戏画面 | 已检查 | [capture_metal.log](capture_metal.log) |

运行检查覆盖时刻／角度互斥、昼夜太阳、无效参数、私有环境、基线资源隔离、按米控制雾、云层高度、临时预览不创建绑定、结束预览恢复原环境、HDRI 旋转与补光分离，以及已保存天空引用经过真实 F6 PlaySession 的加载。

编辑检查覆盖草稿保护、同项重复选择、参数及天气整组撤销重做、预设保存、原生保存全部、场景绑定撤销、保存重开、关卡信息下拉框、新关卡默认值、外部 EXR 导入、HDRI 预设保存后重新加载仍引用项目内素材，以及 1504×1000 / 1100×760 两种窗口布局。所有测试素材和临时资源已清理。

游戏截图使用同一镜头、同一临时白盒遮挡物，物体未写入关卡。程序云层采用静态种子；云海未新增。

## 图像

- [天空面板](editor.png) · [窄窗口](editor_narrow.png)
- [原生视口天空预览](native_preview.png) · [中性检查](native_neutral.png)
- [晴朗](clear.png) · [阴天](overcast.png) · [黄昏](sunset.png) · [夜景](night.png) · [薄雾清晨](morning.png)

## 保留与已知边界

单次编辑器测试前后，用户关卡文件逐字节相同。V1 场景、V1/V2 Environment 资源与开工时 SHA-256 相同。开发期间关卡和配表出现过保存变化，保留其当前内容，没有用旧快照回退。最后审计与之前审计的差异见 [protected_files.json](protected_files.json)：白盒工作区发生过重新保存，当前仍引用“中性白盒”；其余列出的关卡、配表及基线未变。

编辑器测试退出阶段仍有既有 `Plugin is not attached to debugger` 和 `1 ObjectDB instance was leaked at exit` 输出；同类输出也出现在现有关卡套件回归日志。天空的 28 项检查通过，运行组件、游戏截图和独立 PCK 读取未出现此类错误。本次未扩展修改其他模块的调试插件销毁逻辑。

导出验证是独立 PCK 在源项目以外加载 EXR 的资源验证，未验证 Windows 可执行程序或移动平台。第一版不包含雨雪、天气过渡、真实太阳天文计算或动态昼夜循环。
