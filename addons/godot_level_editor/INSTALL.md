# 安装和更新插件

需要 Godot 4.7.1 标准版。使用者不需要 Python、Excel 或完整开发工程。

1. 从 GitHub Releases 下载 `GodotLevelEditor-版本号.zip`，不要选择 Source code。
2. 将 ZIP 的 `addons/godot_level_editor/` 放入自己的 Godot 工程。
3. 等待导入完成，在“项目设置 → 插件”中启用 **GodotLevelEditor**。
4. 新建地图与试玩见[快速开始](https://lanyi021102.github.io/GodotLevelEditor/wiki/getting-started/)。

插件内包含五种独立机关、13 个 NPC 示例、角色、镜头、HUD、模型动画、光照与天空预设。现成地图不进入插件包。

第一次启用会建立 `content/` 和空配表。若工程尚未设置主场景，还会创建空白起始场景并设为主场景；直接点击 Godot 播放或按 F5，即可操控默认角色。已有配表、输入动作、已设置的主场景和渲染设置保持；缺少的默认按键会补齐，三个运行服务使用 GLE 前缀。

## 插件和作品放在哪里

| 内容 | 默认位置 |
|---|---|
| 插件代码与运行组件 | `addons/godot_level_editor/` |
| 空白关卡模板 | `addons/godot_level_editor/templates/empty_level.tscn` |
| 地图 | `content/scenes/levels/`，也可原生另存到其他工程目录 |
| 自建机关／NPC 场景 | `content/scenes/mechanisms/`、`content/scenes/npcs/` |
| NPC 定义 | `content/resources/enemies/` |
| 任务图 | `content/resources/task_graphs/` |
| 配表 | `content/tables/` |
| 自定义天空和 HDRI | `content/resources/sky_presets/custom/`、`content/assets/sky_hdri/` |

内置素材在插件目录中。修改前先另存到作品目录；插件目录内的修改会随更新被替换。

## 更新与禁用

关闭 Godot 后替换 `addons/godot_level_editor/`，保留 `content/`。不要把插件安装到同名插件已经存在的源码开发工程中。

禁用主插件会停用编辑模块，但保留作品、输入和运行服务，让已制作的关卡仍可运行。彻底删除插件前，需要先处理作品对插件脚本、模型和角色的依赖，并从项目设置中移除 GLELightZones、GLENoiseBus、GLESaveSystem 三个自动加载项。

兼容版本以发布包 `manifest.json` 及本版验证为准。MIT 与第三方许可随插件提供。
