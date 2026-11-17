# Changelog

## 2026-11-17 — Complete addon and native scenes

The addon, built-ins and runtime components are grouped under `addons/godot_level_editor/`; author content is under `content/`. Project Excel data is in `content/tables/`. All project folders use English names.

Maps use Godot's native scene tree, FileSystem, 3D viewport, save and F6, while retaining the wheel and face/edge/point tools. The separate Level page edits current-scene persistent logic. Native saves register task level IDs and native file notifications update index paths.

Activation in an empty project creates a start scene for F5 with the included player/camera/HUD. Existing main scenes and input bindings remain. Single-entry activation, MIT licensing, map-free installation ZIPs and GitHub release automation were added. See [installation](plugin-install.md) and [actual validation](../cleanup/plugin_2026-11-17/validation.md).

Chinese/English documentation and README feature screenshots are maintained alongside the current code.

## 2026-11-16 — Editor and example updates

The earlier work added rigged NPC examples, model/animation import, five independent mechanism assets, rotating-door state/curve nodes, task graph categories and ownership synchronization, free/stationary dialogue, Room triggers, native object-reference drag/drop, placement grouping, viewport selection tools, sky controls and display preferences.

Older dated entries and detailed test counts are retained in the original Chinese changelog and module records. They are historical evidence, not a blanket current-release retest claim. Removed timeline/clone/energy systems and the removed custom map-card workflow are not current features.
