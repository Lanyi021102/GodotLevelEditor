# Changelog

## 2026-11-17 — Plugin structure workflow regression fixes

My Levels browses real scene files while maps retain native saving and F6; Level Editing provides persistent logic. Fixes cover Save As identity/registration, indexed destination replacement, saved thumbnails, personal copies of built-in NPCs/mechanisms, NPC scene/import locations and generated collision dimensions, inherited sky references, save-time reference refresh and HDRI retry after cancellation. See the [scope and actual checks](../qa/structure_2026-11-17/validation.md).

## 2026-11-17 — Restore Level secondary navigation

The Level page restores **我的关卡** (My Levels) and **关卡编辑** (Level Editing). Browse real `.tscn` files, search, open, locate or create an inherited map from the template. Switching pages preserves unsaved graph edits and UndoRedo. Native saves, moves and deletions update the browser. See the [guide](guides/levels.md) and [browser checks](../godot_level_editor_suite/level_browser_2026-11-17/validation.md); the [earlier single-entry checks](../godot_level_editor_suite/level_navigation_2026-11-17/validation.md) remain as historical evidence.

## 2026-11-17 — Complete addon and native scenes

The addon, built-ins and runtime components are grouped under `addons/godot_level_editor/`; author content is under `content/`. Project Excel data is in `content/tables/`. All project folders use English names.

Maps use Godot's native scene tree, FileSystem, 3D viewport, save and F6, while retaining the wheel and face/edge/point tools. The separate Level page edits current-scene persistent logic. Native saves register task level IDs and native file notifications update index paths.

Activation in an empty project creates a start scene for F5 with the included player/camera/HUD. Existing main scenes and input bindings remain. Single-entry activation, MIT licensing, map-free installation ZIPs and GitHub release automation were added. See [installation](plugin-install.md) and [actual validation](../cleanup/plugin_2026-11-17/validation.md).

Chinese/English documentation and README feature screenshots are maintained alongside the current code.

## 2026-11-16 — Editor and example updates

The earlier work added rigged NPC examples, model/animation import, five independent mechanism assets, rotating-door state/curve nodes, task graph categories and ownership synchronization, free/stationary dialogue, Room triggers, native object-reference drag/drop, placement grouping, viewport selection tools, sky controls and display preferences.

Older dated entries and detailed test counts are retained in the original Chinese changelog and module records. They are historical evidence, not a blanket current-release retest claim. Removed timeline/clone/energy systems and the removed custom map-card workflow are not current features.
